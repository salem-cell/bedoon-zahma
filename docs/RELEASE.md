# النشر إلى TestFlight وApp Store بلا جهاز Mac

كل شيء يعمل على Mac سحابي في GitHub Actions (`.github/workflows/release.yml`).

## الحالة الحالية (2026‑10‑07)

✅ **الرفع إلى App Store Connect نجح** (تشغيل 37696912758 — Archive Succeeded / Export Succeeded مع الرفع). ✅ **الأرشفة والتوقيع يعملان**: تشغيل `Release to TestFlight` رقم 37680673340 أنتج أرشيف Release موقّعًا بمفتاح API، وتوقف فقط عند الرفع برسالة `Error Downloading App Information` لأن سجل التطبيق غير موجود بعد في App Store Connect.

| البند | الحالة |
|---|---|
| مفتاح App Store Connect API (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`) وفريق Apple (`APPLE_TEAM_ID`) | ✅ موجودة كأسرار في المستودع |
| معرّف الحزمة `sa.mishwarak.app` في حساب المطوّر | ✅ مسجَّل (ID: 7B2RB5552P) |
| الخادم الخلفي | ✅ منشور على Vercel: `https://bedoon-zahma-backend.vercel.app` (`BZ_BACKEND_URL`, `BZ_APP_KEY` مضبوطان) |
| سجل التطبيق في App Store Connect | ✅ أُنشئ (App ID 6820280275، SKU MISHWARAK-IOS-001) |
| مفتاح TomTom (`TOMTOM_API_KEY` على Vercel) | ✅ مضبوط ومُختبَر (2026‑10‑08): طرق حقيقية ببدائل وأقسام مرور، 100 مقهى/طلب، بحث عربي |
| مفتاح Google Maps Platform لـ iOS (`GOOGLE_MAPS_IOS_KEY`) | ✅ مُنشأ ومقيّد ومخزّن في GitHub (يُستخدم عند BZ_MAP_RENDERER=google) |
| ~~مفتاح Google Maps Platform لـ iOS~~ (`GOOGLE_MAPS_IOS_KEY`) | ❌ من Google Cloud Console: فعّل Maps SDK for iOS وNavigation SDK وأنشئ مفتاحًا مقيّدًا بـ iOS/Bundle ID. بدونه يعمل التطبيق بخريطة محايدة وتُعطَّل الملاحة مع رسالة واضحة |
| مفتاح Google الخادمي (`GOOGLE_SERVER_API_KEY` على Vercel) | ✅ مضبوط؛ MAPS_PROVIDER=google |
| ~~مفتاح Google الخادمي~~ (`GOOGLE_SERVER_API_KEY` على Vercel) | ❌ فعّل Routes API وPlaces API (New)، أنشئ مفتاحًا مقيّدًا بالـ APIs، ثم: `vercel env rm GOOGLE_SERVER_API_KEY production && printf 'AIza…' \| vercel env add GOOGLE_SERVER_API_KEY production && vercel deploy --prod` من مجلد `backend/` |

بعد إكمال البنود الثلاثة الناقصة، شغّل **Actions → Release to TestFlight → Run workflow**.

تحتاج مرة واحدة إلى:

## 1) حساب Apple Developer ومفتاح App Store Connect API
1. من [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access → Integrations → App Store Connect API** → أنشئ مفتاحًا بدور **App Manager** (أو Admin).
2. احفظ **Key ID** و**Issuer ID** ونزّل ملف `AuthKey_XXXXXXXXXX.p8` (يُنزَّل مرة واحدة فقط).
3. أنشئ التطبيق في App Store Connect: **Apps → +** باسم «مشوارك أسهل» وBundle ID `sa.mishwarak.app` (أنشئ المعرّف أولًا من **Certificates, Identifiers & Profiles → Identifiers**).
4. معرّف الفريق (Team ID) من **Membership details**.

## 2) أسرار GitHub
في المستودع `salem-cell/bedoon-zahma` → **Settings → Secrets and variables → Actions → New repository secret**:

| الاسم | القيمة |
|---|---|
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | محتوى `.p8` بترميز base64 |
| `APPLE_TEAM_ID` | Team ID |
| `GOOGLE_MAPS_IOS_KEY` | مفتاح Maps/Navigation SDK المقيّد بـ `sa.mishwarak.app` |
| `BZ_APP_KEY` | نفس القيمة في `backend/.env` → `APP_KEYS` |
| `BZ_BACKEND_URL` | رابط الخادم الخلفي HTTPS |

لتشفير `.p8` على Windows:

```bash
certutil -encode AuthKey_XXXXXXXXXX.p8 key.b64.txt
```

ثم انسخ المحتوى بين سطري BEGIN/END (بلا السطرين) إلى السر. على Mac/Linux: `base64 -i AuthKey.p8 | pbcopy`.

## 3) التشغيل
من تبويب **Actions → Release to TestFlight → Run workflow**. يأخذ 15 إلى 30 دقيقة. التوقيع سحابي تلقائي (Xcode Managed) عبر مفتاح API، فلا حاجة لشهادات أو ملفات تزويد يدوية.

بعد الرفع يظهر البناء في **TestFlight** خلال دقائق لمعالجة Apple. مجموعة داخلية باسم **Internal** (تصل لكل البناءات تلقائيًا) أُنشئت وأُضيف إليها أعضاء الفريق: dafaat.ksa@gmail.com، flysmh@yahoo.com، mr.hussein.5566@gmail.com. ثبّت تطبيق TestFlight على iPhone بنفس Apple ID وستجد «مشوارك أسهل».

## 4) الخادم الخلفي
انشر `backend/` (Docker/Cloud Run) قبل أول بناء إنتاجي، وضع رابطه في `BZ_BACKEND_URL`. بلا خادم لا يُقلع بناء Release (مقصود: لا بيانات وهمية في الإنتاج).

## استكشاف الأخطاء
- **No profiles / signing**: تأكد أن المفتاح بدور App Manager وأن Bundle ID مُسجَّل، وأن `APPLE_TEAM_ID` صحيح.
- **ITMS-90xxx عند الرفع**: راجع `release-logs` في artifacts؛ أغلبها أيقونة ناقصة (أضف 1024×1024 في `AppIcon.appiconset`) أو نص إذن الموقع.
- **رفض Google Maps attribution**: أضف شعار Google Maps الرسمي إلى `GoogleMapsLogo.imageset`.
