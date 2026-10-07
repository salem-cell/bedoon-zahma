import Domain
import Foundation

/// تفصيل درجة الاحتكاك لمسار واحد — يُعرض في وضع التصحيح ويُستخدم في الاختبارات.
public struct TrafficFrictionBreakdown: Hashable, Sendable {
    public var routeID: String
    public var delay: Double
    public var jam: Double
    public var slow: Double
    public var stopAndGo: Double
    public var incidents: Double
    public var complexity: Double
    public var extraDistance: Double
    public var warnings: Double
    public var missingData: Double
    public var hasTrafficData: Bool

    public var total: Double { delay + jam + slow + stopAndGo + incidents + complexity + extraDistance + warnings + missingData }
}

/// TrafficFrictionScore = Σ (مقياس × وزن). الأقل يفوز في «بدون توقف».
public struct TrafficRouteScorer: Sendable {
    public var weights: TrafficScoringWeights

    public init(weights: TrafficScoringWeights = .default) {
        self.weights = weights
    }

    /// `shortestDistanceMeters`: أقصر مسافة بين المرشّحين، لحساب عقوبة المسافة النسبية.
    public func score(_ route: RouteModel, shortestDistanceMeters: Int) -> TrafficFrictionBreakdown {
        let w = weights
        let r = RouteMetricsDeriver.enrich(route)
        let delayMin = Double(r.trafficDelaySeconds ?? 0) / 60
        let jamKm = Double(r.trafficJamDistanceMeters ?? 0) / 1000
        let slowKm = Double(r.slowTrafficDistanceMeters ?? 0) / 1000
        let jamSegments = Double(r.trafficJamSegmentCount ?? 0)
        let incidents = Double(r.incidentCount ?? 0)
        let turns = Double(r.turnCount ?? 0)
        let uTurns = Double(r.uTurnCount ?? 0)
        let extraKm = max(Double(r.distanceMeters - shortestDistanceMeters), 0) / 1000

        return TrafficFrictionBreakdown(
            routeID: r.id,
            delay: delayMin * w.delayPerMinute,
            jam: jamKm * w.jamPerKm,
            slow: slowKm * w.slowPerKm,
            stopAndGo: jamSegments * w.stopAndGoPerJamSegment,
            incidents: incidents * w.incidentPenalty,
            complexity: turns * w.turnPenalty + uTurns * w.uTurnPenalty,
            extraDistance: extraKm * w.extraDistancePerKm,
            warnings: Double(r.warnings.count) * w.warningPenalty,
            missingData: r.hasTrafficData ? 0 : w.missingTrafficDataPenalty,
            hasTrafficData: r.hasTrafficData
        )
    }

    public func scoreAll(_ routes: [RouteModel]) -> [TrafficFrictionBreakdown] {
        let shortest = routes.map(\.distanceMeters).min() ?? 0
        return routes.map { score($0, shortestDistanceMeters: shortest) }
    }
}

/// يختار الطرق الثلاثة من مجموعة المرشّحين.
public struct RouteSelector: Sendable {
    public var scorer: TrafficRouteScorer

    public init(scorer: TrafficRouteScorer = .init()) {
        self.scorer = scorer
    }

    public func select(from candidates: [RouteModel]) -> RouteOptions {
        let routes = RouteMetricsDeriver.enrich(candidates)
        guard !routes.isEmpty else { return RouteOptions(noStop: nil, fastest: nil, shortest: nil, all: []) }

        // ⚡ أسرع طريق: أقل مدة بالمرور الحالي.
        let fastest = routes.min { ($0.durationSeconds, $0.distanceMeters) < ($1.durationSeconds, $1.distanceMeters) }!

        // 📏 أقصر طريق: أقل مسافة (مع تفضيل المسار المُعلَّم SHORTER_DISTANCE عند التعادل).
        let shortest = routes.min {
            if $0.distanceMeters != $1.distanceMeters { return $0.distanceMeters < $1.distanceMeters }
            return $0.labels.contains(.shorterDistance) && !$1.labels.contains(.shorterDistance)
        }!

        // 🟢 بدون توقف: أقل احتكاك ضمن حدود الالتفاف المقبولة نسبةً إلى أسرع طريق.
        let w = scorer.weights
        let eligible = routes.filter {
            Double($0.durationSeconds) <= Double(fastest.durationSeconds) * w.maxDetourDurationRatio
                && Double($0.distanceMeters) <= Double(fastest.distanceMeters) * w.maxDetourDistanceRatio
        }
        let pool = eligible.isEmpty ? routes : eligible
        let scores = scorer.scoreAll(pool)
        let noStop = zip(pool, scores).min {
            if $0.1.total != $1.1.total { return $0.1.total < $1.1.total }
            return $0.0.durationSeconds < $1.0.durationSeconds
        }!.0

        return RouteOptions(noStop: noStop, fastest: fastest, shortest: shortest, all: routes)
    }
}

/// قرار «لقينا لك طريق أهدأ» أثناء الرحلة.
public struct RerouteSuggestion: Hashable, Sendable {
    public var current: RouteModel
    public var alternative: RouteModel
    public var delaySavingSeconds: Int
    public var extraDurationSeconds: Int
}

public struct RerouteDecider: Sendable {
    public var thresholds: RerouteThresholds
    public var scorer: TrafficRouteScorer

    public init(thresholds: RerouteThresholds = .default, scorer: TrafficRouteScorer = .init()) {
        self.thresholds = thresholds
        self.scorer = scorer
    }

    /// يقارن المسار الحالي (بمدده المحدَّثة) مع البدائل الجديدة. لا يقترح تغييرًا لفروق تافهة.
    public func evaluate(current: RouteModel, alternatives: [RouteModel], lastSuggestionAt: Date?, now: Date = .init()) -> RerouteSuggestion? {
        if let last = lastSuggestionAt, now.timeIntervalSince(last) < Double(thresholds.cooldownSeconds) { return nil }
        let cur = RouteMetricsDeriver.enrich(current)
        let shortest = ([cur] + alternatives).map(\.distanceMeters).min() ?? cur.distanceMeters
        let curScore = scorer.score(cur, shortestDistanceMeters: shortest).total
        let curDelay = cur.trafficDelaySeconds ?? 0

        var best: RerouteSuggestion?
        for alt in RouteMetricsDeriver.enrich(alternatives) where alt.id != cur.id {
            let altScore = scorer.score(alt, shortestDistanceMeters: shortest).total
            let saving = curDelay - (alt.trafficDelaySeconds ?? 0)
            let extra = alt.durationSeconds - cur.durationSeconds
            guard saving >= thresholds.minDelaySavingSeconds,
                  extra <= thresholds.maxExtraDurationSeconds,
                  curScore > 0, (curScore - altScore) / curScore >= thresholds.minFrictionImprovementRatio
            else { continue }
            let candidate = RerouteSuggestion(current: cur, alternative: alt, delaySavingSeconds: saving, extraDurationSeconds: extra)
            if best == nil || saving > best!.delaySavingSeconds { best = candidate }
        }
        return best
    }
}
