import Foundation

/// استراتيجيات «كيف أبي أوصل؟»
public enum RouteStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 🟢 بدون توقف — أقل احتكاك مروري حتى لو كان أطول.
    case noStop = "no_stop"
    /// ⚡ أسرع طريق — أقل مدة بالمرور الحالي.
    case fastest
    /// 📏 أقصر طريق — أقل مسافة.
    case shortest

    public var id: String { rawValue }
}

/// تسميات Google لطرق الاستجابة (routeLabels).
public enum RouteLabel: String, Codable, Sendable {
    case defaultRoute = "DEFAULT_ROUTE"
    case defaultRouteAlternate = "DEFAULT_ROUTE_ALTERNATE"
    case fuelEfficient = "FUEL_EFFICIENT"
    case shorterDistance = "SHORTER_DISTANCE"
    case unknown
}

/// كثافة المرور على فاصل من المسار كما يرجعها Routes API (TRAFFIC_ON_POLYLINE).
public enum TrafficSpeed: String, Codable, Sendable {
    case normal = "NORMAL"
    case slow = "SLOW"
    case trafficJam = "TRAFFIC_JAM"
}

public struct SpeedReadingInterval: Codable, Hashable, Sendable {
    public var startPolylinePointIndex: Int
    public var endPolylinePointIndex: Int
    public var speed: TrafficSpeed
    public init(startPolylinePointIndex: Int, endPolylinePointIndex: Int, speed: TrafficSpeed) {
        self.startPolylinePointIndex = startPolylinePointIndex
        self.endPolylinePointIndex = endPolylinePointIndex
        self.speed = speed
    }
}

public enum Maneuver: String, Codable, Sendable {
    case turnSlightLeft = "TURN_SLIGHT_LEFT", turnSharpLeft = "TURN_SHARP_LEFT", uturnLeft = "UTURN_LEFT", turnLeft = "TURN_LEFT"
    case turnSlightRight = "TURN_SLIGHT_RIGHT", turnSharpRight = "TURN_SHARP_RIGHT", uturnRight = "UTURN_RIGHT", turnRight = "TURN_RIGHT"
    case straight = "STRAIGHT", rampLeft = "RAMP_LEFT", rampRight = "RAMP_RIGHT", merge = "MERGE"
    case forkLeft = "FORK_LEFT", forkRight = "FORK_RIGHT", ferry = "FERRY", ferryTrain = "FERRY_TRAIN"
    case roundaboutLeft = "ROUNDABOUT_LEFT", roundaboutRight = "ROUNDABOUT_RIGHT", depart = "DEPART", nameChange = "NAME_CHANGE"
    case unspecified = "MANEUVER_UNSPECIFIED"

    public var isTurn: Bool {
        switch self {
        case .turnSlightLeft, .turnSharpLeft, .turnLeft, .turnSlightRight, .turnSharpRight, .turnRight,
             .rampLeft, .rampRight, .forkLeft, .forkRight, .roundaboutLeft, .roundaboutRight:
            return true
        default:
            return false
        }
    }

    public var isUTurn: Bool { self == .uturnLeft || self == .uturnRight }
}

public struct RouteStep: Codable, Hashable, Sendable {
    public var instruction: String?
    public var maneuver: Maneuver?
    public var distanceMeters: Int
    public var staticDurationSeconds: Int?
    public init(instruction: String?, maneuver: Maneuver?, distanceMeters: Int, staticDurationSeconds: Int?) {
        self.instruction = instruction
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.staticDurationSeconds = staticDurationSeconds
    }
}

public struct LocalizedRouteValues: Codable, Hashable, Sendable {
    public var distance: String?
    public var duration: String?
    public var staticDuration: String?
    public init(distance: String?, duration: String?, staticDuration: String?) {
        self.distance = distance
        self.duration = duration
        self.staticDuration = staticDuration
    }
}

