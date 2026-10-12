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
    /// مزوّد البيانات: "tomtom" أو "google" (الطرق والأماكن عبر الخادم).
    static var mapsProvider: String { (string("BZMapsProvider") ?? "tomtom").lowercased() }
    /// طبقة العرض والملاحة: "mapkit" (Apple MapKit + إرشاد ذاتي، بلا مفتاح على الجهاز) أو "google" (Maps SDK + Navigation SDK بمفتاح iOS).
    static var mapRenderer: String { (string("BZMapRenderer") ?? "mapkit").lowercased() }

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

        // بيانات Google (طرق بمرور حي + أماكن بتقييمات وصور وساعات) عبر الخادم.
        // طبقة العرض: افتراضيًا Apple MapKit + إرشاد ذاتي (لا مفتاح على الجهاز)؛ وبـ BZ_MAP_RENDERER=google مع مفتاح iOS → Maps SDK + Navigation SDK.
        let googleRouting = GoogleRoutingProvider(api: backend)
        let hasMapsKey = !(AppConfig.googleMapsIOSKey ?? "").isEmpty
        let useGoogleRenderer = AppConfig.mapRenderer == "google" && hasMapsKey
        let navigation: NavigationProvider
        let maps: MapSurfaces
        if useGoogleRenderer {
            let g = GoogleNavigationProvider()
            navigation = g
            maps = GoogleMapSurfaces(navigation: g)
        } else {
            let guidance = GuidanceNavigationProvider(routing: googleRouting) {
                let cfg = await remoteConfig.config
                return RouteSelector(scorer: TrafficRouteScorer(weights: cfg.trafficWeights))
            }
            navigation = guidance
            maps = MapKitMapSurfaces(navigation: guidance)
        }
        return AppEnvironment(
            places: GooglePlacesProvider(api: backend),
            routing: googleRouting,
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
