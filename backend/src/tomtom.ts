import { z } from "zod";
import type { Config } from "./config.js";
import type { Metrics } from "./metrics.js";
import { GoogleError } from "./google.js";

/**
 * عميل TomTom (Routing API v1، Matrix Routing v2، Search API v2، POI Details).
 * الخطة المجانية بلا بطاقة: توجيه 20K/شهر، بحث 2.5K/شهر، مصفوفة 2.5K خلية/شهر.
 * لذلك: نكتفي بطلب بحث قريب واحد (حتى 100 نتيجة)، ونحسب ETA عبر طلبات توجيه ملخّصة
 * (TRAVEL_TIME_MODE=routes) بدل المصفوفة ما لم يُضبط TRAVEL_TIME_MODE=matrix.
 */

const Point = z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) });

export const TTRoutesBody = z.object({
  origin: Point,
  destination: Point,
  languageCode: z.string().min(2).max(10).default("ar"),
  avoidTolls: z.boolean().default(false),
  maxAlternatives: z.number().int().min(0).max(5).default(3),
});

export const TTMatrixBody = z.object({
  origin: Point,
  destinations: z.array(Point).min(1).max(100),
});

export const TTNearbyBody = z.object({
  center: Point,
  radiusMeters: z.number().positive().max(50_000),
  categorySet: z.array(z.number().int().positive()).min(1).max(10),
  limit: z.number().int().min(1).max(100).default(100),
  languageCode: z.string().min(2).max(10).default("ar"),
});

export const TTSearchBody = z.object({
  query: z.string().min(1).max(200),
  center: Point.optional(),
  radiusMeters: z.number().positive().max(100_000).optional(),
  limit: z.number().int().min(1).max(20).default(7),
  languageCode: z.string().min(2).max(10).default("ar"),
  countrySet: z.array(z.string().length(2)).max(5).default(["SA"]),
});

export class TomTomClient {
  constructor(private readonly cfg: Config, private readonly metrics: Metrics) {}

  private get key(): string {
    if (!this.cfg.TOMTOM_API_KEY) throw new GoogleError(503, "TOMTOM_API_KEY غير مضبوط على الخادم");
    return this.cfg.TOMTOM_API_KEY;
  }

