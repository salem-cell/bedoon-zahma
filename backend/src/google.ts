import { z } from "zod";
import type { Config } from "./config.js";
import type { Metrics } from "./metrics.js";

/**
 * عميل Google Maps Platform (Routes API v2 + Places API New).
 * - يُضيف المفتاح الخادمي وقناع الحقول؛ لا يغيّر شكل الاستجابة.
 * - يفرض حدود Google قبل الإرسال (لتجنّب أخطاء مكلفة).
 * - لا يخزّن محتوى Google (سياسات Places/Routes) — التخزين الوحيد في العميل مؤقت وقصير.
 */

export class GoogleError extends Error {
  constructor(public status: number, message: string, public retryAfter?: string) { super(message); }
}

const LatLng = z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) });
const Waypoint = z.object({ location: z.object({ latLng: LatLng }).optional(), placeId: z.string().min(1).max(512).optional() }).refine((w) => !!w.location || !!w.placeId, "waypoint needs location or placeId");

export const ComputeRoutesBody = z.object({
  origin: Waypoint,
  destination: Waypoint,
  travelMode: z.literal("DRIVE").default("DRIVE"),
  routingPreference: z.enum(["TRAFFIC_AWARE", "TRAFFIC_AWARE_OPTIMAL"]).default("TRAFFIC_AWARE_OPTIMAL"),
  computeAlternativeRoutes: z.boolean().default(true),
  requestedReferenceRoutes: z.array(z.enum(["SHORTER_DISTANCE", "FUEL_EFFICIENT"])).default(["SHORTER_DISTANCE"]),
  extraComputations: z.array(z.enum(["TRAFFIC_ON_POLYLINE", "TOLLS", "FUEL_CONSUMPTION"])).default(["TRAFFIC_ON_POLYLINE"]),
  routeModifiers: z.object({ avoidTolls: z.boolean().optional(), avoidHighways: z.boolean().optional(), avoidFerries: z.boolean().optional() }).optional(),
  languageCode: z.string().min(2).max(10).default("ar"),
  units: z.literal("METRIC").default("METRIC"),
  departureTime: z.string().datetime().optional(),
  regionCode: z.string().length(2).optional(),
});

/** قناع حقول Routes: كل ما يحتاجه TrafficRouteScorer + route token للملاحة. */
export const ROUTES_FIELD_MASK = [
  "routes.routeLabels", "routes.distanceMeters", "routes.duration", "routes.staticDuration",
  "routes.polyline.encodedPolyline", "routes.description", "routes.warnings",
  "routes.legs.steps.distanceMeters", "routes.legs.steps.staticDuration", "routes.legs.steps.navigationInstruction",
  "routes.travelAdvisory.speedReadingIntervals", "routes.travelAdvisory.routeRestrictionsPartiallyIgnored",
  "routes.routeToken", "routes.localizedValues",
].join(",");

export const RouteMatrixBody = z.object({
  origins: z.array(z.object({ waypoint: Waypoint })).min(1).max(50),
  destinations: z.array(z.object({ waypoint: Waypoint })).min(1).max(625),
  travelMode: z.literal("DRIVE").default("DRIVE"),
  routingPreference: z.enum(["TRAFFIC_UNAWARE", "TRAFFIC_AWARE", "TRAFFIC_AWARE_OPTIMAL"]).default("TRAFFIC_AWARE_OPTIMAL"),
  languageCode: z.string().min(2).max(10).optional(),
}).superRefine((b, ctx) => {
  const elements = b.origins.length * b.destinations.length;
  const limit = b.routingPreference === "TRAFFIC_AWARE_OPTIMAL" ? 100 : 625;
  if (elements > limit) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `route matrix elements ${elements} exceed limit ${limit} for ${b.routingPreference}` });
});

export const MATRIX_FIELD_MASK = "originIndex,destinationIndex,condition,distanceMeters,duration,staticDuration";

export const NearbyBody = z.object({
  includedTypes: z.array(z.string().regex(/^[a-z_]+$/)).min(1).max(50),
  maxResultCount: z.number().int().min(1).max(20).default(20),
  rankPreference: z.enum(["POPULARITY", "DISTANCE"]).default("POPULARITY"),
  locationRestriction: z.object({ circle: z.object({ center: LatLng, radius: z.number().positive().max(50_000) }) }),
  languageCode: z.string().min(2).max(10).default("ar"),
  regionCode: z.string().length(2).default("SA"),
  routingParameters: z.object({ origin: LatLng, travelMode: z.literal("DRIVE").default("DRIVE"), routingPreference: z.enum(["TRAFFIC_UNAWARE", "TRAFFIC_AWARE", "TRAFFIC_AWARE_OPTIMAL"]).default("TRAFFIC_AWARE") }).optional(),
});

const PLACE_BASIC = ["id", "displayName", "location", "types", "primaryType"];
const PLACE_CARD = [...PLACE_BASIC, "rating", "userRatingCount", "photos", "currentOpeningHours.openNow", "businessStatus", "priceLevel", "shortFormattedAddress", "addressComponents"];
const PLACE_ATMOSPHERE = ["servesBreakfast", "servesBrunch", "servesDessert", "servesCoffee", "outdoorSeating", "takeout", "dineIn", "delivery", "reservable"];
const PLACE_FULL = [...PLACE_CARD, "formattedAddress", "regularOpeningHours.weekdayDescriptions", "websiteUri", "nationalPhoneNumber", "internationalPhoneNumber", "googleMapsUri", "editorialSummary", "accessibilityOptions", ...PLACE_ATMOSPHERE];

export type DetailLevel = "basic" | "card" | "full";

