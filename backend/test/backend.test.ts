import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { EventsBody } from "../src/analytics.js";
import { GoogleClient, NearbyBody, RouteMatrixBody, nearbyFieldMask, placeFieldMask } from "../src/google.js";
import { DEFAULT_CONFIG, buildRemoteConfig } from "../src/remoteConfig.js";
import { Metrics } from "../src/metrics.js";

const cfg = loadConfig({ GOOGLE_SERVER_API_KEY: "test-key-0123456789", APP_KEYS: "k1", LOG_LEVEL: "silent" });

/** مزوّد Google وهمي للاختبارات — لا يتصل بالشبكة. */
class FakeGoogle extends GoogleClient {
  calls: string[] = [];
  override async computeRoutes(): Promise<unknown> { this.calls.push("routes"); return { routes: [] }; }
  override async computeRouteMatrix(): Promise<unknown[]> { this.calls.push("matrix"); return []; }
  override async searchNearby(): Promise<unknown> { this.calls.push("nearby"); return { places: [] }; }
  override async placeDetails(): Promise<unknown> { this.calls.push("details"); return { id: "x" }; }
  override async autocomplete(): Promise<unknown> { this.calls.push("autocomplete"); return { suggestions: [] }; }
  override async photoUri(): Promise<string> { return "https://lh3.googleusercontent.com/photo"; }
}

function app() {
  const metrics = new Metrics();
  const google = new FakeGoogle(cfg, metrics);
  return { app: buildApp(cfg, { google, metrics }), google };
}

describe("remote config", () => {
  it("يطابق مفاتيح AppRemoteConfig في Swift", () => {
    expect(Object.keys(DEFAULT_CONFIG).sort()).toEqual(["flags", "nearby", "rankingWeights", "rerouteThresholds", "searchRegionCodes", "trafficWeights", "version"]);
    expect(Object.keys(DEFAULT_CONFIG.trafficWeights)).toEqual([
      "delayPerMinute", "jamPerKm", "slowPerKm", "stopAndGoPerJamSegment", "incidentPenalty", "turnPenalty", "uTurnPenalty",
      "extraDistancePerKm", "warningPenalty", "missingTrafficDataPenalty", "maxDetourDurationRatio", "maxDetourDistanceRatio",
    ]);
    expect(DEFAULT_CONFIG.nearby.prefilterRadiusMeters).toEqual({ "5": 5000, "10": 9000, "15": 14000 });
  });

  it("يخدم ETag ويرد 304", async () => {
    const { app: a } = app();
    const r1 = await a.inject({ method: "GET", url: "/v1/config", headers: { "x-app-key": "k1" } });
    expect(r1.statusCode).toBe(200);
    const etag = r1.headers.etag as string;
    expect(etag).toBe(buildRemoteConfig().etag);
    const r2 = await a.inject({ method: "GET", url: "/v1/config", headers: { "x-app-key": "k1", "if-none-match": etag } });
    expect(r2.statusCode).toBe(304);
  });
});

describe("auth & limits", () => {
  it("يرفض بلا مفتاح تطبيق", async () => {
    const { app: a } = app();
    const r = await a.inject({ method: "GET", url: "/v1/config" });
    expect(r.statusCode).toBe(401);
  });

  it("يرفض مصفوفة طرق تتجاوز 100 عنصر مع TRAFFIC_AWARE_OPTIMAL", () => {
    const dest = Array.from({ length: 101 }, () => ({ waypoint: { location: { latLng: { latitude: 24.7, longitude: 46.6 } } } }));
    expect(() => RouteMatrixBody.parse({ origins: [dest[0]], destinations: dest })).toThrow(/exceed limit 100/);
    expect(() => RouteMatrixBody.parse({ origins: [dest[0]], destinations: dest, routingPreference: "TRAFFIC_UNAWARE" })).not.toThrow();
  });

  it("يرفض بحثًا قريبًا بنصف قطر > 50 كم أو أكثر من 20 نتيجة", () => {
    const base = { includedTypes: ["cafe"], locationRestriction: { circle: { center: { latitude: 24.7, longitude: 46.6 }, radius: 60_000 } } };
    expect(() => NearbyBody.parse(base)).toThrow();
    expect(() => NearbyBody.parse({ ...base, locationRestriction: { circle: { center: { latitude: 24.7, longitude: 46.6 }, radius: 5000 } }, maxResultCount: 25 })).toThrow();
  });
});

describe("field masks (cost control)", () => {
  it("المستوى basic لا يطلب حقول Enterprise", () => {
    const m = placeFieldMask("basic");
    expect(m).not.toContain("rating");
    expect(m).not.toContain("websiteUri");
  });
  it("المستوى full يطلب الحقول الغنية والـ Atmosphere", () => {
    const m = placeFieldMask("full");
    expect(m).toContain("regularOpeningHours.weekdayDescriptions");
    expect(m).toContain("googleMapsUri");
    expect(m).toContain("outdoorSeating");
  });
  it("البحث القريب يطلب routingSummaries عند وجود routingParameters", () => {
    expect(nearbyFieldMask(true, false)).toContain("routingSummaries");
    expect(nearbyFieldMask(false, false)).not.toContain("routingSummaries");
    expect(nearbyFieldMask(false, false)).not.toContain("servesBreakfast");
  });
});

describe("analytics privacy", () => {
  it("يرفض أحداثًا غير معروفة أو معاملات تحوي إحداثيات", () => {
    expect(() => EventsBody.parse({ events: [{ name: "evil", params: {}, timestamp: "2026-10-07T00:00:00Z" }] })).toThrow();
    expect(() => EventsBody.parse({ events: [{ name: "place_opened", params: { lat: "24.7" }, timestamp: "2026-10-07T00:00:00Z" }] })).toThrow(/privacy/);
    expect(() => EventsBody.parse({ events: [{ name: "route_option_selected", params: { strategy: "no_stop", extra_km: "3.1" }, timestamp: "2026-10-07T00:00:00Z" }] })).not.toThrow();
  });

  it("يقبل دفعة صالحة بـ 202", async () => {
    const { app: a } = app();
    const r = await a.inject({ method: "POST", url: "/v1/analytics/events", headers: { "x-app-key": "k1" }, payload: { events: [{ name: "nearby_opened", params: { kind: "cafes" }, timestamp: "2026-10-07T00:00:00Z" }] } });
    expect(r.statusCode).toBe(202);
  });
});

describe("proxies", () => {
  it("يمرّر الطلبات الصالحة إلى Google ويعيد توجيه الصور بلا تخزين", async () => {
    const { app: a, google } = app();
    const routes = await a.inject({ method: "POST", url: "/v1/routes/compute", headers: { "x-app-key": "k1" }, payload: { origin: { location: { latLng: { latitude: 24.7, longitude: 46.6 } } }, destination: { placeId: "ChIJ_X" }, languageCode: "ar" } });
    expect(routes.statusCode).toBe(200);
    const photo = await a.inject({ method: "GET", url: "/v1/places/photo?name=places/ChIJ_X/photos/P1&maxWidthPx=800&k=k1" });
    expect(photo.statusCode).toBe(302);
    expect(photo.headers["cache-control"]).toBe("no-store");
    expect(google.calls).toEqual(["routes"]);
  });
});
