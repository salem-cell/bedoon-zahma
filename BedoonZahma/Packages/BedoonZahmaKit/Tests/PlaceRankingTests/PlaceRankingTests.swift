import Domain
@testable import PlaceRanking
import XCTest

final class PlaceRankingTests: XCTestCase {
    private func place(_ id: String, rating: Double?, count: Int?, eta: Int? = 300, km: Double? = 2, open: Bool? = true) -> NearbyPlace {
        NearbyPlace(placeID: id, name: id, coordinate: .init(latitude: 24.7, longitude: 46.6), rating: rating, ratingCount: count, distanceMeters: km.map { Int($0 * 1000) }, drivingETASeconds: eta, openNow: open)
    }

    func testBayesianRankingPrefersManyReviewsOverFewPerfectOnes() {
        let a = place("A", rating: 5.0, count: 12)
        let b = place("B", rating: 4.8, count: 8_500)
        // فئة واقعية: متوسطها أقل من 4.8، فتقييم قليل العدد يُسحب نحو المتوسط.
        let fillers = (0..<6).map { place("F\($0)", rating: 4.0, count: 100) }
        let e = PlaceRankingEngine()
        let sorted = e.sorted([a, b] + fillers, by: .best)
        XCTAssertEqual(sorted.first?.placeID, "B", "4.8 بـ 8,500 تقييم أفضل من 5.0 بـ 12 تقييمًا")
        let avg = e.categoryAverage([a, b] + fillers)
        XCTAssertLessThan(e.bayesianRating(rating: 5.0, count: 12, categoryAverage: avg), e.bayesianRating(rating: 4.8, count: 8_500, categoryAverage: avg))
    }

    func testRatingSortIsRatingDescThenCount() {
        let s = PlaceRankingEngine().sorted([place("A", rating: 4.5, count: 10), place("B", rating: 4.9, count: 5), place("C", rating: 4.9, count: 50)], by: .rating)
        XCTAssertEqual(s.map(\.placeID), ["C", "B", "A"])
    }

    func testRatingCountSortIsCountDesc() {
        let s = PlaceRankingEngine().sorted([place("A", rating: 4.5, count: 10), place("B", rating: 4.0, count: 500), place("C", rating: 4.9, count: 50)], by: .ratingCount)
        XCTAssertEqual(s.map(\.placeID), ["B", "C", "A"])
    }

    func testETASortIsAscending() {
        let s = PlaceRankingEngine().sorted([place("A", rating: 4.5, count: 10, eta: 600), place("B", rating: 4.0, count: 5, eta: 120), place("C", rating: 4.9, count: 50, eta: 300)], by: .eta)
        XCTAssertEqual(s.map(\.placeID), ["B", "C", "A"])
    }

    func testDistanceSortIsAscending() {
        let s = PlaceRankingEngine().sorted([place("A", rating: 4.5, count: 10, km: 3.2), place("B", rating: 4.0, count: 5, km: 0.8), place("C", rating: 4.9, count: 50, km: 1.5)], by: .distance)
        XCTAssertEqual(s.map(\.placeID), ["B", "C", "A"])
    }

    func testMissingRatingGoesLastInRatingSortAndIsNotInvented() {
        let s = PlaceRankingEngine().sorted([place("A", rating: nil, count: nil), place("B", rating: 4.0, count: 5)], by: .rating)
        XCTAssertEqual(s.first?.placeID, "B")
        XCTAssertNil(s.last?.rating)
    }

    func testOpenNowAndETAInfluenceBestScoreButDoNotDominate() {
        let e = PlaceRankingEngine()
        let openNear = place("A", rating: 4.6, count: 1_000, eta: 180, open: true)
        let closedFar = place("B", rating: 4.6, count: 1_000, eta: 840, open: false)
        XCTAssertEqual(e.sorted([closedFar, openNear], by: .best).first?.placeID, "A")
        let okOpenNear = place("D", rating: 4.0, count: 1_000, eta: 180, open: true)
        let muchBetterButClosed = place("C", rating: 4.9, count: 20_000, eta: 840, open: false)
        XCTAssertEqual(e.sorted([okOpenNear, muchBetterButClosed], by: .best).first?.placeID, "C", "التقييم الموزون يبقى العامل الأساسي")
    }

    func testWeightsAreConfigurable() {
        let strict = PlaceRankingEngine(weights: RankingWeights(confidenceThreshold: 5))
        let s = strict.sorted([place("A", rating: 5.0, count: 12), place("B", rating: 4.8, count: 8_500)], by: .best)
        XCTAssertEqual(s.first?.placeID, "A", "بعتبة ثقة منخفضة يفوز التقييم الأعلى")
    }
}
