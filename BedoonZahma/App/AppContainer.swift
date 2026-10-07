import Analytics
import BackendClient
import DevMocks
import Domain
import Features
import Foundation
import GoogleProviders
import Location
import Networking
import RemoteConfig
import Storage
import TomTomProviders
import TrafficEngine

/// قراءة الإعدادات المحقونة من xcconfig عبر Info.plist.
enum AppConfig {
    private static func string(_ key: String) -> String? {
        let v = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    static var googleMapsIOSKey: String? { string("GoogleMapsIOSKey") }
    /// يتحقق أن الرابط يحمل مضيفًا فعليًا (حماية من خطأ xcconfig حيث يقطع "//" القيمة إلى "https:" فقط).
    static var backendURL: URL? {
        guard let raw = string("BZBackendURL"), let url = URL(string: raw), let host = url.host, !host.isEmpty else {
            NSLog("[Mishwarak] BZBackendURL غير صالح: %@", string("BZBackendURL") ?? "nil")
            return nil
        }
        return url
    }
    static var appKey: String { string("BZAppKey") ?? "" }
    static var appVersion: String { (string("CFBundleShortVersionString") ?? "0") + "+" + (string("CFBundleVersion") ?? "0") }
    /// مزوّد البيانات: "tomtom" (مجاني؛ خريطة Apple MapKit وإرشاد ذاتي) أو "google" (Maps/Navigation SDK).
    static var mapsProvider: String { (string("BZMapsProvider") ?? "tomtom").lowercased() }

    /// Mocks مسموحة في DEBUG فقط. في Release تُتجاهل القيمة نهائيًا.
    static var useMocks: Bool {
        #if DEBUG
        return string("BZUseMocks") == "1"
        #else
        return false
        #endif
    }
}

/// تركيب الاعتماديات: Production = Google عبر الخادم الخلفي؛ DEBUG + BZ_USE_MOCKS=1 = DevMocks.
@MainActor
enum AppContainer {
    static func makeEnvironment() -> AppEnvironment {
        let monitor = APIUsageMonitor()
        let http = HTTPClient(monitor: monitor)
        let backend: BackendAPI? = AppConfig.backendURL.map {
            BackendAPI(http: http, config: BackendConfiguration(baseURL: $0, appKey: AppConfig.appKey, appVersion: AppConfig.appVersion))
        }
        let remoteConfig = RemoteConfigService(api: backend)
        let analytics = AnalyticsService(api: backend)

        if AppConfig.useMocks {
            return AppEnvironment(
                places: MockPlacesProvider(), routing: MockRoutingProvider(), travelTime: MockTravelTimeProvider(),
                location: MockLocationProvider(), analytics: NoopAnalytics(), remoteConfig: remoteConfig,
                favorites: FavoritesStore(), recents: RecentSearchesStore(), savedAddresses: SavedAddressesStore(), settings: SettingsStore(),
                maps: PlaceholderMapSurfaces(), navigation: SimulatedNavigationProvider(), isDevMock: true
            )
        }

        guard let backend else {
            // بلا خادم لا يمكن تشغيل الإنتاج — نُفشل مبكرًا بدل عرض بيانات وهمية.
            fatalError("BZ_BACKEND_URL مفقود. راجع Config/*.xcconfig")
        }

        if AppConfig.mapsProvider == "tomtom" {
            // TomTom (بيانات حقيقية بمرور حي) + Apple MapKit (خريطة) + إرشاد ذاتي — بلا مفاتيح على الجهاز إطلاقًا.
            let routing = TomTomRoutingProvider(api: backend)
            let guidance = GuidanceNavigationProvider(routing: routing) {
                let cfg = await remoteConfig.config
                return RouteSelector(scorer: TrafficRouteScorer(weights: cfg.trafficWeights))
            }
            return AppEnvironment(
                places: TomTomPlacesProvider(api: backend),
                routing: routing,
                travelTime: TomTomTravelTimeProvider(api: backend),
                location: LocationService(),
                analytics: analytics,
                remoteConfig: remoteConfig,
                favorites: FavoritesStore(), recents: RecentSearchesStore(), savedAddresses: SavedAddressesStore(), settings: SettingsStore(),
                maps: MapKitMapSurfaces(navigation: guidance),
                navigation: guidance,
                isDevMock: false
            )
        }

        // بلا مفتاح Maps SDK (مثل بناء TestFlight قبل تفعيل Google Cloud) لا نُهيّئ Google Maps كي لا ينهار التطبيق؛
        // تُعرض خريطة محايدة وتفشل الملاحة بخطأ واضح، وتبقى بيانات الأماكن والطرق حقيقية عبر الخادم.
        let hasMapsKey = !(AppConfig.googleMapsIOSKey ?? "").isEmpty
        let navigation: NavigationProvider = hasMapsKey ? GoogleNavigationProvider() : UnavailableNavigationProvider()
        let maps: MapSurfaces = hasMapsKey ? GoogleMapSurfaces(navigation: navigation as! GoogleNavigationProvider) : PlaceholderMapSurfaces()
        return AppEnvironment(
            places: GooglePlacesProvider(api: backend),
            routing: GoogleRoutingProvider(api: backend),
            travelTime: GoogleTravelTimeProvider(api: backend),
            location: LocationService(),
            analytics: analytics,
            remoteConfig: remoteConfig,
            favorites: FavoritesStore(), recents: RecentSearchesStore(), savedAddresses: SavedAddressesStore(), settings: SettingsStore(),
            maps: maps,
            navigation: navigation,
            isDevMock: false
        )
    }
}