export function placeFieldMask(level: DetailLevel): string {
  return (level === "full" ? PLACE_FULL : level === "card" ? PLACE_CARD : PLACE_BASIC).join(",");
}

/** قناع البحث القريب: مستوى «card» + routingSummaries (ETA فعلي) + حقول Atmosphere.
 *  routingSummaries يُفوتر على SKU Enterprise + Atmosphere، لذا إضافة حقول Atmosphere لا تكلّف أكثر. */
export function nearbyFieldMask(withRouting: boolean, atmosphere: boolean): string {
  const fields = PLACE_CARD.map((f) => `places.${f}`);
  if (atmosphere || withRouting) fields.push(...PLACE_ATMOSPHERE.map((f) => `places.${f}`));
  if (withRouting) fields.push("routingSummaries");
  return fields.join(",");
}

export const AutocompleteBody = z.object({
  input: z.string().min(1).max(200),
  locationBias: z.object({ circle: z.object({ center: LatLng, radius: z.number().positive().max(50_000) }) }).optional(),
  origin: LatLng.optional(),
  includedRegionCodes: z.array(z.string().length(2)).max(15).default(["sa"]),
  languageCode: z.string().min(2).max(10).default("ar"),
  sessionToken: z.string().min(8).max(128),
});

export class GoogleClient {
  constructor(private readonly cfg: Config, private readonly metrics: Metrics) {}

  private async call<T>(endpoint: string, sku: string, url: string, init: RequestInit & { fieldMask?: string }): Promise<T> {
    const started = Date.now();
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), this.cfg.GOOGLE_TIMEOUT_MS);
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": this.cfg.GOOGLE_SERVER_API_KEY,
      ...(init.fieldMask ? { "X-Goog-FieldMask": init.fieldMask } : {}),
    };
    try {
      const res = await fetch(url, { ...init, headers, signal: ac.signal });
      const text = await res.text();
      if (!res.ok) {
        this.metrics.record(endpoint, Date.now() - started, true, sku);
        // لا نمرّر نص Google الخام كاملًا (قد يحوي تفاصيل داخلية)؛ نكتفي بالحالة والرسالة المختصرة.
        let message = `google ${endpoint} failed (${res.status})`;
        try { message = JSON.parse(text)?.error?.message ?? message; } catch { /* ignore */ }
        throw new GoogleError(res.status, message, res.headers.get("retry-after") ?? undefined);
      }
      this.metrics.record(endpoint, Date.now() - started, false, sku);
      return (text ? JSON.parse(text) : {}) as T;
    } catch (e) {
      if (e instanceof GoogleError) throw e;
      this.metrics.record(endpoint, Date.now() - started, true, sku);
      const aborted = (e as Error).name === "AbortError";
      throw new GoogleError(aborted ? 504 : 502, aborted ? `google ${endpoint} timeout` : `google ${endpoint} network error`);
    } finally {
      clearTimeout(timer);
    }
  }

  computeRoutes(body: z.infer<typeof ComputeRoutesBody>) {
    const sku = body.extraComputations.includes("TRAFFIC_ON_POLYLINE") ? "routes.compute.advanced" : "routes.compute.basic";
    return this.call<unknown>("routes.compute", sku, "https://routes.googleapis.com/directions/v2:computeRoutes", {
      method: "POST", body: JSON.stringify({ ...body, regionCode: body.regionCode ?? this.cfg.DEFAULT_REGION_CODE }), fieldMask: ROUTES_FIELD_MASK,
    });
  }

  computeRouteMatrix(body: z.infer<typeof RouteMatrixBody>) {
    const sku = body.routingPreference === "TRAFFIC_UNAWARE" ? "routes.matrix.basic" : "routes.matrix.advanced";
    return this.call<unknown[]>("routes.matrix", sku, "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix", {
      method: "POST", body: JSON.stringify(body), fieldMask: MATRIX_FIELD_MASK,
    });
  }

  searchNearby(body: z.infer<typeof NearbyBody>, atmosphere: boolean) {
    const withRouting = !!body.routingParameters;
    const sku = withRouting || atmosphere ? "places.nearby.enterprise_atmosphere" : "places.nearby.enterprise";
    return this.call<unknown>("places.nearby", sku, "https://places.googleapis.com/v1/places:searchNearby", {
      method: "POST", body: JSON.stringify(body), fieldMask: nearbyFieldMask(withRouting, atmosphere),
    });
  }

  placeDetails(placeId: string, level: DetailLevel, languageCode: string, sessionToken?: string) {
    const q = new URLSearchParams({ languageCode });
    if (sessionToken) q.set("sessionToken", sessionToken);
    const sku = level === "full" ? "places.details.enterprise_atmosphere" : level === "card" ? "places.details.enterprise" : "places.details.essentials";
    return this.call<unknown>("places.details", sku, `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?${q}`, {
      method: "GET", fieldMask: placeFieldMask(level),
    });
  }

  autocomplete(body: z.infer<typeof AutocompleteBody>) {
    return this.call<unknown>("places.autocomplete", "places.autocomplete.session", "https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST", body: JSON.stringify(body),
    });
  }

  /** يرجع رابط الصورة المؤقت (بلا تخزين) ليُعاد توجيه العميل إليه. */
  async photoUri(name: string, maxWidthPx: number): Promise<string> {
    const q = new URLSearchParams({ maxWidthPx: String(Math.min(Math.max(maxWidthPx, 1), 4800)), skipHttpRedirect: "true" });
    const res = await this.call<{ photoUri?: string }>("places.photo", "places.photo", `https://places.googleapis.com/v1/${name}/media?${q}`, { method: "GET" });
    if (!res.photoUri) throw new GoogleError(404, "photo unavailable");
    return res.photoUri;
  }
}
