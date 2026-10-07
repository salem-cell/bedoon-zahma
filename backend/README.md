# خادم «مشوارك أسهل» الخلفي

خادم Node/TypeScript (Fastify) خفيف. دوره الوحيد: حمل مفاتيح Google الخادمية، فرض أقنعة الحقول والحدود (تكلفة)، تقديم Remote Config، واستقبال أحداث التحليلات.

## التشغيل محليًا

```bash
cd backend
cp .env.example .env   # ثم املأ GOOGLE_SERVER_API_KEY و APP_KEYS
npm install
npm run dev
```

للتطوير بلا مفتاح تطبيق: `ALLOW_NO_APP_KEY=true`.

## الاختبارات

```bash
npm test
```

## المسارات

| المسار | الوظيفة | Google |
|---|---|---|
| `GET /v1/config` | Remote Config مع ETag/304 | — |
| `POST /v1/routes/compute` | الطرق البديلة + أقصر مسافة + المرور على المسار + route token | Routes API `computeRoutes` |
| `POST /v1/routes/matrix` | ETA فعلي لدفعات حتى 100 عنصر (TRAFFIC_AWARE_OPTIMAL) | Routes API `computeRouteMatrix` |
| `POST /v1/places/nearby` | بحث قريب + `routingSummaries` | Places API (New) `searchNearby` |
| `GET /v1/places/:id?level=basic|card|full` | تفاصيل بقناع حقول حسب المستوى | Places API (New) `Place Details` |
| `POST /v1/places/autocomplete` | إكمال تلقائي بجلسة | Places API (New) `autocomplete` |
| `GET /v1/places/photo?name=&maxWidthPx=&k=` | إعادة توجيه 302 إلى الصورة بلا تخزين | Place Photos (New) |
| `POST /v1/analytics/events` | أحداث بقائمة مسموحة ورفض أي معامل يشبه بيانات شخصية | — |
| `GET /metrics` | عدّادات الطلبات/الأخطاء/الكمون لكل مسار + تقدير التكلفة لكل SKU | — |

## الأمان

- مفتاح Google الخادمي مقيّد بعناوين IP الخادم وبـ APIs: Routes API و Places API (New) فقط.
- مفتاح iOS (Maps/Navigation SDK) مقيّد بـ Bundle ID ولا يملك صلاحية Places/Routes.
- `X-App-Key` بسيط الآن؛ الخطوة التالية: Apple App Attest لتوقيع الطلبات.
- لا يخزّن الخادم أي محتوى Google (لا أماكن ولا صور ولا طرق).

## النشر

```bash
docker build -t bedoon-zahma-backend .
docker run -p 8080:8080 --env-file .env bedoon-zahma-backend
```

مناسب لـ Cloud Run أو أي حاوية. أضف `SKU_PRICES_JSON` من جدول أسعار Google الحالي لعرض تقدير التكلفة في `/metrics`.
