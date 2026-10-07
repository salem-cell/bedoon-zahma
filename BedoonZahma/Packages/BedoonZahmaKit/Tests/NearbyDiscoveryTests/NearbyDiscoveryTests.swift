import Domain
@testable import NearbyDiscovery
import XCTest

/// مزوّدات اختبار قابلة للضبط مع عدّاد طلبات.
final class StubPlaces: PlacesProvider, @unchecked Sendable {
    var places: [NearbyPlace]
    var calls = 0
    init(_ places: [NearbyPlace]) { self.places = places }
    func searchNearby(_ r: NearbySearchRequest) async throws -> [NearbyPlace] { calls += 1; return places }
    func autocomplete(_ r: AutocompleteRequest) async throws -> [SearchSuggestion] { [] }
    func placeDetails(placeID: String, level: PlaceDetailLevel, languageCode: String, sessionToken: String?) async throws -> NearbyPlace { places.first { $0.placeID == placeID }! }
    func photoURL(for photo: PhotoReference, maxWidthPx: Int) -> URL? { nil }
}

final class StubTravelTime: TravelTimeProvider, @unchecked Sendable {
    var etaByPlace: [String: Int] // placeID → seconds (nil = لا طريق)
    var calls = 0
    var lastBatchSize = 0
    init(_ etaByPlace: [String: Int]) { self.etaByPlace = etaByPlace }
    var maxElementsPerRequest: Int { 100 }
    func travelTimes(from origin: Coordinate, to destinations: [Coordinate], trafficAware: Bool) async throws -> [TravelTimeResult] {
        calls += 1
        lastBatchSize = destinations.count
        return destinations.enumerated().map { i, d in
            let id = "\(d.latitude)"
            if let s = etaByPlace[id] { return TravelTimeResult(destinationIndex: i, durationSeconds: s, staticDurationSeconds: s, distanceMeters: Int(origin.distanceMeters(to: d)), routeExists: true) }
            return TravelTimeResult(destinationIndex: i, durationSeconds: nil, staticDurationSeconds: nil, distanceMeters: nil, routeExists: false)
        }
    }
}

final class NearbyDiscoveryTests: XCTestCase {
    let origin = Coordinate(latitude: 24.7, longitude: 46.6)

    /// نرمّز معرّف المكان في خط العرض كي يتعرّف عليه StubTravelTime.
    private func place(_ id: String, kmAway: Double, etaSeconds: Int?, types: [String] = ["cafe"], rating: Double? = 4.5, count: Int? = 100, open: Bool? = true, status: BusinessStatus = .operational, photos: [PhotoReference] = [], attrs: Set<PlaceAttribute> = []) -> (NearbyPlace, String) {
        let lat = 24.7 + kmAway / 111.32
        let p = NearbyPlace(placeID: id, name: id, coordinate: .init(latitude: lat, longitude: 46.6), types: types, primaryType: types.first, rating: rating, ratingCount: count, photos: photos, drivingETASeconds: etaSeconds, openNow: open, businessStatus: status, attributes: attrs)
        return (p, "\(lat)")
    }

    private func pipeline(_ places: [NearbyPlace], eta: [String: Int] = [:], config: NearbySearchConfig = NearbySearchConfig(maxFanOutRequests: 1)) -> (NearbyDiscoveryPipeline, StubPlaces, StubTravelTime) {
        let sp = StubPlaces(places), st = StubTravelTime(eta)
        return (NearbyDiscoveryPipeline(places: sp, travelTime: st, config: config), sp, st)
    }

    private func query(_ f: TravelTimeFilter, sort: PlaceSort = .best, category: PlaceCategory? = nil) -> NearbyQuery {
        NearbyQuery(origin: origin, kind: PlaceKindCatalog.cafes, timeFilter: f, category: category, sort: sort, languageCode: "ar", regionCode: "SA")
    }

    func testNearButSlowPlaceIsExcludedFromFifteenMinutes() async throws {
        let (near, _) = place("near-slow", kmAway: 2, etaSeconds: 16 * 60)
        let (p, _, _) = pipeline([near])
        let r = try await p.discover(query(.fifteenMinutes))
        XCTAssertTrue(r.places.isEmpty, "2 كم لكن 16 دقيقة → لا يظهر في ≤15")
        XCTAssertEqual(r.candidates.count, 1)
    }

    func testFarButFastPlaceIsIncludedInTenMinutes() async throws {
        let (far, _) = place("far-fast", kmAway: 6, etaSeconds: 9 * 60)
        let (p, _, _) = pipeline([far])
        let r = try await p.discover(query(.tenMinutes))
        XCTAssertEqual(r.places.map(\.placeID), ["far-fast"], "6 كم لكن 9 دقائق → يظهر في ≤10")
    }

    func testFilterUsesDrivingETANotDistanceConversion() async throws {
        let (a, _) = place("a", kmAway: 1, etaSeconds: 6 * 60)
        let (b, _) = place("b", kmAway: 4, etaSeconds: 4 * 60)
        let (p, _, _) = pipeline([a, b])
        let r = try await p.discover(query(.fiveMinutes))
        XCTAssertEqual(r.places.map(\.placeID), ["b"])
    }

