import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/**
 * Remote Config — مفاتيح JSON تطابق حرفيًا `AppRemoteConfig` في Swift (RemoteConfigService.swift).
 * تغيير أي قيمة هنا (أو في ملف overrides) يصل إلى التطبيق بلا إصدار جديد.
 */
export const DEFAULT_CONFIG = {
  version: 1,
  trafficWeights: {
    delayPerMinute: 5,
    jamPerKm: 10,
    slowPerKm: 3,
    stopAndGoPerJamSegment: 2,
    incidentPenalty: 8,
    turnPenalty: 0.15,
    uTurnPenalty: 2.5,
    extraDistancePerKm: 0.6,
    warningPenalty: 3,
    missingTrafficDataPenalty: 6,
    maxDetourDurationRatio: 1.35,
    maxDetourDistanceRatio: 1.6,
  },
  rerouteThresholds: {
    minDelaySavingSeconds: 180,
    maxExtraDurationSeconds: 300,
    minFrictionImprovementRatio: 0.3,
    checkIntervalSeconds: 90,
    cooldownSeconds: 240,
  },
  rankingWeights: {
    confidenceThreshold: 500,
    etaPenaltyPerMinute: 0.02,
    openNowBonus: 0.1,
    closedPenalty: 0.3,
    fallbackAverageRating: 4.2,
  },
  nearby: {
    prefilterRadiusMeters: { "5": 5000, "10": 9000, "15": 14000 },
    maxFanOutRequests: 4,
    typesPerRequest: 8,
    maxCandidates: 30,
    cacheTTLSeconds: 120,
    preferRoutingSummaries: true,
  },
  flags: {
    navigationSDKEnabled: true,
    dynamicRerouteEnabled: true,
    mapViewInNearbyEnabled: true,
    photosEnabled: true,
    atmosphereFieldsEnabled: true,
  },
  searchRegionCodes: ["sa"],
  /** المزوّد النشط: tomtom (مجاني) أو google. التطبيق يختار المزوّد وقت الإقلاع من إعداد البناء، وهذا للمراقبة والتبديل لاحقًا. */
  mapsProvider: "tomtom" as "tomtom" | "google",
};

export type RemoteConfig = typeof DEFAULT_CONFIG;

function deepMerge<T extends Record<string, unknown>>(base: T, patch: Record<string, unknown>): T {
  const out: Record<string, unknown> = { ...base };
  for (const [k, v] of Object.entries(patch)) {
    const cur = out[k];
    if (v && typeof v === "object" && !Array.isArray(v) && cur && typeof cur === "object" && !Array.isArray(cur)) {
      out[k] = deepMerge(cur as Record<string, unknown>, v as Record<string, unknown>);
    } else {
      out[k] = v;
    }
  }
  return out as T;
}

export function buildRemoteConfig(overridesPath?: string, envPatch: Partial<RemoteConfig> = {}): { config: RemoteConfig; etag: string; body: string } {
  let config: RemoteConfig = deepMerge(DEFAULT_CONFIG as unknown as Record<string, unknown>, envPatch as Record<string, unknown>) as unknown as RemoteConfig;
  if (overridesPath) {
    const patch = JSON.parse(readFileSync(overridesPath, "utf8")) as Record<string, unknown>;
    config = deepMerge(config as unknown as Record<string, unknown>, patch) as unknown as RemoteConfig;
  }
  const body = JSON.stringify(config);
  const etag = `"${createHash("sha256").update(body).digest("hex").slice(0, 16)}"`;
  return { config, etag, body };
}
