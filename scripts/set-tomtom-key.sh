#!/usr/bin/env bash
# يضع مفتاح TomTom على Vercel (الإنتاج)، يعيد نشر الخادم، ويتحقق بطلب طرق وبحث حقيقيين في الرياض.
# الاستخدام: bash scripts/set-tomtom-key.sh <TOMTOM_API_KEY>
set -euo pipefail
KEY="${1:?TomTom API key required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPKEY_FILE="${BZ_APP_KEY_FILE:-}"
cd "$ROOT/backend"
(vercel env rm TOMTOM_API_KEY production --yes >/dev/null 2>&1 || true)
printf '%s' "$KEY" | vercel env add TOMTOM_API_KEY production >/dev/null
vercel deploy --prod --yes 2>&1 | tail -1
sleep 5
B="https://bedoon-zahma-backend.vercel.app"
echo "== healthz"; curl -s -m 20 "$B/healthz"; echo
if [ -n "${BZ_APP_KEY:-}" ]; then
  echo "== routes (حطين → البوليفارد)"
  curl -s -m 40 -H "X-App-Key: $BZ_APP_KEY" -H "Content-Type: application/json" \
    -d '{"origin":{"latitude":24.7619,"longitude":46.6150},"destination":{"latitude":24.7640,"longitude":46.6240},"languageCode":"ar"}' \
    "$B/v1/tt/routes" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const rs=(j.primary&&j.primary.routes)||[];console.log("routes:",rs.length,rs.map(r=>r.summary&&`${r.summary.lengthInMeters}m ${r.summary.travelTimeInSeconds}s delay=${r.summary.trafficDelayInSeconds}`));console.log("shortest:",(j.shortest&&j.shortest.routes||[]).length);})'
  echo "== nearby cafés"
  curl -s -m 40 -H "X-App-Key: $BZ_APP_KEY" -H "Content-Type: application/json" \
    -d '{"center":{"latitude":24.7619,"longitude":46.6150},"radiusMeters":5000,"categorySet":[9376],"limit":100,"languageCode":"ar"}' \
    "$B/v1/tt/nearby" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const r=j.results||[];console.log("results:",r.length,r.slice(0,3).map(x=>x.poi&&x.poi.name));})'
fi
echo "تم."