    func testMissingETAIsFilledFromRouteMatrixInBatches() async throws {
        let (a, ka) = place("a", kmAway: 1, etaSeconds: nil)
        let (b, kb) = place("b", kmAway: 2, etaSeconds: nil)
        let (c, _) = place("c", kmAway: 3, etaSeconds: 200)
        let (p, sp, st) = pipeline([a, b, c], eta: [ka: 240, kb: 20 * 60])
        let r = try await p.discover(query(.fifteenMinutes))
        XCTAssertEqual(sp.calls, 1)
        XCTAssertEqual(st.calls, 1, "دفعة واحدة للنواقص فقط")
        XCTAssertEqual(st.lastBatchSize, 2)
        XCTAssertEqual(Set(r.places.map(\.placeID)), ["a", "c"])
    }

    func testPlaceWithoutRouteIsNotShown() async throws {
        let (a, _) = place("island", kmAway: 1, etaSeconds: nil)
        let (p, _, _) = pipeline([a], eta: [:])
        let r = try await p.discover(query(.fifteenMinutes))
        XCTAssertTrue(r.places.isEmpty)
    }

    func testPermanentlyClosedRemovedButClosedNowKeptAndFlagged() async throws {
        let (gone, _) = place("gone", kmAway: 1, etaSeconds: 100, status: .closedPermanently)
        let (closed, _) = place("closed", kmAway: 1, etaSeconds: 100, open: false)
        let (p, _, _) = pipeline([gone, closed])
        let r = try await p.discover(query(.fifteenMinutes))
        XCTAssertEqual(r.places.map(\.placeID), ["closed"])
        XCTAssertEqual(r.places.first?.openNow, false)
    }

    func testMissingPhotosAndRatingDoNotBreakPipeline() async throws {
        let (a, _) = place("noinfo", kmAway: 1, etaSeconds: 100, rating: nil, count: nil, photos: [])
        let (p, _, _) = pipeline([a])
        let r = try await p.discover(query(.fifteenMinutes, sort: .rating))
        XCTAssertEqual(r.places.count, 1)
        XCTAssertNil(r.places.first?.coverPhoto)
        XCTAssertNil(r.places.first?.rating)
    }

    func testNoResultsYieldsEmptyWithoutError() async throws {
        let (p, _, _) = pipeline([])
        let r = try await p.discover(query(.fifteenMinutes))
        XCTAssertTrue(r.places.isEmpty)
        XCTAssertTrue(r.availableCategories.isEmpty)
    }

    func testSortsApplyAfterTimeFilter() async throws {
        let (a, _) = place("a", kmAway: 1, etaSeconds: 500, rating: 4.9, count: 10)
        let (b, _) = place("b", kmAway: 3, etaSeconds: 200, rating: 4.7, count: 9_000)
        let (c, _) = place("c", kmAway: 2, etaSeconds: 300, rating: 4.1, count: 50_000)
        let (p, _, _) = pipeline([a, b, c])
        var r = try await p.discover(query(.fifteenMinutes, sort: .rating))
        XCTAssertEqual(r.places.map(\.placeID), ["a", "b", "c"])
        r = await p.refine(query(.fifteenMinutes, sort: .ratingCount), candidates: r.candidates)
        XCTAssertEqual(r.places.map(\.placeID), ["c", "b", "a"])
        r = await p.refine(query(.fifteenMinutes, sort: .eta), candidates: r.candidates)
        XCTAssertEqual(r.places.map(\.placeID), ["b", "c", "a"])
        r = await p.refine(query(.fifteenMinutes, sort: .distance), candidates: r.candidates)
        XCTAssertEqual(r.places.map(\.placeID), ["a", "c", "b"])
        r = await p.refine(query(.fifteenMinutes, sort: .best), candidates: r.candidates)
        XCTAssertEqual(r.places.first?.placeID, "b", "الأفضل حولي = تقييم موزون")
    }

    func testRefineDoesNotIssueNewRequests() async throws {
        let (a, _) = place("a", kmAway: 1, etaSeconds: 500)
        let (p, sp, st) = pipeline([a])
        let r = try await p.discover(query(.fifteenMinutes))
        _ = await p.refine(query(.fiveMinutes), candidates: r.candidates)
        _ = try await p.discover(query(.tenMinutes)) // من الذاكرة المؤقتة
        XCTAssertEqual(sp.calls, 1)
        XCTAssertEqual(st.calls, 0)
    }

    func testCategoriesComeOnlyFromGoogleTypesAndAttributes() async throws {
        let (a, _) = place("roast", kmAway: 1, etaSeconds: 100, types: ["coffee_roastery", "cafe"])
        let (b, _) = place("bake", kmAway: 1, etaSeconds: 100, types: ["bakery"])
        let (c, _) = place("seat", kmAway: 1, etaSeconds: 100, types: ["cafe"], attrs: [.outdoorSeating])
        let (p, _, _) = pipeline([a, b, c])
        let r = try await p.discover(query(.fifteenMinutes))
        XCTAssertEqual(Set(r.availableCategories.map(\.id)), ["specialty_coffee", "bakery", "seating"])
        let onlyBakery = await p.refine(query(.fifteenMinutes, category: PlaceKindCatalog.cafes.categories.first { $0.id == "bakery" }), candidates: r.candidates)
        XCTAssertEqual(onlyBakery.places.map(\.placeID), ["bake"])
        XCTAssertFalse(PlaceKindCatalog.restaurants.categories.contains { $0.id == "saudi" }, "لا تصنيف «سعودي» لأن Google لا يوفر نوعًا موثوقًا له")
    }
}
