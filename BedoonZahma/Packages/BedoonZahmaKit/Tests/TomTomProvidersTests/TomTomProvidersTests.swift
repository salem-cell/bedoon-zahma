import BackendClient
import Domain
@testable import TomTomProviders
import TrafficEngine
import XCTest

final class TomTomProvidersTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testRoutesBundleMapsPrimaryAlternativesAndShortest() throws {
        let bundle = try JSONDecoder().decode(TTRoutesBundle.self, from: fixture("ttRoutes"))
        let routes = TomTomMappers.routes(bundle)
        XCTAssertEqual(routes.count, 3)

        let main = routes[0]
        XCTAssertEqual(main.labels, [.defaultRoute])
        XCTAssertEqual(main.distanceMeters, 24_120)
        XCTAssertEqual(main.durationSeconds, 1_740)
        XCTAssertEqual(main.staticDurationSeconds, 1_440)
        XCTAssertEqual(main.speedReadingIntervals?.count, 2, "أقسام TRAFFIC فقط تتحول إلى فواصل")
        XCTAssertEqual(main.speedReadingIntervals?[0].speed, .trafficJam, "magnitude 3 / 12 كم/س = اختناق")
        XCTAssertEqual(main.speedReadingIntervals?[1].speed, .slow)
        XCTAssertEqual(main.incidentCount, 1, "ROAD_WORK حادث فعلي؛ JAM ليس حادثًا")
        XCTAssertEqual(main.steps.count, 4)
        XCTAssertEqual(main.steps[0].maneuver, .depart)
        XCTAssertEqual(main.steps[1].maneuver, .turnRight)
        XCTAssertEqual(main.steps[1].distanceMeters, 18_500)
        XCTAssertEqual(main.steps[1].routeOffsetMeters, 1_500)
        XCTAssertEqual(main.steps[2].maneuver, .turnSlightLeft)
        XCTAssertNil(main.steps[3].maneuver, "ARRIVE لا تُعدّ مناورة")
        XCTAssertEqual(main.summary, "طريق الملك فهد ← طريق الأمير تركي")
        XCTAssertTrue(Polyline.decode(main.encodedPolyline).count == 5)

        XCTAssertEqual(routes[1].labels, [.defaultRouteAlternate])
        XCTAssertEqual(routes[2].labels, [.shorterDistance])
        XCTAssertEqual(routes[2].distanceMeters, 19_000)
    }

    func testSelectorPicksCalmAlternativeAsNoStopFromTomTomData() throws {
        let bundle = try JSONDecoder().decode(TTRoutesBundle.self, from: fixture("ttRoutes"))
        let options = RouteSelector().select(from: TomTomMappers.routes(bundle))
        XCTAssertEqual(options.fastest?.distanceMeters, 24_120)
        XCTAssertEqual(options.shortest?.distanceMeters, 19_000)
        XCTAssertEqual(options.noStop?.distanceMeters, 32_000, "الأبعد لكنه الأهدأ (تأخير دقيقة، بلا أقسام زحمة)")
    }

    func testManeuverMappingCoversTomTomCodes() {
        XCTAssertEqual(TomTomMappers.maneuver("SHARP_LEFT"), .turnSharpLeft)
        XCTAssertEqual(TomTomMappers.maneuver("KEEP_RIGHT"), .forkRight)
        XCTAssertEqual(TomTomMappers.maneuver("MAKE_UTURN"), .uturnLeft)
        XCTAssertEqual(TomTomMappers.maneuver("ROUNDABOUT_CROSS"), .roundaboutRight)
        XCTAssertEqual(TomTomMappers.maneuver("ENTER_MOTORWAY"), .rampRight)
        XCTAssertEqual(TomTomMappers.maneuver("FOLLOW"), .straight)
        XCTAssertNil(TomTomMappers.maneuver("ARRIVE_LEFT"))
        XCTAssertNil(TomTomMappers.maneuver(nil))
    }

    func testNearbyMapsPlacesTypesHoursAndAddress() throws {
        let res = try JSONDecoder().decode(TTSearchResponse.self, from: fixture("ttNearby"))
        let places = (res.results ?? []).compactMap { TomTomMappers.place($0) }
        XCTAssertEqual(places.count, 2)
        let a = places[0]
        XCTAssertEqual(a.placeID, "tt-poi-1")
        XCTAssertEqual(a.name, "محمصة سدر")
        XCTAssertEqual(a.types, ["coffee_shop", "cafe"])
        XCTAssertEqual(a.primaryType, "coffee_shop")
        XCTAssertEqual(a.neighborhood, "حطين")
        XCTAssertEqual(a.distanceMeters, 1_712)
        XCTAssertEqual(a.openNow, true)
        XCTAssertEqual(a.website?.absoluteString, "https://sidr.coffee")
        XCTAssertNil(a.rating, "التقييم يأتي من POI Details فقط — لا نخترعه")
        XCTAssertNil(a.drivingETASeconds, "ETA يُحسب لاحقًا عبر TravelTimeProvider")
        let b = places[1]
        XCTAssertEqual(b.types, ["restaurant", "middle_eastern_restaurant"])
        XCTAssertNil(b.openNow, "بلا ساعات عمل → غير معروف")
        XCTAssertTrue(b.photos.isEmpty)
    }

    func testPlaceDetailsMergeRatingPriceAndPhotos() throws {
        let res = try JSONDecoder().decode(TTSearchResponse.self, from: fixture("ttNearby"))
        let details = try JSONDecoder().decode(TTPoiDetailsResponse.self, from: """
        {"id":"pd-1","result":{"description":{"value":"قهوة مختصة","language":"ar"},"rating":{"scale":{"min":0,"max":5},"totalRatings":8420,"value":4.8},"priceRange":{"scaledRange":{"scale":{"min":1,"max":4},"start":{"label":"$$","value":2},"end":{"label":"$$","value":2}}},"photos":[{"id":"ph1"},{"id":"ph2"}]}}
        """.data(using: .utf8)!)
        let p = try XCTUnwrap(TomTomMappers.place(res.results![0], details: details))
        XCTAssertEqual(p.rating, 4.8)
        XCTAssertEqual(p.ratingCount, 8420)
        XCTAssertEqual(p.priceLevel, .moderate)
        XCTAssertEqual(p.photos.map(\.name), ["tt:ph1", "tt:ph2"])
        XCTAssertEqual(p.editorialSummary, "قهوة مختصة")
    }

    func testSuggestionCarriesCoordinate() throws {
        let res = try JSONDecoder().decode(TTSearchResponse.self, from: fixture("ttNearby"))
        let s = try XCTUnwrap(TomTomMappers.suggestion(res.results![0]))
        XCTAssertEqual(s.mainText, "محمصة سدر")
        XCTAssertEqual(s.coordinate?.latitude, 24.7705)
        XCTAssertEqual(s.distanceMeters, 1_712)
    }

    func testCategorySetSelection() {
        XCTAssertEqual(TomTomPlacesProvider.categorySet(for: ["cafe", "coffee_shop", "bakery"]), [9376])
        XCTAssertEqual(TomTomPlacesProvider.categorySet(for: ["restaurant", "pizza_restaurant"]), [7315])
        XCTAssertEqual(TomTomPlacesProvider.categorySet(for: ["cafe", "restaurant"]), [9376, 7315])
    }
}
