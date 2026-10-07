import Analytics
import DesignSystem
import Domain
import Foundation
import NearbyDiscovery
import PlaceRanking
import RemoteConfig
import Storage
import SwiftUI
import TrafficEngine

/// أسطح الخريطة — تُنفَّذ في هدف التطبيق بـ Google Maps/Navigation SDK. هنا نصف السلوك فقط.
@MainActor
public protocol MapSurfaces: AnyObject {
    /// خريطة الرئيسية: موقع المستخدم، بلا ازدحام بصري.
    func homeMap(userLocation: Coordinate?) -> AnyView
    /// خريطة مقارنة الطرق: المسارات الثلاثة مع إبراز المختار.
    func routesMap(origin: Coordinate, destination: Coordinate?, overlays: [MapRouteOverlay]) -> AnyView
    /// خريطة الأماكن القريبة: دبابيس + «البحث في هذه المنطقة».
    func nearbyMap(center: Coordinate, pins: [MapPin], onPinTap: @escaping (String) -> Void, onRegionMoved: @escaping (Coordinate) -> Void) -> AnyView
    /// سطح الملاحة (Navigation SDK) المرتبط بـ NavigationProvider.
    func navigationMap() -> AnyView
    /// اختيار نقطة من الخريطة.
    func pickerMap(initial: Coordinate, onMove: @escaping (Coordinate) -> Void) -> AnyView
}

/// حالة الرحلة المشتركة بين شاشة الطرق وشاشة الملاحة.
@MainActor @Observable
public final class TripState {
    public var origin: Coordinate?
    public var destination: Destination?
    public var options: RouteOptions?
    public var strategy: RouteStrategy = .noStop
    public var fromPlaceKindID: String?
    public init() {}

    public var selectedRoute: RouteModel? { options?.route(for: strategy) }
}

/// حاوية الاعتماديات. هدف التطبيق يبنيها إمّا بمزوّدات Google (Production) أو DevMocks (تطوير بلا مفاتيح).
@MainActor
public final class AppEnvironment {
    public let places: PlacesProvider
    public let routing: RoutingProvider
    public let travelTime: TravelTimeProvider
    public let location: LocationProviding
    public let analytics: AnalyticsClient
    public let remoteConfig: RemoteConfigService
    public let favorites: FavoritesStore
    public let recents: RecentSearchesStore
    public let savedAddresses: SavedAddressesStore
    public let settings: SettingsStore
    public let nearby: NearbyDiscoveryPipeline
    public let maps: MapSurfaces
    public let navigation: NavigationProvider
    public let trip = TripState()
    /// true عند استخدام DevMocks — يُظهر شارة «بيانات تجريبية» ولا يُسمح به في Release.
    public let isDevMock: Bool

    public init(
        places: PlacesProvider, routing: RoutingProvider, travelTime: TravelTimeProvider, location: LocationProviding,
        analytics: AnalyticsClient, remoteConfig: RemoteConfigService, favorites: FavoritesStore, recents: RecentSearchesStore,
        savedAddresses: SavedAddressesStore, settings: SettingsStore, maps: MapSurfaces, navigation: NavigationProvider, isDevMock: Bool
    ) {
        self.places = places
        self.routing = routing
        self.travelTime = travelTime
        self.location = location
        self.analytics = analytics
        self.remoteConfig = remoteConfig
        self.favorites = favorites
        self.recents = recents
        self.savedAddresses = savedAddresses
        self.settings = settings
        self.maps = maps
        self.navigation = navigation
        self.isDevMock = isDevMock
        let cfg = remoteConfig.initialConfig
        self.nearby = NearbyDiscoveryPipeline(
            places: places, travelTime: travelTime,
            ranking: PlaceRankingEngine(weights: cfg.rankingWeights),
            config: NearbySearchConfig(
                prefilterRadiusMeters: cfg.nearby.prefilterRadiusMeters, maxFanOutRequests: cfg.nearby.maxFanOutRequests,
                typesPerRequest: cfg.nearby.typesPerRequest, maxCandidates: cfg.nearby.maxCandidates,
                cacheTTLSeconds: cfg.nearby.cacheTTLSeconds, preferRoutingSummaries: cfg.nearby.preferRoutingSummaries
            )
        )
    }

    /// لغة الواجهة الحالية بصيغة BCP‑47 المدعومة من Google.
    public var languageCode: String {
        let code = Locale.current.language.languageCode?.identifier ?? "ar"
        return code.hasPrefix("ar") ? "ar" : "en"
    }

    public var regionCode: String { Locale.current.region?.identifier ?? "SA" }
    public var isRTL: Bool { languageCode == "ar" }

    public func routeSelector() async -> RouteSelector {
        let cfg = await remoteConfig.config
        return RouteSelector(scorer: TrafficRouteScorer(weights: cfg.trafficWeights))
    }
}

// MARK: - الترجمة

