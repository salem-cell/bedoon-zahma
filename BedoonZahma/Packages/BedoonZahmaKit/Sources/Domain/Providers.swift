import Foundation

// MARK: - طبقة المزوّد
// Google هو المزوّد الأساسي الآن (GoogleProviders)، لكن منطق المنتج يعتمد على هذه البروتوكولات فقط.

public struct RouteRequest: Hashable, Sendable {
    public var origin: Coordinate
    public var destination: Destination
    public var languageCode: String
    public var avoidTolls: Bool
    public var departureTime: Date?
    /// اتجاه حركة المركبة بالدرجات (0–359) إن كان معروفًا — يمنع اقتراح التفاف عند البداية.
    public var headingDegrees: Int?
    public init(origin: Coordinate, destination: Destination, languageCode: String, avoidTolls: Bool = false, departureTime: Date? = nil, headingDegrees: Int? = nil) {
        self.origin = origin
        self.destination = destination
        self.languageCode = languageCode
        self.avoidTolls = avoidTolls
        self.departureTime = departureTime
        self.headingDegrees = headingDegrees
    }
}

public protocol RoutingProvider: Sendable {
    /// يرجع كل الطرق المرشّحة (الافتراضي + البدائل + مرجع أقصر مسافة) مع بيانات المرور عند توفرها.
    func computeRoutes(_ request: RouteRequest) async throws -> [RouteModel]
}

public struct TravelTimeResult: Hashable, Sendable {
    public var destinationIndex: Int
    public var durationSeconds: Int?
    public var staticDurationSeconds: Int?
    public var distanceMeters: Int?
    public var routeExists: Bool
    public init(destinationIndex: Int, durationSeconds: Int?, staticDurationSeconds: Int?, distanceMeters: Int?, routeExists: Bool) {
        self.destinationIndex = destinationIndex
        self.durationSeconds = durationSeconds
        self.staticDurationSeconds = staticDurationSeconds
        self.distanceMeters = distanceMeters
        self.routeExists = routeExists
    }
}

public protocol TravelTimeProvider: Sendable {
    /// أقصى عدد عناصر في طلب واحد (Google: 100 مع TRAFFIC_AWARE_OPTIMAL، 625 بدونه).
    var maxElementsPerRequest: Int { get }
    func travelTimes(from origin: Coordinate, to destinations: [Coordinate], trafficAware: Bool) async throws -> [TravelTimeResult]
}

public struct NearbySearchRequest: Hashable, Sendable {
    public var center: Coordinate
    public var radiusMeters: Double
    public var includedTypes: [String]
    public var maxResultCount: Int
    public var rankByDistance: Bool
    public var languageCode: String
    public var regionCode: String
    /// عند true يطلب routingSummaries (ETA فعلي بالمرور من الأصل) ضمن نفس الطلب.
    public var includeDrivingETA: Bool
    public init(center: Coordinate, radiusMeters: Double, includedTypes: [String], maxResultCount: Int = 20, rankByDistance: Bool = false, languageCode: String, regionCode: String, includeDrivingETA: Bool = true) {
        self.center = center
        self.radiusMeters = radiusMeters
        self.includedTypes = includedTypes
        self.maxResultCount = maxResultCount
        self.rankByDistance = rankByDistance
        self.languageCode = languageCode
        self.regionCode = regionCode
        self.includeDrivingETA = includeDrivingETA
    }
}

public struct AutocompleteRequest: Hashable, Sendable {
    public var input: String
    public var origin: Coordinate?
    public var biasCenter: Coordinate?
    public var biasRadiusMeters: Double
    public var regionCodes: [String]
    public var languageCode: String
    public var sessionToken: String
    public init(input: String, origin: Coordinate?, biasCenter: Coordinate?, biasRadiusMeters: Double = 50_000, regionCodes: [String], languageCode: String, sessionToken: String) {
        self.input = input
        self.origin = origin
        self.biasCenter = biasCenter
        self.biasRadiusMeters = biasRadiusMeters
        self.regionCodes = regionCodes
        self.languageCode = languageCode
        self.sessionToken = sessionToken
    }
}

public enum PlaceDetailLevel: String, Sendable {
    /// للبحث والمسار: المعرّف والاسم والإحداثية والأنواع.
    case basic
    /// لبطاقات القوائم (المفضلة): + التقييم والعدد والصور وحالة الفتح والسعر والحي.
    case card
    /// لصفحة التفاصيل: كل الحقول المدعومة.
    case full
}