  private async call<T>(endpoint: string, sku: string, url: string, init: RequestInit = {}, raw = false): Promise<T> {
    const started = Date.now();
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), this.cfg.GOOGLE_TIMEOUT_MS);
    try {
      const res = await fetch(url, { ...init, signal: ac.signal });
      if (!res.ok) {
        const text = await res.text();
        this.metrics.record(endpoint, Date.now() - started, true, sku);
        let message = `tomtom ${endpoint} failed (${res.status})`;
        try { message = JSON.parse(text)?.detailedError?.message ?? JSON.parse(text)?.errorText ?? message; } catch { /* ignore */ }
        throw new GoogleError(res.status, message, res.headers.get("retry-after") ?? undefined);
      }
      this.metrics.record(endpoint, Date.now() - started, false, sku);
      if (raw) return res as unknown as T;
      const text = await res.text();
      return (text ? JSON.parse(text) : {}) as T;
    } catch (e) {
      if (e instanceof GoogleError) throw e;
      this.metrics.record(endpoint, Date.now() - started, true, sku);
      const aborted = (e as Error).name === "AbortError";
      throw new GoogleError(aborted ? 504 : 502, aborted ? `tomtom ${endpoint} timeout` : `tomtom ${endpoint} network error`);
    } finally {
      clearTimeout(timer);
    }
  }

  private routeUrl(o: z.infer<typeof Point>, d: z.infer<typeof Point>, params: Record<string, string>) {
    const q = new URLSearchParams({ key: this.key, ...params });
    return `https://api.tomtom.com/routing/1/calculateRoute/${o.latitude},${o.longitude}:${d.latitude},${d.longitude}/json?${q}`;
  }

  /** الطرق: الأسرع + بدائل (مرور حي، أقسام مرور، إرشادات) ثم أقصر مسافة مرجعي. */
  async routes(body: z.infer<typeof TTRoutesBody>) {
    const base: Record<string, string> = {
      travelMode: "car", traffic: "true", departAt: "now", routeRepresentation: "polyline",
      instructionsType: "text", language: body.languageCode === "ar" ? "ar" : body.languageCode,
      sectionType: "traffic", computeTravelTimeFor: "all",
    };
    if (body.avoidTolls) base.avoid = "tollRoads";
    const [primary, shortest] = await Promise.all([
      this.call<unknown>("tt.routes", "tt.routing", this.routeUrl(body.origin, body.destination, { ...base, routeType: "fastest", maxAlternatives: String(body.maxAlternatives) })),
      this.call<unknown>("tt.routes", "tt.routing", this.routeUrl(body.origin, body.destination, { ...base, routeType: "shortest", maxAlternatives: "0" })).catch(() => null),
    ]);
    return { primary, shortest };
  }

  /** ETA فعلي لعدة وجهات. matrix = Matrix Routing v2 (خلية لكل وجهة)، routes = طلب توجيه ملخّص لكل وجهة (موازاة 8). */
  async matrix(body: z.infer<typeof TTMatrixBody>) {
    if (this.cfg.TRAVEL_TIME_MODE === "matrix") {
      const q = new URLSearchParams({ key: this.key });
      const payload = {
        origins: [{ point: body.origin }],
        destinations: body.destinations.map((p) => ({ point: p })),
        options: { departAt: "now", routeType: "fastest", traffic: "live", travelMode: "car" },
      };
      return this.call<unknown>("tt.matrix", "tt.matrix", `https://api.tomtom.com/routing/matrix/2?${q}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload),
      });
    }
    const results: { originIndex: number; destinationIndex: number; routeSummary?: unknown }[] = [];
    const concurrency = 8;
    let next = 0;
    const worker = async () => {
      while (next < body.destinations.length) {
        const i = next++;
        try {
          const r = await this.call<{ routes?: { summary?: unknown }[] }>("tt.routes.summary", "tt.routing",
            this.routeUrl(body.origin, body.destinations[i], { travelMode: "car", traffic: "true", departAt: "now", routeRepresentation: "summaryOnly", routeType: "fastest", maxAlternatives: "0" }));
          results.push({ originIndex: 0, destinationIndex: i, routeSummary: r.routes?.[0]?.summary });
        } catch {
          results.push({ originIndex: 0, destinationIndex: i });
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(concurrency, body.destinations.length) }, worker));
    return { data: results.sort((a, b) => a.destinationIndex - b.destinationIndex) };
  }

  nearby(body: z.infer<typeof TTNearbyBody>) {
    const q = new URLSearchParams({
      key: this.key, lat: String(body.center.latitude), lon: String(body.center.longitude), radius: String(Math.round(body.radiusMeters)),
      categorySet: body.categorySet.join(","), limit: String(body.limit), language: body.languageCode, openingHours: "nextSevenDays", view: "Unified",
    });
    return this.call<unknown>("tt.nearby", "tt.search", `https://api.tomtom.com/search/2/nearbySearch/.json?${q}`);
  }

  /** بحث نصي بإكمال تلقائي. العربية: إن قلّت النتائج نعيد المحاولة بلا «ال» التعريف (بيانات TomTom تخزّن «بوليفارد الرياض» لا «البوليفارد»). */
  async search(body: z.infer<typeof TTSearchBody>) {
    const run = async (query: string, typeahead: boolean) => {
      const q = new URLSearchParams({ key: this.key, limit: String(body.limit), language: body.languageCode, countrySet: body.countrySet.join(","), view: "Unified" });
      if (typeahead) q.set("typeahead", "true");
      if (body.center) { q.set("lat", String(body.center.latitude)); q.set("lon", String(body.center.longitude)); }
      if (body.radiusMeters) q.set("radius", String(Math.round(body.radiusMeters)));
      return this.call<{ results?: { id?: string }[] }>("tt.search", "tt.search", `https://api.tomtom.com/search/2/search/${encodeURIComponent(query)}.json?${q}`);
    };
    const first = await run(body.query, true);
    const results = [...(first.results ?? [])];
    const stripped = body.query.trim().replace(/^(ال|وال|بال|لل)/, "");
    if (results.length < 3 && stripped !== body.query.trim() && stripped.length >= 2) {
      const second = await run(stripped, true).catch(() => ({ results: [] as { id?: string }[] }));
      for (const r of second.results ?? []) if (!results.some((x) => x.id === r.id)) results.push(r);
    }
    return { ...first, results: results.slice(0, body.limit) };
  }

  async place(id: string, languageCode: string, withDetails: boolean) {
    const q = new URLSearchParams({ key: this.key, entityId: id, language: languageCode, openingHours: "nextSevenDays", view: "Unified" });
    const res = await this.call<{ results?: { dataSources?: { poiDetails?: { id?: string }[] } }[] }>("tt.place", "tt.search", `https://api.tomtom.com/search/2/place.json?${q}`);
    const place = res.results?.[0] ?? null;
    let details: unknown = null;
    const detailsId = place?.dataSources?.poiDetails?.[0]?.id;
    if (withDetails && detailsId) {
      const dq = new URLSearchParams({ key: this.key, id: detailsId });
      details = await this.call<unknown>("tt.poiDetails", "tt.search", `https://api.tomtom.com/search/2/poiDetails.json?${dq}`).catch(() => null);
    }
    return { place, details };
  }

  /** صورة POI — تُمرَّر كبايتات مباشرة بلا تخزين. */
  photo(id: string, width: number, height: number) {
    const q = new URLSearchParams({ key: this.key, id, width: String(width), height: String(height) });
    return this.call<Response>("tt.photo", "tt.search", `https://api.tomtom.com/search/2/poiPhoto?${q}`, {}, true);
  }
}
