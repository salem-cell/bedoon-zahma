# جاهزية App Store — قائمة التحقق

## مفاتيح وأمان
- [ ] مفتاح iOS (`GOOGLE_MAPS_IOS_KEY`) مقيّد بـ Bundle ID `sa.mishwarak.app` وبـ Maps SDK + Navigation SDK فقط.
- [ ] مفتاح الخادم مقيّد بـ IP وبـ Routes API + Places API (New) فقط، ومخزّن في Secret Manager/متغيرات البيئة.
- [ ] `Secrets.xcconfig` و`backend/.env` خارج git (مضبوط في `.gitignore`).
- [ ] `BZ_USE_MOCKS=0` في Release (مفروض بالكود أيضًا: Mocks تعمل في DEBUG فقط).
- [ ] ATS مفعّل (`NSAllowsArbitraryLoads=false`)، الخادم HTTPS فقط.

## الخصوصية
- [ ] `NSLocationWhenInUseUsageDescription` بالعربية والإنجليزية (InfoPlist.xcstrings).
- [ ] `PrivacyInfo.xcprivacy`: موقع دقيق (وظيفة التطبيق، غير مرتبط بالهوية)، تفاعل المنتج (تحليلات)، لا تتبّع.
- [ ] Nutrition labels في App Store Connect تطابق البيان: Precise Location (App Functionality)، Product Interaction (Analytics).
- [ ] لا تخزين لسجل الموقع؛ «مسح السجل» متاح؛ التحليلات بلا إحداثيات ولا معرّفات أشخاص (مفروض في الخادم).
- [ ] UIBackgroundModes: `location` و`audio` مبرّران بالملاحة الصوتية أثناء القفل — اذكر ذلك في ملاحظات المراجعة.

## Google Maps Platform
- [ ] شروط الملاحة تُعرض عبر SDK قبل أول رحلة.
- [ ] شعار Google Maps في القوائم/التفاصيل (أضف أصل `GoogleMapsLogo` من حزمة الشعارات الرسمية إلى Assets.xcassets؛ النص بديل مؤقت).
- [ ] إسناد مصوّري الصور ظاهر على الصور.
- [ ] «عرض في Google Maps» يستخدم `googleMapsUri` الرسمي.
- [ ] لا تخزين لمحتوى Google (مراجعة GOOGLE_DATA_LIMITS.md).

## الجودة
- [ ] `xcodegen generate` ثم بناء Release بلا تحذيرات حرجة.
- [ ] اختبارات الحزمة الأربع خضراء (`swift test` من مجلد الحزمة على macOS).
- [ ] UI Tests على المحاكي بوضع Mocks.
- [ ] تجربة ميدانية حقيقية في الرياض: بحث → 3 طرق → ملاحة → وصول؛ مقاهيي ≤5 دقائق → تفاصيل → اذهب الآن.
- [ ] RTL/LTR: تبديل لغة الجهاز بين العربية والإنجليزية.
- [ ] الأداء: القائمة تظهر خلال < 2 ثانية على شبكة 4G (fan‑out متوازٍ + routingSummaries).

## الأصول
- [ ] أيقونة التطبيق 1024×1024 في `AppIcon.appiconset`.
- [ ] لقطات شاشة 6.7″ و6.1″ عربية وإنجليزية.
- [ ] وصف المتجر: «اختر كيف تبي توصل» + شرح 🟢⚡📏 و☕🍽️ خلال 5/10/15 دقيقة.
