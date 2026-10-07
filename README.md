# بدون زحمة — Bedoon Zahma

**«اختر كيف تبي توصل»**

تطبيق iPhone أصلي (Swift / SwiftUI) فوق Google Maps Platform يجيب سؤالين:

1. **كيف أبي أوصل؟** → 🟢 بدون توقف · ⚡ أسرع طريق · 📏 أقصر طريق
2. **وين أبي أروح حولي؟** → ☕ مقاهيي · 🍽️ مطاعمي خلال ≤5 / ≤10 / ≤15 دقيقة **بوقت القيادة الفعلي**

## محتويات المستودع

| المسار | الوصف |
|---|---|
| `BedoonZahma/` | مشروع iOS (XcodeGen `project.yml` + هدف التطبيق + الحزمة) |
| `BedoonZahma/Packages/BedoonZahmaKit/` | الحزمة: Domain، TrafficEngine، PlaceRanking، NearbyDiscovery، GoogleProviders، Features… + الاختبارات |
| `backend/` | خادم Fastify/TypeScript (مفاتيح Google، أقنعة الحقول، Remote Config، التحليلات، المقاييس) |
| `docs/` | المعمارية، قيود بيانات Google، قائمة App Store |
| `design-source/` | ملفات التصميم الأصلية من Claude Design (مرجع الهوية والشاشات) |

## التشغيل على Mac

المتطلبات: macOS، Xcode 26، Node 20+، [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# 1) الخادم الخلفي
cd backend && cp .env.example .env    # املأ GOOGLE_SERVER_API_KEY و APP_KEYS
npm install && npm test && npm run dev

# 2) التطبيق
cd ../BedoonZahma
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # املأ GOOGLE_MAPS_IOS_KEY و BZ_APP_KEY و BZ_TEAM_ID
xcodegen generate
open BedoonZahma.xcodeproj
```

- **بلا مفاتيح** (محاكي): اترك `BZ_USE_MOCKS = 1` في `Config/Debug.xcconfig`. يعمل التطبيق ببيانات تطوير مُعلَّمة بشارة «بيانات تجريبية» وخريطة مجرّدة. هذا الوضع مستحيل في Release.
- **ببيانات حقيقية**: `BZ_USE_MOCKS = 0` و`BZ_BACKEND_URL` يشير إلى الخادم.

اختبارات الحزمة (لا تحتاج Google SDK):

```bash
cd BedoonZahma/Packages/BedoonZahmaKit && swift test
```

على Windows (Swift 6.4 + VS Build Tools) تُشغَّل محركات المنطق واختباراتها الأربعة بالسكربت التالي؛ أهداف SwiftUI وCoreLocation تُستثنى تلقائياً خارج منصات Apple:

```bash
powershell -File scripts/test-kit-windows.ps1
```

## كيف تعمل الميزات الأساسية

- **بدون توقف**: `TrafficRouteScorer` يحسب درجة احتكاك من بيانات Routes API الرسمية (تأخير المرور، مسافة البطء/الاختناق من `speedReadingIntervals`، الانعطافات، التحذيرات، المسافة الإضافية) ويختار الأقل ضمن حدود التفاف قابلة للتعديل. الأوزان من الخادم (`GET /v1/config`).
- **5/10/15 دقيقة**: `NearbyDiscoveryPipeline` يطلب `searchNearby` مع `routingSummaries` (ETA فعلي بالمرور) ويكمل النواقص بـ Route Matrix، ثم يفلتر بالـ ETA لا بالمسافة.
- **الأفضل حولي**: ترتيب بايزي `(v/(v+m))·R + (m/(v+m))·C` مع عوامل محدودة (ETA، مفتوح الآن).
- **الملاحة**: Navigation SDK يتلقى `routeToken` للمسار المختار، و`RerouteDecider` يقترح «لقينا لك طريق أهدأ» عند توفر بديل أهدأ ضمن العتبات.

## ما لا يوفره Google ولا نزيّفه

الحوادث، دقائق الاختناق الشديد بدقة، نسبة الطرق المحلية، تسلسل الأحياء، المنيو، تصنيف «سعودي». التفاصيل والبدائل في [docs/GOOGLE_DATA_LIMITS.md](docs/GOOGLE_DATA_LIMITS.md).

## الحالة (2026‑10‑07)

- **مُجمَّع ومُختبَر فعليًا على Windows (Swift 6.4):** Domain، TrafficEngine، PlaceRanking، NearbyDiscovery، Networking، BackendClient، GoogleProviders، DevMocks، Storage، Analytics، RemoteConfig — 36 اختبارًا تمرّ (13 + 8 + 11 + 4).
- **مُختبَر فعليًا:** الخادم الخلفي — فحص الأنواع و11 اختبار vitest.
- **مكتوب ومُراجَع بلا تجميع (يحتاج Mac):** DesignSystem، Features (الشاشات)، Location، وهدف التطبيق مع Google Maps/Navigation SDK. راجعته مراجعة مستقلة سطرًا سطرًا وطُبّقت كل ملاحظاتها، لكن أول بناء بـ Xcode 26 قد يكشف تفاصيل صغيرة (مثل `GMSRouteStatus.OK` أو واجهة حوار شروط الملاحة).
- التجربة الميدانية الحقيقية في الرياض هي خطوة الإغلاق قبل App Store (انظر `docs/APP_STORE_CHECKLIST.md`).