public protocol PlacesProvider: Sendable {
    func searchNearby(_ request: NearbySearchRequest) async throws -> [NearbyPlace]
    func autocomplete(_ request: AutocompleteRequest) async throws -> [SearchSuggestion]
    func placeDetails(placeID: String, level: PlaceDetailLevel, languageCode: String, sessionToken: String?) async throws -> NearbyPlace
    /// رابط الصورة بالحجم المطلوب (يمرّ عبر الخادم الخلفي كي لا يُكشف المفتاح).
    func photoURL(for photo: PhotoReference, maxWidthPx: Int) -> URL?
}

// MARK: - الملاحة

/// المناورة التالية (للإرشاد الذاتي المبني على MapKit). nil عندما يرسم SDK الملاحة رأسه الخاص.
public struct GuidanceInstruction: Equatable, Sendable {
    public var text: String
    public var maneuver: Maneuver?
    public var distanceMeters: Int
    public var streetName: String?
    public init(text: String, maneuver: Maneuver?, distanceMeters: Int, streetName: String?) {
        self.text = text
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.streetName = streetName
    }
}

public enum NavigationState: Equatable, Sendable {
    case idle
    case calculating
    case guiding(remainingSeconds: Int?, remainingMeters: Int?, delay: TrafficDelayCategory, instruction: GuidanceInstruction? = nil)
    case arrived
    case failed(String)
}

public enum TrafficDelayCategory: String, Equatable, Sendable {
    case noData, light, medium, heavy
}

/// واجهة الملاحة المجردة. التنفيذ الفعلي في هدف التطبيق عبر Google Navigation SDK.
@MainActor
public protocol NavigationProvider: AnyObject {
    var state: NavigationState { get }
    var stateStream: AsyncStream<NavigationState> { get }
    func start(route: RouteModel, destination: Destination, strategy: RouteStrategy) async throws
    func stop()
    func setVoiceGuidance(enabled: Bool)
    /// المسار الحالي (قد يتغيّر بإعادة التوجيه) — لرسمه على خريطة لا يملكها SDK الملاحة.
    var activeRoute: RouteModel? { get }
    /// آخر موقع معروف أثناء الملاحة (لمتابعة الكاميرا).
    var currentLocation: Coordinate? { get }
}

public extension NavigationProvider {
    var activeRoute: RouteModel? { nil }
    var currentLocation: Coordinate? { nil }
}

// MARK: - الموقع

public enum LocationAuthorization: Equatable, Sendable {
    case notDetermined, denied, restricted, whenInUse, always
}

public protocol LocationProviding: Sendable {
    var authorization: LocationAuthorization { get async }
    func requestWhenInUseAuthorization() async -> LocationAuthorization
    func currentLocation() async throws -> Coordinate
    /// تحديثات موفّرة للبطارية (دقة ~100م) للاستخدام خارج الملاحة.
    func locationUpdates() -> AsyncStream<Coordinate>
}

// MARK: - التحليلات

public struct AnalyticsEvent: Codable, Hashable, Sendable {
    public var name: String
    public var params: [String: String]
    public var timestamp: Date
    public init(name: String, params: [String: String] = [:], timestamp: Date = .init()) {
        self.name = name
        self.params = params
        self.timestamp = timestamp
    }
}

public protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
}

// MARK: - أسطح الخريطة (تُنفَّذ في هدف التطبيق بواسطة Google Maps SDK)

public struct MapPin: Identifiable, Hashable, Sendable {
    public var id: String
    public var coordinate: Coordinate
    public var title: String
    public var subtitle: String?
    public var selected: Bool
    public init(id: String, coordinate: Coordinate, title: String, subtitle: String?, selected: Bool) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
    }
}

public struct MapRouteOverlay: Identifiable, Hashable, Sendable {
    public var id: String
    public var encodedPolyline: String
    public var highlighted: Bool
    public var strategy: RouteStrategy?
    public var speedIntervals: [SpeedReadingInterval]?
    public init(id: String, encodedPolyline: String, highlighted: Bool, strategy: RouteStrategy?, speedIntervals: [SpeedReadingInterval]?) {
        self.id = id
        self.encodedPolyline = encodedPolyline
        self.highlighted = highlighted
        self.strategy = strategy
        self.speedIntervals = speedIntervals
    }
}