/// مفاتيح الترجمة من Localizable.xcstrings داخل الحزمة.
/// نقرأ النص الخام من الكتالوج (بلا تمرير تنسيق) ثم نطبّق String(format:) بأنفسنا للمفاتيح ذات المعاملات.
public func L(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

public func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}

extension EnvironmentValues {
    @Entry public var appEnv: AppEnvironment? = nil
}

// MARK: - سطح خريطة بديل (معاينات/اختبارات واجهة بلا SDK)

@MainActor
public final class PlaceholderMapSurfaces: MapSurfaces {
    public init() {}

    public func homeMap(userLocation: Coordinate?) -> AnyView { AnyView(PlaceholderMap(dark: false, showUser: true)) }
    public func routesMap(origin: Coordinate, destination: Coordinate?, overlays: [MapRouteOverlay]) -> AnyView { AnyView(PlaceholderMap(dark: false, showUser: true, overlays: overlays)) }
    public func nearbyMap(center: Coordinate, pins: [MapPin], onPinTap: @escaping (String) -> Void, onRegionMoved: @escaping (Coordinate) -> Void) -> AnyView {
        AnyView(PlaceholderMap(dark: false, showUser: true, pins: pins, onPinTap: onPinTap))
    }
    public func navigationMap() -> AnyView { AnyView(PlaceholderMap(dark: true, showUser: true)) }
    public func pickerMap(initial: Coordinate, onMove: @escaping (Coordinate) -> Void) -> AnyView { AnyView(PlaceholderMap(dark: false, showUser: false)) }
}

/// شبكة شوارع مجرّدة بأسلوب النموذج — تُستخدم فقط حين لا يتوفر Google Maps SDK.
struct PlaceholderMap: View {
    var dark: Bool
    var showUser: Bool
    var overlays: [MapRouteOverlay] = []
    var pins: [MapPin] = []
    var onPinTap: ((String) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (dark ? BZColor.night : BZColor.mapBase)
                Canvas { ctx, size in
                    let road = dark ? Color(hex: 0x1E4551) : Color.white
                    let minor = dark ? Color(hex: 0x193E49) : Color(hex: 0xDFE4E1)
                    for y in stride(from: 0.2, through: 0.8, by: 0.3) {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: size.height * y)); p.addLine(to: CGPoint(x: size.width, y: size.height * y))
                        ctx.stroke(p, with: .color(road), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    }
                    for x in [0.27, 0.72] {
                        var p = Path(); p.move(to: CGPoint(x: size.width * x, y: 0)); p.addLine(to: CGPoint(x: size.width * x, y: size.height))
                        ctx.stroke(p, with: .color(road), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    }
                    for y in [0.36, 0.62] {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: size.height * y)); p.addLine(to: CGPoint(x: size.width, y: size.height * y))
                        ctx.stroke(p, with: .color(minor), lineWidth: 6)
                    }
                    var p = Path(); p.move(to: CGPoint(x: size.width * 0.5, y: 0)); p.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
                    ctx.stroke(p, with: .color(minor), lineWidth: 6)
                }
                ForEach(overlays) { o in
                    let color: Color = o.strategy == .noStop ? BZColor.green : (o.strategy == .fastest ? BZColor.sky : BZColor.mute)
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.6))
                        p.addLine(to: CGPoint(x: geo.size.width * (o.strategy == .noStop ? 0.27 : (o.strategy == .fastest ? 0.5 : 0.72)), y: geo.size.height * 0.36))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.72, y: geo.size.height * 0.12))
                    }
                    .stroke(o.highlighted ? color : Color(hex: 0xC7CECB), style: StrokeStyle(lineWidth: o.highlighted ? 12 : 7, lineCap: .round, lineJoin: .round))
                }
                ForEach(pins) { pin in
                    Button { onPinTap?(pin.id) } label: {
                        Text(pin.subtitle ?? pin.title)
                            .font(BZFont.small.weight(.heavy))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(pin.selected ? BZColor.sky : Color.white, in: Capsule())
                            .foregroundStyle(pin.selected ? .white : BZColor.ink)
                            .shadow(color: BZColor.ink.opacity(0.18), radius: 7, y: 3)
                    }
                    .position(x: geo.size.width * CGFloat(abs(pin.coordinate.longitude.truncatingRemainder(dividingBy: 0.1)) * 8 + 0.1),
                              y: geo.size.height * CGFloat(abs(pin.coordinate.latitude.truncatingRemainder(dividingBy: 0.1)) * 8 + 0.1))
                }
                if showUser {
                    ZStack {
                        Circle().fill(BZColor.green).frame(width: 18, height: 18).overlay(Circle().stroke(.white, lineWidth: 3))
                        PulseRing()
                    }
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.6)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct PulseRing: View {
    @State private var on = false
    var body: some View {
        Circle().fill(BZColor.green).frame(width: 18, height: 18)
            .scaleEffect(on ? 2.6 : 1).opacity(on ? 0 : 0.6)
            .onAppear { withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { on = true } }
    }
}
