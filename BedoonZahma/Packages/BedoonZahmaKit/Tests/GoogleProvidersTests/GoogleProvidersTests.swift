import BackendClient
import Domain
@testable import GoogleProviders
import XCTest

final class GoogleProvidersTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testParseGoogleDuration() {
        XCTAssertEqual(parseGoogleDuration("1234s"), 1234)
        XCTAssertEqual(parseGoogleDuration("3.5s"), 4)
        XCTAssertNil(parseGoogleDuration(nil))
        XCTAssertNil(parseGoogleDuration("abc"))
    }

    func testComputeRoutesResponseMapsToRouteModels() throws {
        let res = try JSONDecoder().decode(GComputeRoutesResponse.self, from: fixture("computeRoutes"))
        let routes = (res.routes ?? []).enumerated().compactMap { GoogleMappers.route($0.element, index: $0.offset) }
        XCTAssertEqual(routes.count, 3)
        let main = routes[0]
        XCTAssertEqual(main.labels, [.defaultRoute])
        XCTAssertEqual(main.distanceMeters, 24_120)
        XCTAssertEqual(main.durationSeconds, 1_740)
        XCTAssertEqual(main.staticDurationSeconds, 1_440)
        XCTAssertEqual(main.routeToken, "CgAS...token")
        XCTAssertEqual(main.speedReadingIntervals?.count, 3)
        XCTAssertEqual(main.speedReadingIntervals?.first?.startPolylinePointIndex, 0, "الفهرس 0 محذوف في JSON ويُفترض صفرًا")
        XCTAssertEqual(main.speedReadingIntervals?[1].speed, .slow)
        XCTAssertEqual(main.steps.count, 2)
        XCTAssertEqual(main.steps.first?.maneuver, .depart)
        XCTAssertEqual(main.summary, "طريق الملك فهد")
        XCTAssertTrue(routes[2].labels.contains(.shorterDistance))
        XCTAssertTrue(routes[1].warnings.contains("ROUTE_RESTRICTIONS_PARTIALLY_IGNORED"))
        XCTAssertNil(routes[1].routeToken)
    }

    func testNearbySearchResponseMapsPlacesWithRoutingSummaries() throws {
        let res = try JSONDecoder().decode(GNearbySearchResponse.self, from: fixture("searchNearby"))
        let places = (res.places ?? []).enumerated().compactMap { GoogleMappers.place($0.element, routing: res.routingSummaries?[$0.offset]) }
        XCTAssertEqual(places.count, 2)
        let a = places[0]
        XCTAssertEqual(a.placeID, "ChIJ_A")
        XCTAssertEqual(a.name, "محمصة سدر")
        XCTAssertEqual(a.rating, 4.8)
        XCTAssertEqual(a.ratingCount, 8420)
        XCTAssertEqual(a.drivingETASeconds, 251)
        XCTAssertEqual(a.distanceMeters, 1_712)
        XCTAssertEqual(a.openNow, true)
        XCTAssertEqual(a.priceLevel, .moderate)
        XCTAssertEqual(a.neighborhood, "حطين")
        XCTAssertEqual(a.photos.first?.name, "places/ChIJ_A/photos/P1")
        XCTAssertEqual(a.photos.first?.authorAttributions.first?.displayName, "Salem")
        XCTAssertTrue(a.attributes.contains(.servesBreakfast))
        XCTAssertTrue(a.attributes.contains(.outdoorSeating))
        XCTAssertNil(a.menuURL)
        let b = places[1]
        XCTAssertNil(b.drivingETASeconds, "ملخص توجيه فارغ → بلا ETA (يُستكمل من Route Matrix)")
        XCTAssertNil(b.rating)
        XCTAssertTrue(b.photos.isEmpty)
    }

    func testAutocompleteMapping() throws {
        let json = """
        {"suggestions":[{"placePrediction":{"placeId":"ChIJ_X","text":{"text":"البوليفارد، حطين"},"structuredFormat":{"mainText":{"text":"البوليفارد"},"secondaryText":{"text":"حطين، الرياض"}},"distanceMeters":2400}},{"queryPrediction":{"text":{"text":"بوليفارد"}}}]}
        """.data(using: .utf8)!
        let res = try JSONDecoder().decode(GAutocompleteResponse.self, from: json)
        let s = (res.suggestions ?? []).compactMap(GoogleMappers.suggestion)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.first?.mainText, "البوليفارد")
        XCTAssertEqual(s.first?.secondaryText, "حطين، الرياض")
        XCTAssertEqual(s.first?.distanceMeters, 2400)
    }
}
