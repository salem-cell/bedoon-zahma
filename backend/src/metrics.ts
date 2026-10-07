/** عدّادات الاستخدام والتكلفة لكل مسار Google (للمراقبة وضبط التكلفة). */
export type Counter = { requests: number; errors: number; latencyMs: number };

export class Metrics {
  private endpoints = new Map<string, Counter>();
  private skus = new Map<string, number>();
  private startedAt = Date.now();

  constructor(private readonly prices: Record<string, number> = {}) {}

  record(endpoint: string, latencyMs: number, failed: boolean, sku?: string) {
    const c = this.endpoints.get(endpoint) ?? { requests: 0, errors: 0, latencyMs: 0 };
    c.requests += 1;
    c.latencyMs += latencyMs;
    if (failed) c.errors += 1;
    this.endpoints.set(endpoint, c);
    if (sku && !failed) this.skus.set(sku, (this.skus.get(sku) ?? 0) + 1);
  }

  snapshot() {
    const endpoints: Record<string, Counter & { avgLatencyMs: number }> = {};
    for (const [k, v] of this.endpoints) endpoints[k] = { ...v, avgLatencyMs: v.requests ? Math.round(v.latencyMs / v.requests) : 0 };
    const skus: Record<string, { count: number; estimatedUsd: number | null }> = {};
    let total = 0;
    let priced = false;
    for (const [k, count] of this.skus) {
      const price = this.prices[k];
      const usd = price != null ? (count / 1000) * price : null;
      if (usd != null) { total += usd; priced = true; }
      skus[k] = { count, estimatedUsd: usd };
    }
    return { uptimeSeconds: Math.round((Date.now() - this.startedAt) / 1000), endpoints, skus, estimatedTotalUsd: priced ? Number(total.toFixed(4)) : null };
  }
}
