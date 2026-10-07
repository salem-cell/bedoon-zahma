import Domain
import Foundation

// ⚠️ مزوّدات تطوير فقط (DEV/Simulator بلا مفاتيح). لا تُربط أبدًا في بناء Production — انظر AppContainer.
// البيانات هنا توضيحية ومُعلَّمة بوضوح؛ لا تُخلط مع بيانات Google الحقيقية.

public enum DevFixtures {
    /// الرياض — حي حطين تقريبًا.
    public static let origin = Coordinate(latitude: 24.7619, longitude: 46.6150)

    public static let cafes: [NearbyPlace] = [
        make("dev-c1", "محمصة سدر (تجريبي)", 24.7705, 46.6210, ["coffee_roastery", "cafe"], 4.8, 8420, 240, 1700, "حطين", true, .moderate, [.servesCoffee, .dineIn]),
        make("dev-c2", "كوب الصباح (تجريبي)", 24.7660, 46.6050, ["coffee_shop", "breakfast_restaurant"], 4.9, 4220, 180, 1200, "الملقا", true, .moderate, [.servesBreakfast, .servesCoffee]),
        make("dev-c3", "قهوة ١٩ (تجريبي)", 24.7540, 46.6320, ["coffee_shop"], 5.0, 12, 360, 2800, "العقيق", true, .inexpensive, [.servesCoffee]),
        make("dev-c4", "مخبز الحارة (تجريبي)", 24.7900, 46.6400, ["bakery"], 4.6, 11300, 540, 5900, "النخيل", true, .inexpensive, [.servesBreakfast]),
        make("dev-c5", "بيت الكنافة (تجريبي)", 24.8100, 46.6000, ["dessert_shop"], 4.7, 2310, 720, 7400, "الياسمين", false, .moderate, [.servesDessert]),
        make("dev-c6", "ركن الجلسات (تجريبي)", 24.8050, 46.6600, ["cafe"], 4.4, 980, 840, 9100, "الصحافة", true, .expensive, [.outdoorSeating, .dineIn]),
        make("dev-c7", "لاتيه هاوس (تجريبي)", 24.7500, 46.5900, ["coffee_shop"], 4.5, 3400, 960, 2100, "الربيع", true, .moderate, [.servesCoffee]),
    ]

    public static let restaurants: [NearbyPlace] = [
        make("dev-r1", "مشويات الديرة (تجريبي)", 24.7700, 46.6250, ["barbecue_restaurant", "restaurant"], 4.7, 15200, 300, 2400, "حطين", true, .moderate, [.dineIn, .takeout]),
        make("dev-r2", "برجر ٣٦٠ (تجريبي)", 24.7650, 46.6030, ["hamburger_restaurant"], 4.5, 9800, 240, 1900, "الملقا", true, .moderate, [.takeout]),
        make("dev-r3", "شاورما الخال (تجريبي)", 24.7520, 46.6350, ["shawarma_restaurant"], 4.8, 21000, 480, 4600, "العقيق", true, .inexpensive, [.takeout]),
        make("dev-r4", "نابولي (تجريبي)", 24.7920, 46.6380, ["pizza_restaurant", "italian_restaurant"], 4.6, 3200, 600, 6200, "النخيل", false, .expensive, [.dineIn]),
        make("dev-r5", "بحر الشرقية (تجريبي)", 24.8120, 46.6020, ["seafood_restaurant"], 4.9, 640, 780, 8800, "الياسمين", true, .expensive, [.dineIn, .reservable]),
        make("dev-r6", "مطبخ هند (تجريبي)", 24.8060, 46.6620, ["indian_restaurant"], 4.3, 5100, 900, 9900, "الصحافة", true, .moderate, [.dineIn]),
    ]

