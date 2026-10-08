import BackendClient
import Domain
@testable import TomTomProviders
import TrafficEngine
import XCTest

/// اختبارات على استجابة حقيقية من TomTom (حطين → مطار الملك خالد، 2026‑10‑08) محفوظة كـ fixture.
final class TomTomRealDataTests: XCTestCase {
    private func load() throws -> TTRoutesBundle {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ttRoutesReal", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(TTRoutesBundle.self, from: try Data(contentsOf: url))
    }

    func testRealResponseMapsAllRoutesWithArabicInstructions() throws {
        let routes = TomTomMappers.routes(try load())
        XCTAssertEqual(routes.count, 5, "4 طرق أساسية/بديلة + أقصر مسافة")
        for r in routes {
            XCTAssertGreaterThan(r.distanceMeters, 30_000)
            XCTAssertGreaterThan(r.durationSeconds, 1_000)
            XCTAssertNotNil(r.staticDurationSeconds)
            XCTAssertGreaterThan(Polyline.decode(r.encodedPolyline).count, 300)
            XCTAssertFalse(r.steps.isEmpty)
            XCTAssertTrue(r.steps.allSatisfy { ($0.instruction ?? "").isEmpty == false || $0.maneuver == nil })
            XCTAssertTrue(r.steps.contains { $0.instruction?.contains("المنعطف") == true || $0.instruction?.contains("اتجه") == true }, "تعليمات بالعربية")
            // مواضع المناورات متزايدة على طول المسار (شرط الإرشاد الذاتي)
            let offsets = r.steps.compactMap(\.routeOffsetMeters)
            XCTAssertEqual(offsets, offsets.sorted())
            XCTAssertEqual(offsets.last, r.distanceMeters, "آخر تعليمة (الوصول) عند نهاية المسار")
        }
    }

    func testSelectorProducesThreeStrategiesOnRealData() throws {
        let options = RouteSelector().select(from: TomTomMappers.routes(try load()))
        XCTAssertNotNil(options.fastest)
        XCTAssertNotNil(options.shortest)
        XCTAssertNotNil(options.noStop)
        XCTAssertEqual(options.fastest?.durationSeconds, options.all.map(\.durationSeconds).min())
        XCTAssertEqual(options.shortest?.distanceMeters, options.all.map(\.distanceMeters).min())
        // بلا زحمة ليلًا، «بدون توقف» يجب ألا يختار طريقًا أطول بلا سبب: يساوي الأسرع أو يقاربه
        if let ns = options.noStop, let f = options.fastest {
            XCTAssertLessThanOrEqual(Double(ns.durationSeconds), Double(f.durationSeconds) * 1.35)
        }
    }

    func testStepDistancesSumToRouteLength() throws {
        for r in TomTomMappers.routes(try load()) {
            let sum = r.steps.map(\.distanceMeters).reduce(0, +)
            XCTAssertEqual(sum, r.distanceMeters, accuracy: 1)
        }
    }
}
