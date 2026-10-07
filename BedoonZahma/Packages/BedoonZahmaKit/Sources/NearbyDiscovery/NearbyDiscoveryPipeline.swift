import Domain
import Foundation
import PlaceRanking

/// معاملات البحث القريب — قابلة للتعديل عن بُعد.
public struct NearbySearchConfig: Codable, Hashable, Sendable {
    /// نصف قطر الترشيح الجغرافي الأولي لكل فلتر وقت (بالأمتار). ليس تحويلًا ثابتًا من الدقائق إلى كيلومترات،
    /// بل حد أعلى سخي لتقليل المرشّحين قبل حساب ETA الفعلي.
    public var prefilterRadiusMeters: [String: Double]
    /// عدد البحوث المتوازية (POPULARITY + DISTANCE × مجموعات أنواع) لتجاوز حد 20 نتيجة/طلب بلا ترقيم.
    public var maxFanOutRequests: Int
    public var typesPerRequest: Int
    public var maxCandidates: Int
    /// مدة بقاء النتائج في الذاكرة (ثوانٍ) — مؤقت وداخل الجلسة فقط التزامًا بسياسات Google.
    public var cacheTTLSeconds: Int
    public var cacheGridMeters: Double
    /// عند true نطلب ETA ضمن البحث نفسه (routingSummaries) ونلجأ إلى Route Matrix فقط للنواقص.
    public var preferRoutingSummaries: Bool

    public init(
        prefilterRadiusMeters: [String: Double] = ["5": 5_000, "10": 9_000, "15": 14_000],
        maxFanOutRequests: Int = 4,
        typesPerRequest: Int = 8,
        maxCandidates: Int = 80,
        cacheTTLSeconds: Int = 120,
        cacheGridMeters: Double = 150,
        preferRoutingSummaries: Bool = true
    ) {
        self.prefilterRadiusMeters = prefilterRadiusMeters
        self.maxFanOutRequests = maxFanOutRequests
        self.typesPerRequest = typesPerRequest
        self.maxCandidates = maxCandidates
        self.cacheTTLSeconds = cacheTTLSeconds
        self.cacheGridMeters = cacheGridMeters
        self.preferRoutingSummaries = preferRoutingSummaries
    }

    public static let `default` = NearbySearchConfig()

    public func radius(for filter: TravelTimeFilter) -> Double {
        prefilterRadiusMeters[String(filter.rawValue)] ?? 14_000
    }
}

public struct NearbyQuery: Hashable, Sendable {
    public var origin: Coordinate
    public var kind: PlaceKind
    public var timeFilter: TravelTimeFilter
    public var category: PlaceCategory?
    public var sort: PlaceSort
    public var languageCode: String
    public var regionCode: String

    public init(origin: Coordinate, kind: PlaceKind, timeFilter: TravelTimeFilter, category: PlaceCategory? = nil, sort: PlaceSort = .best, languageCode: String, regionCode: String) {
        self.origin = origin
        self.kind = kind
        self.timeFilter = timeFilter
        self.category = category
        self.sort = sort
        self.languageCode = languageCode
        self.regionCode = regionCode
    }
}

public struct NearbyResult: Sendable {
    /// كل المرشّحين الذين لهم ETA محسوب (قبل فلتر الوقت) — يسمح بتبديل 5/10/15 بلا طلبات جديدة.
    public var candidates: [NearbyPlace]
    /// النتيجة بعد فلتر الوقت والتصنيف والترتيب.
    public var places: [NearbyPlace]
    public var availableCategories: [PlaceCategory]
    public var fromCache: Bool
}