/// النموذج الموحّد للطريق. أي حقل لا يوفره المزوّد مباشرة أو لا يمكن اشتقاقه بثقة يبقى nil ولا يُخترع.
///
/// ما يوفره Routes API مباشرة: المسافة، المدة بالمرور، المدة بلا مرور، المسار، فواصل السرعة، الخطوات، التسميات، route token.
/// ما نشتقه بثقة (انظر TrafficEngine.RouteMetricsDeriver): تأخير المرور، مسافة البطء، مسافة الاختناق،
/// عدد فواصل الاختناق (مؤشر توقف‑وانطلاق)، عدد الانعطافات، عدد الالتفافات.
/// ما لا يوفره Google ولا نزيّفه: عدد الحوادث، دقائق الاختناق الشديد بدقة، نسبة الطرق المحلية.
public struct RouteModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var labels: [RouteLabel]
    public var distanceMeters: Int
    /// المدة بالمرور الحالي (ثوانٍ). مع TRAFFIC_AWARE* تساوي `duration`.
    public var durationSeconds: Int
    /// المدة بلا اعتبار المرور (ثوانٍ) — `staticDuration`.
    public var staticDurationSeconds: Int?
    public var encodedPolyline: String
    public var speedReadingIntervals: [SpeedReadingInterval]?
    public var steps: [RouteStep]
    public var summary: String?
    public var warnings: [String]
    public var routeToken: String?
    public var localized: LocalizedRouteValues?
    /// الأحياء الرئيسية على المسار (اختياري — يُملأ عبر Geocoding عند توفره).
    public var neighborhoods: [String]?

    // مشتقات (تُملأ بواسطة RouteMetricsDeriver). كلها اختيارية بطبيعتها.
    public var trafficDelaySeconds: Int?
    public var slowTrafficDistanceMeters: Int?
    public var trafficJamDistanceMeters: Int?
    public var trafficJamSegmentCount: Int?
    public var turnCount: Int?
    public var uTurnCount: Int?

    // غير متاحة من Google حاليًا — تبقى nil حتى يُضاف مزوّد مرور إضافي.
    public var incidentCount: Int?
    public var severeCongestionSeconds: Int?
    public var localRoadRatio: Double?

    public init(
        id: String,
        labels: [RouteLabel] = [],
        distanceMeters: Int,
        durationSeconds: Int,
        staticDurationSeconds: Int? = nil,
        encodedPolyline: String,
        speedReadingIntervals: [SpeedReadingInterval]? = nil,
        steps: [RouteStep] = [],
        summary: String? = nil,
        warnings: [String] = [],
        routeToken: String? = nil,
        localized: LocalizedRouteValues? = nil,
        neighborhoods: [String]? = nil
    ) {
        self.id = id
        self.labels = labels
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.staticDurationSeconds = staticDurationSeconds
        self.encodedPolyline = encodedPolyline
        self.speedReadingIntervals = speedReadingIntervals
        self.steps = steps
        self.summary = summary
        self.warnings = warnings
        self.routeToken = routeToken
        self.localized = localized
        self.neighborhoods = neighborhoods
    }

    public var distanceKm: Double { Double(distanceMeters) / 1000 }
    public var durationMinutes: Int { Int((Double(durationSeconds) / 60).rounded()) }
    public var hasTrafficData: Bool { staticDurationSeconds != nil || !(speedReadingIntervals?.isEmpty ?? true) }

    /// وصف مقروء لمستوى الزحمة مشتق فقط من البيانات المتاحة.
    public var congestionLevel: CongestionLevel {
        guard hasTrafficData else { return .unknown }
        let delay = Double(trafficDelaySeconds ?? 0)
        let base = Double(staticDurationSeconds ?? durationSeconds)
        let ratio = base > 0 ? delay / base : 0
        let jamShare = Double(trafficJamDistanceMeters ?? 0) / Double(max(distanceMeters, 1))
        if ratio < 0.08 && jamShare < 0.03 { return .light }
        if ratio < 0.25 && jamShare < 0.12 { return .moderate }
        return .heavy
    }
}

public enum CongestionLevel: String, Codable, Sendable {
    case light, moderate, heavy, unknown
}

/// نتيجة اختيار الطرق الثلاثة.
public struct RouteOptions: Codable, Hashable, Sendable {
    public var noStop: RouteModel?
    public var fastest: RouteModel?
    public var shortest: RouteModel?
    public var all: [RouteModel]

    public init(noStop: RouteModel?, fastest: RouteModel?, shortest: RouteModel?, all: [RouteModel]) {
        self.noStop = noStop
        self.fastest = fastest
        self.shortest = shortest
        self.all = all
    }

    public func route(for strategy: RouteStrategy) -> RouteModel? {
        switch strategy {
        case .noStop: return noStop
        case .fastest: return fastest
        case .shortest: return shortest
        }
    }
}