    private static func make(_ id: String, _ name: String, _ lat: Double, _ lng: Double, _ types: [String], _ rating: Double, _ count: Int, _ eta: Int, _ dist: Int, _ hood: String, _ open: Bool, _ price: PriceLevel, _ attrs: Set<PlaceAttribute>) -> NearbyPlace {
        NearbyPlace(
            placeID: id, name: name, coordinate: Coordinate(latitude: lat, longitude: lng), types: types, primaryType: types.first,
            rating: rating, ratingCount: count, photos: [], distanceMeters: dist, drivingETASeconds: eta, openNow: open,
            businessStatus: .operational, priceLevel: price, neighborhood: hood, address: "\(hood)، الرياض (عنوان تجريبي)",
            website: nil, phone: nil, googleMapsURI: nil, weekdayHours: ["السبت – الخميس: 7:00 ص – 11:30 م", "الجمعة: 1:00 م – 11:30 م"],
            attributes: attrs
        )
    }
}

public struct MockPlacesProvider: PlacesProvider {
    public var latencyMs: Int
    public init(latencyMs: Int = 250) { self.latencyMs = latencyMs }

    public func searchNearby(_ r: NearbySearchRequest) async throws -> [NearbyPlace] {
        try await Task.sleep(for: .milliseconds(latencyMs))
        let pool = r.includedTypes.contains(where: { $0.contains("restaurant") && !$0.contains("breakfast") }) ? DevFixtures.restaurants : DevFixtures.cafes
        return pool.map { p in
            var c = p
            c.distanceMeters = Int(r.center.distanceMeters(to: p.coordinate))
            if !r.includeDrivingETA { c.drivingETASeconds = nil }
            return c
        }
    }

    public func autocomplete(_ r: AutocompleteRequest) async throws -> [SearchSuggestion] {
        try await Task.sleep(for: .milliseconds(latencyMs))
        let all = [
            SearchSuggestion(placeID: "dev-boulevard", mainText: "البوليفارد", secondaryText: "بوليفارد رياض سيتي، حطين (تجريبي)", distanceMeters: 24_000),
            SearchSuggestion(placeID: "dev-boulevard-world", mainText: "بوليفارد وورلد", secondaryText: "طريق الأمير محمد بن سلمان (تجريبي)", distanceMeters: 27_000),
            SearchSuggestion(placeID: "dev-kkia", mainText: "مطار الملك خالد الدولي", secondaryText: "الرياض (تجريبي)", distanceMeters: 38_000),
            SearchSuggestion(placeID: "dev-gate", mainText: "البوابة الاقتصادية", secondaryText: "طريق الملك خالد (تجريبي)", distanceMeters: 19_000),
        ]
        let q = r.input.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.mainText.contains(q) || ($0.secondaryText ?? "").contains(q) }
    }

    public func placeDetails(placeID: String, level: PlaceDetailLevel, languageCode: String, sessionToken: String?) async throws -> NearbyPlace {
        try await Task.sleep(for: .milliseconds(latencyMs))
        if let p = (DevFixtures.cafes + DevFixtures.restaurants).first(where: { $0.placeID == placeID }) { return p }
        let coords: [String: Coordinate] = [
            "dev-boulevard": .init(latitude: 24.7640, longitude: 46.6240),
            "dev-boulevard-world": .init(latitude: 24.8360, longitude: 46.5890),
            "dev-kkia": .init(latitude: 24.9578, longitude: 46.6989),
            "dev-gate": .init(latitude: 24.8190, longitude: 46.6320),
        ]
        return NearbyPlace(placeID: placeID, name: placeID, coordinate: coords[placeID] ?? DevFixtures.origin)
    }

    public func photoURL(for photo: PhotoReference, maxWidthPx: Int) -> URL? { nil }
}

public struct MockTravelTimeProvider: TravelTimeProvider {
    public init() {}
    public var maxElementsPerRequest: Int { 100 }
    public func travelTimes(from origin: Coordinate, to destinations: [Coordinate], trafficAware: Bool) async throws -> [TravelTimeResult] {
        destinations.enumerated().map { i, d in
            let meters = origin.distanceMeters(to: d) * 1.3
            let seconds = Int(meters / 9.5) // ~34 كم/س متوسط حضري — تقدير تطويري فقط
            return TravelTimeResult(destinationIndex: i, durationSeconds: seconds, staticDurationSeconds: Int(Double(seconds) * 0.8), distanceMeters: Int(meters), routeExists: true)
        }
    }
}

