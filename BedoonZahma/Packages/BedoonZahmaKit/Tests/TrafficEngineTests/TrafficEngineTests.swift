import Domain
@testable import TrafficEngine
import XCTest

final class TrafficEngineTests: XCTestCase {
    // مسار على خط عرض ثابت: كل 0.01° طول ≈ 1,000 م تقريبًا عند خط العرض 24.7.
    private func polyline(km: Double, points: Int = 11) -> String {
        let step = (km / Double(points - 1)) / (111.32 * cos(24.7 * .pi / 180))
        return Polyline.encode((0..<points).map { Coordinate(latitude: 24.7, longitude: 46.6 + Double($0) * step) })
    }

    private func route(_ id: String, km: Double, staticMin: Double, trafficMin: Double, intervals: [SpeedReadingInterval]? = nil, turns: Int = 2, uTurns: Int = 0, labels: [RouteLabel] = [], warnings: [String] = []) -> RouteModel {
        var steps = Array(repeating: RouteStep(instruction: nil, maneuver: .turnRight, distanceMeters: 500, staticDurationSeconds: 40), count: turns)
        steps += Array(repeating: RouteStep(instruction: nil, maneuver: .uturnLeft, distanceMeters: 100, staticDurationSeconds: 30), count: uTurns)
        return RouteModel(id: id, labels: labels, distanceMeters: Int(km * 1000), durationSeconds: Int(trafficMin * 60), staticDurationSeconds: Int(staticMin * 60), encodedPolyline: polyline(km: km), speedReadingIntervals: intervals, steps: steps, warnings: warnings)
    }

    private let smooth = [SpeedReadingInterval(startPolylinePointIndex: 0, endPolylinePointIndex: 10, speed: .normal)]
    private let halfJam = [SpeedReadingInterval(startPolylinePointIndex: 0, endPolylinePointIndex: 5, speed: .trafficJam), SpeedReadingInterval(startPolylinePointIndex: 5, endPolylinePointIndex: 10, speed: .normal)]
    private let mostlySlow = [SpeedReadingInterval(startPolylinePointIndex: 0, endPolylinePointIndex: 7, speed: .slow), SpeedReadingInterval(startPolylinePointIndex: 7, endPolylinePointIndex: 10, speed: .normal)]

    /// A: بعيد وانسيابي — B: الأسرع بزحمة متوسطة — C: الأقصر بزحمة شديدة.
    private var trio: [RouteModel] {
        [
            route("A", km: 34, staticMin: 35, trafficMin: 36, intervals: smooth),
            route("B", km: 24, staticMin: 24, trafficMin: 29, intervals: mostlySlow),
            route("C", km: 19, staticMin: 23, trafficMin: 34, intervals: halfJam, labels: [.shorterDistance]),
        ]
    }

    func testFastestShortestAndNoStopAreDifferentRoutes() {
        let o = RouteSelector().select(from: trio)
        XCTAssertEqual(o.fastest?.id, "B")
        XCTAssertEqual(o.shortest?.id, "C")
        XCTAssertEqual(o.noStop?.id, "A")
        XCTAssertNotEqual(o.fastest?.id, o.shortest?.id)
        XCTAssertNotEqual(o.fastest?.id, o.noStop?.id)
        XCTAssertNotEqual(o.shortest?.id, o.noStop?.id)
    }

    func testFarSmoothRouteBeatsShortJammedRouteInNoStop() {
        let o = RouteSelector().select(from: trio)
        XCTAssertEqual(o.noStop?.id, "A", "«بدون توقف» يفضّل الانسيابية حتى لو زادت المسافة والمدة قليلًا")
        XCTAssertNotEqual(o.noStop?.id, "C", "المسار القصير شديد الزحمة لا يفوز في «بدون توقف»")
    }

    func testMetricsAreDerivedFromSpeedIntervalsOnly() {
        let c = RouteMetricsDeriver.enrich(trio[2])
        XCTAssertEqual(c.trafficDelaySeconds, 11 * 60)
        XCTAssertEqual(c.trafficJamSegmentCount, 1)
        XCTAssertEqual(Double(c.trafficJamDistanceMeters ?? 0), 9_500, accuracy: 600, "نصف المسار (≈9.5 كم) اختناق")
        XCTAssertNil(c.incidentCount, "Google لا يوفر الحوادث — يبقى nil")
        XCTAssertNil(c.localRoadRatio)
        XCTAssertNil(c.severeCongestionSeconds)
    }

    func testIncidentPenaltyIsZeroWhenDataUnavailable() {
        let b = TrafficRouteScorer().score(trio[2], shortestDistanceMeters: 19_000)
        XCTAssertEqual(b.incidents, 0)
        XCTAssertGreaterThan(b.jam, 0)
        XCTAssertGreaterThan(b.delay, 0)
    }

