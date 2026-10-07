import Fastify, { type FastifyInstance } from "fastify";
import rateLimit from "@fastify/rate-limit";
import { z } from "zod";
import { type Config } from "./config.js";
import { AutocompleteBody, ComputeRoutesBody, GoogleClient, GoogleError, NearbyBody, RouteMatrixBody, type DetailLevel } from "./google.js";
import { Metrics } from "./metrics.js";
import { buildRemoteConfig } from "./remoteConfig.js";
import { EventsBody } from "./analytics.js";

export function buildApp(cfg: Config, deps?: { google?: GoogleClient; metrics?: Metrics }): FastifyInstance {
  const app = Fastify({ logger: { level: cfg.LOG_LEVEL }, bodyLimit: 256 * 1024 });
  const metrics = deps?.metrics ?? new Metrics(cfg.skuPrices);
  const google = deps?.google ?? new GoogleClient(cfg, metrics);
  const remote = buildRemoteConfig(cfg.CONFIG_OVERRIDES_PATH);

  app.register(rateLimit, {
    max: cfg.RATE_LIMIT_PER_MIN,
    timeWindow: "1 minute",
    keyGenerator: (req) => (req.headers["x-app-key"] as string | undefined) ?? req.ip,
  });

  // تحقق مفتاح التطبيق (X-App-Key أو ?k= لطلبات الصور التي يفتحها AsyncImage بلا رؤوس).
  app.addHook("onRequest", async (req, reply) => {
    if (req.url.startsWith("/healthz") || req.url.startsWith("/metrics")) return;
    if (cfg.ALLOW_NO_APP_KEY) return;
    const key = (req.headers["x-app-key"] as string | undefined) ?? (req.query as { k?: string }).k;
    if (!key || !cfg.appKeys.has(key)) {
      reply.code(401).send({ error: "invalid app key" });
    }
  });

  app.setErrorHandler((err, _req, reply) => {
    if (err instanceof GoogleError) {
      if (err.retryAfter) reply.header("Retry-After", err.retryAfter);
      const status = err.status === 429 ? 429 : err.status >= 500 ? 502 : err.status === 404 ? 404 : 502;
      return reply.code(status).send({ error: err.message, upstreamStatus: err.status });
    }
    if (err instanceof z.ZodError) return reply.code(400).send({ error: "validation", issues: err.issues });
    if ((err as { statusCode?: number }).statusCode === 429) return reply.code(429).send({ error: "rate limited" });
    app.log.error(err);
    return reply.code(500).send({ error: "internal" });
  });

  app.get("/healthz", async () => ({ ok: true, version: remote.config.version }));
  app.get("/metrics", async () => metrics.snapshot());

  // Remote Config مع ETag/304.
  app.get("/v1/config", async (req, reply) => {
    if (req.headers["if-none-match"] === remote.etag) return reply.code(304).send();
    reply.header("ETag", remote.etag).header("Cache-Control", "max-age=300").type("application/json");
    return remote.body;
  });

  // Routes API
  app.post("/v1/routes/compute", async (req) => google.computeRoutes(ComputeRoutesBody.parse(req.body)));
  app.post("/v1/routes/matrix", async (req) => google.computeRouteMatrix(RouteMatrixBody.parse(req.body)));

  // Places API (New)
  app.post("/v1/places/nearby", async (req) => google.searchNearby(NearbyBody.parse(req.body), remote.config.flags.atmosphereFieldsEnabled));

  app.get("/v1/places/photo", async (req, reply) => {
    const q = z.object({ name: z.string().regex(/^places\/[^/]+\/photos\/[^/]+$/), maxWidthPx: z.coerce.number().int().min(1).max(4800).default(800) }).parse(req.query);
    if (!remote.config.flags.photosEnabled) return reply.code(404).send({ error: "photos disabled" });
    const uri = await google.photoUri(q.name, q.maxWidthPx);
    // إعادة توجيه مباشرة إلى Google؛ لا نحفظ الصورة ولا الرابط.
    return reply.header("Cache-Control", "no-store").redirect(uri, 302);
  });

  app.get("/v1/places/:id", async (req) => {
    const { id } = z.object({ id: z.string().min(1).max(512) }).parse(req.params);
    const q = z.object({ level: z.enum(["basic", "card", "full"]).default("basic"), languageCode: z.string().min(2).max(10).default("ar"), sessionToken: z.string().max(128).optional() }).parse(req.query);
    return google.placeDetails(id, q.level as DetailLevel, q.languageCode, q.sessionToken);
  });

  app.post("/v1/places/autocomplete", async (req) => google.autocomplete(AutocompleteBody.parse(req.body)));

  // التحليلات: تحقق صارم ثم سجل منظّم (يُوصَل لاحقًا بـ BigQuery/ClickHouse عبر سجلات stdout).
  app.post("/v1/analytics/events", async (req, reply) => {
    const body = EventsBody.parse(req.body);
    for (const e of body.events) app.log.info({ analytics: true, event: e.name, params: e.params, ts: e.timestamp, appVersion: req.headers["x-app-version"] }, "event");
    return reply.code(202).send({ accepted: body.events.length });
  });

  return app;
}
