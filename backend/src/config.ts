import { z } from "zod";

const Env = z.object({
  PORT: z.coerce.number().default(8080),
  HOST: z.string().default("0.0.0.0"),
  LOG_LEVEL: z.string().default("info"),
  /** مفتاح Google خادمي: مقيّد بـ IP الخادم + APIs: Routes API, Places API (New) فقط. */
  GOOGLE_SERVER_API_KEY: z.string().min(10),
  /** مفاتيح التطبيق المقبولة (X-App-Key)، مفصولة بفواصل. */
  APP_KEYS: z.string().default(""),
  /** للتطوير المحلي فقط. */
  ALLOW_NO_APP_KEY: z.enum(["true", "false"]).default("false").transform((v) => v === "true"),
  RATE_LIMIT_PER_MIN: z.coerce.number().default(120),
  DEFAULT_REGION_CODE: z.string().default("SA"),
  /** ملف JSON اختياري يُدمج فوق إعدادات Remote Config الافتراضية. */
  CONFIG_OVERRIDES_PATH: z.string().optional(),
  /** أسعار SKU التقديرية (USD لكل 1000 طلب) لحساب التكلفة في /metrics — اختياري. */
  SKU_PRICES_JSON: z.string().optional(),
  GOOGLE_TIMEOUT_MS: z.coerce.number().default(10_000),
});

export type Config = z.infer<typeof Env> & { appKeys: Set<string>; skuPrices: Record<string, number> };

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = Env.parse(env);
  const appKeys = new Set(parsed.APP_KEYS.split(",").map((s) => s.trim()).filter(Boolean));
  if (appKeys.size === 0 && !parsed.ALLOW_NO_APP_KEY) {
    throw new Error("APP_KEYS فارغ. عيّن مفتاحًا واحدًا على الأقل أو ALLOW_NO_APP_KEY=true للتطوير.");
  }
  let skuPrices: Record<string, number> = {};
  if (parsed.SKU_PRICES_JSON) skuPrices = JSON.parse(parsed.SKU_PRICES_JSON);
  return { ...parsed, appKeys, skuPrices };
}