public struct MockRoutingProvider: RoutingProvider {
    public init() {}

    public func computeRoutes(_ request: RouteRequest) async throws -> [RouteModel] {
        try await Task.sleep(for: .milliseconds(400))
        let o = request.origin
        let d = request.destination.coordinate ?? Coordinate(latitude: o.latitude + 0.05, longitude: o.longitude + 0.05)
        let base = o.distanceMeters(to: d) * 1.25

        func line(_ via: [Coordinate]) -> String { Polyline.encode([o] + via + [d]) }
        let midA = Coordinate(latitude: (o.latitude + d.latitude) / 2 + 0.012, longitude: (o.longitude + d.longitude) / 2 - 0.02)
        let midB = Coordinate(latitude: (o.latitude + d.latitude) / 2, longitude: (o.longitude + d.longitude) / 2)
        let midC = Coordinate(latitude: (o.latitude + d.latitude) / 2 - 0.006, longitude: (o.longitude + d.longitude) / 2 + 0.004)

        // A: أطول لكن انسيابي — B: الأسرع بزحمة متوسطة — C: الأقصر بزحمة مرتفعة.
        let a = RouteModel(id: "dev-a", labels: [.defaultRouteAlternate], distanceMeters: Int(base * 1.33), durationSeconds: Int(base / 13.9) + 60, staticDurationSeconds: Int(base / 13.9),
                           encodedPolyline: line([midA]), speedReadingIntervals: [.init(startPolylinePointIndex: 0, endPolylinePointIndex: 2, speed: .normal)],
                           steps: Array(repeating: RouteStep(instruction: "انعطف", maneuver: .turnRight, distanceMeters: 800, staticDurationSeconds: 60), count: 6),
                           summary: "النخيل ← العقيق ← حطين", routeToken: nil)
        let b = RouteModel(id: "dev-b", labels: [.defaultRoute], distanceMeters: Int(base), durationSeconds: Int(base / 13.9) + 300, staticDurationSeconds: Int(base / 13.9) - 100,
                           encodedPolyline: line([midB]), speedReadingIntervals: [.init(startPolylinePointIndex: 0, endPolylinePointIndex: 1, speed: .slow), .init(startPolylinePointIndex: 1, endPolylinePointIndex: 2, speed: .normal)],
                           steps: Array(repeating: RouteStep(instruction: "انعطف", maneuver: .turnLeft, distanceMeters: 1000, staticDurationSeconds: 70), count: 4),
                           summary: "الملقا ← حطين", routeToken: nil)
        let c = RouteModel(id: "dev-c", labels: [.shorterDistance], distanceMeters: Int(base * 0.8), durationSeconds: Int(base / 13.9) + 420, staticDurationSeconds: Int(base / 13.9) - 200,
                           encodedPolyline: line([midC]), speedReadingIntervals: [.init(startPolylinePointIndex: 0, endPolylinePointIndex: 1, speed: .trafficJam), .init(startPolylinePointIndex: 1, endPolylinePointIndex: 2, speed: .slow)],
                           steps: Array(repeating: RouteStep(instruction: "استمر", maneuver: .straight, distanceMeters: 1500, staticDurationSeconds: 90), count: 3),
                           summary: "طريق الملك فهد", routeToken: nil)
        return [b, a, c]
    }
}

public final class MockLocationProvider: LocationProviding, @unchecked Sendable {
    private var auth: LocationAuthorization
    public init(authorization: LocationAuthorization = .whenInUse) { auth = authorization }
    public var authorization: LocationAuthorization { get async { auth } }
    public func requestWhenInUseAuthorization() async -> LocationAuthorization { auth = .whenInUse; return auth }
    public func currentLocation() async throws -> Coordinate { DevFixtures.origin }
    public func locationUpdates() -> AsyncStream<Coordinate> {
        AsyncStream { c in c.yield(DevFixtures.origin); c.finish() }
    }
}

public struct NoopAnalytics: AnalyticsClient {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
}
