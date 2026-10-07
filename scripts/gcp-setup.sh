#!/usr/bin/env bash
# إعداد Google Maps Platform لـ«مشوارك أسهل» دفعة واحدة (يُشغَّل بعد قبول شروط Google Cloud وإنشاء حساب فوترة):
#   1) إنشاء المشروع وربطه بالفوترة   2) تفعيل Maps SDK for iOS + Navigation SDK + Routes API + Places API (New)
#   3) مفتاح iOS مقيّد بمعرّف الحزمة    4) مفتاح خادمي مقيّد بـ Routes/Places
#   5) وضع المفاتيح في GitHub (GOOGLE_MAPS_IOS_KEY) وVercel (GOOGLE_SERVER_API_KEY) وإعادة نشر الخادم
#
# الاستخدام:  bash scripts/gcp-setup.sh [PROJECT_ID] [BILLING_ACCOUNT_ID]
#   BILLING_ACCOUNT_ID اختياري؛ إن غاب يُؤخذ أول حساب فوترة مفتوح في الحساب.
set -euo pipefail

PROJECT="${1:-mishwarak-ashal}"
BILLING="${2:-}"
BUNDLE_ID="sa.mishwarak.app"
REPO="salem-cell/bedoon-zahma"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GC="/c/Users/Lenovo/AppData/Local/Google/Cloud SDK/google-cloud-sdk"
if [ -d "$GC" ]; then export PATH="$GC/bin:$PATH"; export CLOUDSDK_PYTHON="$GC/platform/bundledpython/python.exe"; fi

echo "== الحساب"; gcloud auth list --format="value(account)" | head -1

echo "== المشروع $PROJECT"
if ! gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
  gcloud projects create "$PROJECT" --name="Mishwarak Ashal"
fi
gcloud config set project "$PROJECT" >/dev/null

echo "== الفوترة"
if [ -z "$BILLING" ]; then
  BILLING="$(gcloud billing accounts list --filter=open=true --format='value(name)' | head -1 | sed 's#billingAccounts/##')"
fi
if [ -z "$BILLING" ]; then
  echo "لا يوجد حساب فوترة. أنشئه من https://console.cloud.google.com/billing/create ثم أعد التشغيل." >&2
  exit 2
fi
gcloud billing projects link "$PROJECT" --billing-account="$BILLING" >/dev/null
echo "مرتبط بحساب الفوترة $BILLING"

echo "== تفعيل الواجهات"
NAV_SERVICE="$(gcloud services list --available --filter='config.title~Navigation' --format='value(config.name)' | head -1)"
gcloud services enable apikeys.googleapis.com maps-ios-backend.googleapis.com routes.googleapis.com places.googleapis.com ${NAV_SERVICE:+$NAV_SERVICE}
echo "Navigation SDK service: ${NAV_SERVICE:-غير موجود في القائمة — فعّله يدويًا من Google Maps Platform → APIs}"

echo "== مفتاح iOS (مقيّد بـ $BUNDLE_ID)"
IOS_KEY_NAME="$(gcloud services api-keys create --display-name="Mishwarak iOS (Maps+Navigation)" \
  --allowed-bundle-ids="$BUNDLE_ID" \
  --api-target=service=maps-ios-backend.googleapis.com ${NAV_SERVICE:+--api-target=service=$NAV_SERVICE} \
  --format='value(response.name)' 2>/dev/null || gcloud services api-keys create --display-name="Mishwarak iOS (Maps+Navigation)" --allowed-bundle-ids="$BUNDLE_ID" --api-target=service=maps-ios-backend.googleapis.com ${NAV_SERVICE:+--api-target=service=$NAV_SERVICE} --format='value(name)')"
IOS_KEY="$(gcloud services api-keys get-key-string "$IOS_KEY_NAME" --format='value(keyString)')"

echo "== المفتاح الخادمي (Routes + Places)"
SRV_KEY_NAME="$(gcloud services api-keys create --display-name="Mishwarak backend (Routes+Places)" \
  --api-target=service=routes.googleapis.com --api-target=service=places.googleapis.com \
  --format='value(response.name)' 2>/dev/null || gcloud services api-keys create --display-name="Mishwarak backend (Routes+Places)" --api-target=service=routes.googleapis.com --api-target=service=places.googleapis.com --format='value(name)')"
SRV_KEY="$(gcloud services api-keys get-key-string "$SRV_KEY_NAME" --format='value(keyString)')"

echo "== GitHub secret GOOGLE_MAPS_IOS_KEY"
printf '%s' "$IOS_KEY" | gh secret set GOOGLE_MAPS_IOS_KEY -R "$REPO"

echo "== Vercel GOOGLE_SERVER_API_KEY + إعادة النشر"
( cd "$ROOT/backend" \
  && (vercel env rm GOOGLE_SERVER_API_KEY production --yes >/dev/null 2>&1 || true) \
  && printf '%s' "$SRV_KEY" | vercel env add GOOGLE_SERVER_API_KEY production >/dev/null \
  && vercel deploy --prod --yes 2>&1 | tail -2 )

echo
echo "تم. المفاتيح لم تُطبع هنا عمدًا. تحقق:"
echo "  curl -s -H 'X-App-Key: <BZ_APP_KEY>' -H 'Content-Type: application/json' -d '{\"includedTypes\":[\"cafe\"],\"locationRestriction\":{\"circle\":{\"center\":{\"latitude\":24.7,\"longitude\":46.6},\"radius\":3000}}}' https://bedoon-zahma-backend.vercel.app/v1/places/nearby | head -c 300"