/// Current Location → Nearby Search (+routingSummaries) → Candidates → Geo pre-filter
/// → Route Matrix للنواقص → Driving ETA → فلتر 5/10/15 → Ranking → List.
public actor NearbyDiscoveryPipeline {
    private let places: PlacesProvider
    private let travelTime: TravelTimeProvider
    private let ranking: PlaceRankingEngine
    private let config: NearbySearchConfig
    private var cache: [String: (expires: Date, candidates: [NearbyPlace])] = [:]

    public init(places: PlacesProvider, travelTime: TravelTimeProvider, ranking: PlaceRankingEngine = .init(), config: NearbySearchConfig = .default) {
        self.places = places
        self.travelTime = travelTime
        self.ranking = ranking
        self.config = config
    }

    public func discover(_ query: NearbyQuery) async throws -> NearbyResult {
        let key = cacheKey(query)
        var fromCache = false
        let candidates: [NearbyPlace]
        if let hit = cache[key], hit.expires > Date() {
            candidates = hit.candidates
            fromCache = true
        } else {
            candidates = try await fetchCandidates(query)
            cache[key] = (Date().addingTimeInterval(Double(config.cacheTTLSeconds)), candidates)
        }
        try Task.checkCancellation()
        return finish(query, candidates: candidates, fromCache: fromCache)
    }

    /// إعادة الترتيب/الفلترة محليًا بلا طلبات جديدة (تبديل الوقت أو التصنيف أو الترتيب).
    public func refine(_ query: NearbyQuery, candidates: [NearbyPlace]) -> NearbyResult {
        finish(query, candidates: candidates, fromCache: true)
    }

    public func invalidate() { cache.removeAll() }

    // MARK: - Steps

    private func fetchCandidates(_ q: NearbyQuery) async throws -> [NearbyPlace] {
        // الخطوة 1: البحث القريب مع fan-out محدود (لا ترقيم صفحات في Nearby Search الجديد).
        let radius = config.radius(for: .fifteenMinutes) // نجلب أوسع فلتر مرة واحدة ثم نفلتر محليًا
        // نوزّع كل الأنواع على ميزانية الطلبات (نصفها POPULARITY ونصفها DISTANCE) حتى لا يُستبعد أي تصنيف. Google يقبل حتى 50 نوعًا/طلب.
        let chunkBudget = max(config.maxFanOutRequests / 2, 1)
        let perRequest = min(50, max(config.typesPerRequest, Int((Double(q.kind.includedTypes.count) / Double(chunkBudget)).rounded(.up))))
        let typeChunks = q.kind.includedTypes.chunked(perRequest)
        var requests: [NearbySearchRequest] = []
        for chunk in typeChunks {
            requests.append(NearbySearchRequest(center: q.origin, radiusMeters: radius, includedTypes: chunk, rankByDistance: false, languageCode: q.languageCode, regionCode: q.regionCode, includeDrivingETA: config.preferRoutingSummaries))
            requests.append(NearbySearchRequest(center: q.origin, radiusMeters: radius, includedTypes: chunk, rankByDistance: true, languageCode: q.languageCode, regionCode: q.regionCode, includeDrivingETA: config.preferRoutingSummaries))
        }
        requests = Array(requests.prefix(config.maxFanOutRequests))

        var merged: [String: NearbyPlace] = [:]
        try await withThrowingTaskGroup(of: [NearbyPlace].self) { group in
            for r in requests { group.addTask { try await self.places.searchNearby(r) } }
            for try await batch in group {
                for p in batch where merged[p.placeID] == nil { merged[p.placeID] = p }
            }
        }

        // الخطوة 2: ترشيح جغرافي + استبعاد المغلق نهائيًا + حساب المسافة.
        var candidates = merged.values.compactMap { p -> NearbyPlace? in
            if p.businessStatus == .closedPermanently { return nil }
            var c = p
            if c.distanceMeters == nil { c.distanceMeters = Int(q.origin.distanceMeters(to: p.coordinate)) }
            return Double(c.distanceMeters ?? 0) <= radius ? c : nil
        }
        candidates.sort { ($0.distanceMeters ?? .max) < ($1.distanceMeters ?? .max) }
        candidates = Array(candidates.prefix(config.maxCandidates))

        // الخطوة 3: ETA الفعلي للنواقص عبر Route Matrix بدفعات ≤ الحد المسموح.
        let missing = candidates.indices.filter { candidates[$0].drivingETASeconds == nil }
        if !missing.isEmpty {
            for batch in missing.chunked(travelTime.maxElementsPerRequest) {
                try Task.checkCancellation()
                let dests = batch.map { candidates[$0].coordinate }
                let results = try await travelTime.travelTimes(from: q.origin, to: dests, trafficAware: true)
                for r in results where r.routeExists {
                    let idx = batch[r.destinationIndex]
                    candidates[idx].drivingETASeconds = r.durationSeconds
                    if let d = r.distanceMeters { candidates[idx].distanceMeters = d }
                }
            }
        }
        return candidates
    }

    private func finish(_ q: NearbyQuery, candidates: [NearbyPlace], fromCache: Bool) -> NearbyResult {
        // الخطوة 4: فلتر الوقت بالـ ETA الفعلي فقط (المكان بلا ETA لا يُعرض لأننا لا نعرف إن كان يُدرَك في الوقت).
        var list = candidates.filter { ($0.drivingETASeconds ?? .max) <= q.timeFilter.seconds }
        if let cat = q.category { list = list.filter { $0.matches(cat) } }
        // الخطوة 5: الترتيب.
        list = ranking.sorted(list, by: q.sort)
        let cats = PlaceKindCatalog.availableCategories(for: q.kind, in: candidates.filter { ($0.drivingETASeconds ?? .max) <= q.timeFilter.seconds })
        return NearbyResult(candidates: candidates, places: list, availableCategories: cats, fromCache: fromCache)
    }

    private func cacheKey(_ q: NearbyQuery) -> String {
        let s = q.origin.snapped(toGridMeters: config.cacheGridMeters)
        return "\(q.kind.id)|\(s.latitude)|\(s.longitude)|\(q.languageCode)|\(q.regionCode)"
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
