# ما توفره Google فعليًا وما لا نزيّفه

مرجع القيود الذي بُني عليه `RouteModel` و`NearbyPlace` و`TrafficRouteScorer`. تمت مراجعته على الوثائق الرسمية بتاريخ 2026‑10‑07.

## Routes API v2 — `computeRoutes`

| الحاجة | المصدر الرسمي | الحالة |
|---|---|---|
| المسافة، المدة بالمرور، المدة بلا مرور | `distanceMeters`, `duration`, `staticDuration` | ✅ مباشر |
| تأخير المرور | `duration − staticDuration` | ✅ مشتق بثقة |
| كثافة المرور على المسار | `travelAdvisory.speedReadingIntervals` (NORMAL/SLOW/TRAFFIC_JAM) مع `extraComputations: TRAFFIC_ON_POLYLINE` | ✅ مباشر (SKU Advanced) |
| مسافة البطء / مسافة الاختناق | طول الفواصل على المسار المفكوك | ✅ مشتق |
| «توقف وانطلاق» | عدد فواصل TRAFFIC_JAM المنفصلة | ⚠️ مؤشر تقريبي موثّق، ليس عدّ توقفات فعليًا |
| عدد الانعطافات والالتفافات | `legs.steps.navigationInstruction.maneuver` | ✅ مشتق |
| الطرق البديلة | `computeAlternativeRoutes: true` → حتى 3 طرق (بلا نقاط وسيطة) | ✅ |
| أقصر مسافة | `requestedReferenceRoutes: ["SHORTER_DISTANCE"]` → `routeLabels: SHORTER_DISTANCE` | ✅ |
| قيود جزئية/تحذيرات | `warnings`, `travelAdvisory.routeRestrictionsPartiallyIgnored` | ✅ تُعاقَب |
| رمز المسار للملاحة | `routeToken` (يتطلب TRAFFIC_AWARE/OPTIMAL، DRIVE، بلا via) | ✅ يُمرَّر إلى Navigation SDK |
| الحوادث / الإغلاقات | غير متاحة في Routes API | ❌ `incidentCount = nil` ووزنها محفوظ لمزوّد مستقبلي |
| دقائق الاختناق الشديد بدقة | غير متاحة | ❌ `severeCongestionSeconds = nil`؛ نستخدم مسافة الاختناق بديلًا |
| نسبة الطرق المحلية | غير متاحة | ❌ `localRoadRatio = nil`؛ نعاقب التعقيد بالانعطافات بدلًا منها |
| الأحياء على المسار | `description` (ملخص Google للمسار، مثل اسم الطريق الرئيسي) | ⚠️ نعرض الملخص الرسمي؛ تسلسل الأحياء يتطلب Geocoding عكسيًا لعينات نقاط (مؤجّل، الحقل `neighborhoods` اختياري) |

## Routes API — `computeRouteMatrix`

- الحد: 625 عنصرًا، أو **100** مع `TRAFFIC_AWARE_OPTIMAL`. الخادم يرفض ما يتجاوز الحد قبل الإرسال، والعميل يقسم الدفعات.
- الحقول: `originIndex, destinationIndex, condition, distanceMeters, duration, staticDuration`.

## Places API (New)

- `searchNearby`: حد 20 نتيجة لكل طلب **بلا ترقيم صفحات**. نعوّض بـ fan‑out محدود (POPULARITY + DISTANCE × مجموعات أنواع) ثم دمج وإزالة التكرار. نصف القطر ≤ 50 كم.
- `routingParameters` + `routingSummaries`: وقت القيادة الفعلي (TRAFFIC_AWARE) لكل نتيجة ضمن نفس الطلب — هذا ما يجعل فلتر 5/10/15 دقيقة مبنيًا على ETA الحقيقي لا على تحويل مسافة.
- التصنيفات: من `types`/`primaryType` (Table A) وحقول Atmosphere (`servesBreakfast`, `outdoorSeating`…). **لا يوجد نوع موثوق لـ«سعودي»** فلا نعرضه. `shawarma_restaurant`, `barbecue_restaurant`, `steak_house`, `seafood_restaurant`, `hamburger_restaurant`, `pizza_restaurant`, `indian_restaurant` موجودة ومستخدمة.
- المنيو: لا يوجد حقل منيو منظّم في Places API (New). `menuURL = nil` ويُعرض «غير متاحة حاليًا». الموقع الرسمي (`websiteUri`) متاح كبديل.
- الصور: `photos[].name` → `GET /v1/{name}/media?maxWidthPx=…&skipHttpRedirect=true` ثم إعادة توجيه. يجب عرض `authorAttributions`.

## سياسات التخزين والإسناد (ملتزم بها في الكود)

- **يُخزَّن بلا حد**: `place ID` فقط (المفضلة، المنزل/العمل، سجل البحث).
- **لا يُخزَّن**: محتوى الأماكن والصور والطرق. الذاكرة المؤقتة للبحث القريب في الذاكرة فقط لمدة 120 ثانية ضمن الجلسة (معاملة المستخدم الفورية).
- نص العرض في سجل البحث يُحذف بعد 30 يومًا ويُعاد جلبه بالمعرّف.
- `URLCache` معطّل لطلبات Google؛ الخادم يردّ على الصور بـ `Cache-Control: no-store`.
- الإسناد: على خريطة Google لا شيء إضافي؛ في القوائم والتفاصيل `GoogleAttributionView` (شعار Google Maps عند توفر الأصل، وإلا نص «Google Maps»).

## Navigation SDK for iOS (11.2.0)

- iOS 16+ و Xcode 26. يتضمن Maps SDK 11.2.0.
- شروط الملاحة تُعرض مرة واحدة عبر `GMSNavigationServices.showTermsAndConditionsDialogIfNeeded(with:callback:)`.
- المسار المختار يُمرَّر عبر `setDestinations(_:routeToken:callback:)`؛ إعادة التوجيه التلقائية داخل SDK تحافظ على أهداف المسار المرمّزة.
- المتاح للقراءة: `timeToNextDestination`, `distanceToNextDestination`, `delayCategoryToNextDestination`, `currentRouteLeg`، وأحداث `didArriveAt`, `didUpdateRemainingTime/Distance`, `navigatorDidChangeRoute`.
- رأس المناورة التالية والإرشاد الصوتي (عربي/إنجليزي بلغة الجهاز) من SDK نفسه؛ لم نبنِ عرض مناورات مخصصًا كي لا نعتمد على واجهات غير موثّقة.
- «لقينا لك طريق أهدأ» تُحسب في التطبيق (RerouteDecider) بإعادة استدعاء Routes API دوريًا من الموقع الحالي، ثم تُبدَّل الوجهة برمز المسار الجديد.
