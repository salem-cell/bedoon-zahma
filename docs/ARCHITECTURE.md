# معمارية «بدون زحمة»

## المبدأ

Google Maps Platform هو محرك الخرائط والأماكن والطرق والمرور. «بدون زحمة» طبقة تجربة فوقه تجيب سؤالين: *كيف أبي أوصل؟* و*وين أبي أروح حولي؟*

## الطبقات

```
App (هدف iOS)
 ├─ AppContainer ── يركّب Production (Google عبر الخادم) أو DevMocks (DEBUG فقط)
 ├─ GoogleMapSurfaces ── Maps SDK: الرئيسية، مقارنة الطرق، خريطة الأماكن، اختيار نقطة
 └─ GoogleNavigationProvider ── Navigation SDK: route token، إرشاد صوتي، أحداث التقدّم

Packages/BedoonZahmaKit (Swift Package، بلا Google SDK → يُختبر على macOS)
 ├─ Domain ─────────── النماذج الموحّدة + بروتوكولات المزوّدين (Routing/Places/TravelTime/Navigation/Location)
 ├─ TrafficEngine ──── RouteMetricsDeriver، TrafficRouteScorer، RouteSelector، RerouteDecider
 ├─ PlaceRanking ───── PlaceRankingEngine (بايزي + ETA + مفتوح الآن) والترتيبات الخمسة
 ├─ NearbyDiscovery ── PlaceKindCatalog (الأقسام/التصنيفات) + NearbyDiscoveryPipeline (actor)
 ├─ Networking ─────── HTTPClient (إلغاء/مهلة/إعادة محاولة) + APIUsageMonitor
 ├─ BackendClient ──── DTOs Google + BackendAPI
 ├─ GoogleProviders ── تنفيذ البروتوكولات بـ Routes API / Places API (New) عبر الخادم
 ├─ DevMocks ───────── مزوّدات تطوير مُعلَّمة بوضوح (ليست Production)
 ├─ Location ───────── CoreLocation (When In Use، موفّر للبطارية)
 ├─ Storage ────────── المفضلة (IDs)، السجل، المنزل/العمل، الإعدادات
 ├─ Analytics ──────── أحداث بلا بيانات شخصية، دفعات
 ├─ RemoteConfig ───── الأوزان/العتبات/الأعلام من الخادم مع ETag
 ├─ DesignSystem ───── الهوية (ألوان، خطوط، مكوّنات)
 └─ Features ───────── الشاشات وViewModels (SwiftUI @Observable) + Localizable.xcstrings (ar/en)

backend (Fastify/TS) ── مفاتيح Google الخادمية، أقنعة الحقول، الحدود، Remote Config، التحليلات، /metrics
```

## تدفق الملاحة

```
Location → Autocomplete (session) → Destination
 → Routes API computeRoutes (alternatives + SHORTER_DISTANCE + TRAFFIC_ON_POLYLINE + routeToken)
 → RouteMetricsDeriver → TrafficRouteScorer → RouteSelector {🟢 بدون توقف, ⚡ أسرع, 📏 أقصر}
 → اختيار → Navigation SDK setDestinations(routeToken)
 → (بدون توقف) RerouteDecider كل N ثانية: «لقينا لك طريق أهدأ»
```

## تدفق الاكتشاف

```
Location → searchNearby × fan‑out (≤4 طلبات، 20 نتيجة/طلب، routingSummaries)
 → دمج/إزالة تكرار → ترشيح جغرافي → Route Matrix للنواقص (دفعات ≤100)
 → فلتر ≤5/10/15 دقيقة بالـ ETA الفعلي → PlaceRankingEngine → قائمة (الخريطة ثانوية)
 → Place Details (full) → «اذهب الآن» → تدفق الملاحة نفسه
```

## القرارات المهمة

- **الأعمال لا تلمس Google SDK**: كل المنطق في الحزمة ضد بروتوكولات؛ إضافة مزوّد مرور/أماكن آخر = تنفيذ بروتوكول جديد وتسجيله في AppContainer.
- **الخادم يمرّر لا يحوّل**: شكل استجابة Google يصل للعميل كما هو، والتحويل إلى Domain في `GoogleMappers` (مختبر بـ fixtures). هذا يبقي الخادم بلا حالة وقابلًا للاستبدال.
- **ETA الحقيقي لا تحويل المسافة**: فلتر الدقائق يعتمد `routingSummaries`/`Route Matrix` فقط؛ المكان بلا ETA لا يُعرض.
- **لا بيانات مزيّفة**: الحقول غير المتاحة من Google تبقى `nil` (انظر GOOGLE_DATA_LIMITS.md). Mocks في DEBUG فقط مع شارة ظاهرة.
- **التكلفة**: قناع حقول لكل مستوى، fan‑out محدود، ذاكرة مؤقتة قصيرة، Place Details عند الفتح فقط، الصور عند الظهور فقط، `/metrics` لكل SKU.
- **التوسع**: قسم جديد (⛽ محطات، 💊 صيدليات…) = `PlaceKind` جديد في `PlaceKindCatalog` بأنواع Google وتصنيفات قابلة للاشتقاق. لا تغيير في المحرك.
