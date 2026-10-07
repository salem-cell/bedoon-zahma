import Domain
import Foundation

/// أوزان «الأفضل حولي» — قابلة للتعديل عن بُعد.
public struct RankingWeights: Codable, Hashable, Sendable {
    /// m في المعادلة البايزية: عدد التقييمات الذي يوازن متوسط الفئة.
    public var confidenceThreshold: Double
    /// خصم لكل دقيقة قيادة (بوحدة التقييم). 0.02 ⇒ 10 دقائق = −0.2 نجمة.
    public var etaPenaltyPerMinute: Double
    /// مكافأة المكان المفتوح الآن.
    public var openNowBonus: Double
    /// خصم المكان المغلق الآن.
    public var closedPenalty: Double
    /// متوسط افتراضي عندما لا يمكن حساب متوسط الفئة (قائمة فارغة من التقييمات).
    public var fallbackAverageRating: Double

    public init(confidenceThreshold: Double = 500, etaPenaltyPerMinute: Double = 0.02, openNowBonus: Double = 0.1, closedPenalty: Double = 0.3, fallbackAverageRating: Double = 4.2) {
        self.confidenceThreshold = confidenceThreshold
        self.etaPenaltyPerMinute = etaPenaltyPerMinute
        self.openNowBonus = openNowBonus
        self.closedPenalty = closedPenalty
        self.fallbackAverageRating = fallbackAverageRating
    }

    public static let `default` = RankingWeights()
}

public struct PlaceRankingEngine: Sendable {
    public var weights: RankingWeights

    public init(weights: RankingWeights = .default) {
        self.weights = weights
    }

    /// WeightedRating = (v/(v+m))·R + (m/(v+m))·C
    public func bayesianRating(rating: Double?, count: Int?, categoryAverage: Double) -> Double {
        guard let r = rating, let v = count.map(Double.init), v >= 0 else { return categoryAverage - 0.5 } // بلا تقييم: تحت المتوسط
        let m = weights.confidenceThreshold
        return (v / (v + m)) * r + (m / (v + m)) * categoryAverage
    }

    public func categoryAverage(_ places: [NearbyPlace]) -> Double {
        let rated = places.compactMap(\.rating)
        guard !rated.isEmpty else { return weights.fallbackAverageRating }
        return rated.reduce(0, +) / Double(rated.count)
    }

    /// درجة «الأفضل حولي» لمكان واحد.
    public func bestScore(_ p: NearbyPlace, categoryAverage: Double) -> Double {
        var s = bayesianRating(rating: p.rating, count: p.ratingCount, categoryAverage: categoryAverage)
        if let eta = p.drivingETASeconds { s -= Double(eta) / 60 * weights.etaPenaltyPerMinute }
        if let open = p.openNow { s += open ? weights.openNowBonus : -weights.closedPenalty }
        return s
    }

    public func sorted(_ places: [NearbyPlace], by sort: PlaceSort) -> [NearbyPlace] {
        switch sort {
        case .best:
            let avg = categoryAverage(places)
            return places.sorted { bestScore($0, categoryAverage: avg) > bestScore($1, categoryAverage: avg) }
        case .rating:
            return places.sorted { ($0.rating ?? -1, $0.ratingCount ?? 0) > ($1.rating ?? -1, $1.ratingCount ?? 0) }
        case .ratingCount:
            return places.sorted { ($0.ratingCount ?? -1, $0.rating ?? 0) > ($1.ratingCount ?? -1, $1.rating ?? 0) }
        case .eta:
            return places.sorted { ($0.drivingETASeconds ?? .max, $0.distanceMeters ?? .max) < ($1.drivingETASeconds ?? .max, $1.distanceMeters ?? .max) }
        case .distance:
            return places.sorted { ($0.distanceMeters ?? .max, $0.drivingETASeconds ?? .max) < ($1.distanceMeters ?? .max, $1.drivingETASeconds ?? .max) }
        }
    }
}