    func testRouteWithoutTrafficDataIsPenalizedNotInvented() {
        // نفس مسافة ومدة A تقريبًا، لكن بلا بيانات مرور — الفارق الوحيد هو عقوبة غياب البيانات.
        let noData = RouteModel(id: "N", distanceMeters: 34_000, durationSeconds: 36 * 60, staticDurationSeconds: nil, encodedPolyline: polyline(km: 34), speedReadingIntervals: nil)
        let b = TrafficRouteScorer().score(noData, shortestDistanceMeters: 34_000)
        XCTAssertFalse(b.hasTrafficData)
        XCTAssertEqual(b.missingData, TrafficScoringWeights.default.missingTrafficDataPenalty)
        XCTAssertEqual(b.delay, 0)
        XCTAssertEqual(noData.congestionLevel, .unknown)
        let o = RouteSelector().select(from: [trio[0], noData])
        XCTAssertEqual(o.noStop?.id, "A", "مسار بلا بيانات لا يُفضَّل على مسار معروف الانسيابية")
    }

    func testExcessiveDetourIsExcludedFromNoStop() {
        // D: انسيابي تمامًا لكن مدته ضعف الأسرع — خارج حد الالتفاف.
        let d = route("D", km: 60, staticMin: 60, trafficMin: 60, intervals: smooth)
        let o = RouteSelector().select(from: trio + [d])
        XCTAssertNotEqual(o.noStop?.id, "D")
        XCTAssertEqual(o.noStop?.id, "A")
    }

    func testNeighborhoodRouteTurnsAndUTurnsArePenalized() {
        let direct = route("X", km: 10, staticMin: 12, trafficMin: 12, intervals: smooth, turns: 2)
        let twisty = route("Y", km: 10, staticMin: 12, trafficMin: 12, intervals: smooth, turns: 14, uTurns: 2)
        let s = TrafficRouteScorer()
        let bx = s.score(direct, shortestDistanceMeters: 10_000), by = s.score(twisty, shortestDistanceMeters: 10_000)
        XCTAssertLessThan(bx.total, by.total)
        XCTAssertEqual(by.complexity, 14 * 0.15 + 2 * 2.5, accuracy: 0.001)
        XCTAssertEqual(RouteSelector().select(from: [direct, twisty]).noStop?.id, "X")
    }

    func testWarningsAndPartiallyIgnoredRestrictionsArePenalized() {
        let clean = route("P", km: 10, staticMin: 12, trafficMin: 12, intervals: smooth)
        let flagged = route("Q", km: 10, staticMin: 12, trafficMin: 12, intervals: smooth, warnings: ["ROUTE_RESTRICTIONS_PARTIALLY_IGNORED"])
        XCTAssertEqual(RouteSelector().select(from: [flagged, clean]).noStop?.id, "P")
    }

    func testWeightsAreConfigurable() {
        // برفع عقوبة المسافة بشدة يصبح الأقصر هو «بدون توقف» رغم الزحمة.
        let heavyDistance = TrafficScoringWeights(extraDistancePerKm: 50)
        let o = RouteSelector(scorer: TrafficRouteScorer(weights: heavyDistance)).select(from: trio)
        XCTAssertEqual(o.noStop?.id, "C")
    }

    func testFastestPicksLowestTrafficAwareETAAndShortestPicksLowestDistance() {
        let o = RouteSelector().select(from: trio.shuffled())
        XCTAssertEqual(o.fastest?.durationSeconds, 29 * 60)
        XCTAssertEqual(o.shortest?.distanceMeters, 19_000)
    }

    // MARK: Reroute

    func testRerouteSuggestsCalmerAlternativeWithinLimits() {
        let current = route("cur", km: 15, staticMin: 12, trafficMin: 18, intervals: halfJam)      // 6 دقائق زحمة
        let calmer = route("alt", km: 18, staticMin: 21, trafficMin: 21, intervals: smooth)        // 0 زحمة، +3 دقائق
        let s = RerouteDecider().evaluate(current: current, alternatives: [calmer], lastSuggestionAt: nil)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.alternative.id, "alt")
        XCTAssertEqual(s?.delaySavingSeconds, 6 * 60)
        XCTAssertEqual(s?.extraDurationSeconds, 3 * 60)
    }

    func testRerouteIgnoresTrivialDifferencesAndRespectsCooldown() {
        let current = route("cur", km: 15, staticMin: 12, trafficMin: 14, intervals: mostlySlow)   // دقيقتان زحمة فقط
        let alt = route("alt", km: 16, staticMin: 13, trafficMin: 13, intervals: smooth)
        XCTAssertNil(RerouteDecider().evaluate(current: current, alternatives: [alt], lastSuggestionAt: nil), "توفير دقيقة لا يستحق اقتراحًا")

        let heavy = route("cur2", km: 15, staticMin: 12, trafficMin: 22, intervals: halfJam)
        let calm = route("alt2", km: 17, staticMin: 20, trafficMin: 20, intervals: smooth)
        XCTAssertNotNil(RerouteDecider().evaluate(current: heavy, alternatives: [calm], lastSuggestionAt: nil))
        XCTAssertNil(RerouteDecider().evaluate(current: heavy, alternatives: [calm], lastSuggestionAt: Date().addingTimeInterval(-30)), "ضمن فترة التهدئة")
    }

    func testRerouteRejectsAlternativeThatAddsTooMuchTime() {
        let current = route("cur", km: 15, staticMin: 12, trafficMin: 22, intervals: halfJam)
        let slowAlt = route("alt", km: 30, staticMin: 32, trafficMin: 32, intervals: smooth) // +10 دقائق > الحد
        XCTAssertNil(RerouteDecider().evaluate(current: current, alternatives: [slowAlt], lastSuggestionAt: nil))
    }
}
