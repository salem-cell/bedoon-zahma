import BackendClient
import Domain
import Foundation
import PlaceRanking
import TrafficEngine

public struct FeatureFlags: Codable, Hashable, Sendable {
    public var navigationSDKEnabled: Bool = true
    public var dynamicRerouteEnabled: Bool = true
    public var mapViewInNearbyEnabled: Bool = true
    public var photosEnabled: Bool = true
    public var atmosphereFieldsEnabled: Bool = true // حقول Enterprise + Atmosphere (تكلفة أعلى)
    public init() {}
}

/// نسخة Codable من معاملات Nearby (تُحوَّل إلى NearbySearchConfig في Features لتجنّب دورة اعتماد).
public struct NearbyConfigValues: Codable, Hashable, Sendable {
    public var prefilterRadiusMeters: [String: Double] = ["5": 5_000, "10": 9_000, "15": 14_000]
    public var maxFanOutRequests: Int = 4
    public var typesPerRequest: Int = 8
    public var maxCandidates: Int = 80
    public var cacheTTLSeconds: Int = 120
    public var preferRoutingSummaries: Bool = true
    public init() {}
}

/// كل القيم القابلة للتعديل بلا إصدار جديد (تطابق استجابة `GET /v1/config` في الخادم).
public struct AppRemoteConfig: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var trafficWeights: TrafficScoringWeights = .default
    public var rerouteThresholds: RerouteThresholds = .default
    public var rankingWeights: RankingWeights = .default
    public var nearby: NearbyConfigValues = .init()
    public var flags: FeatureFlags = .init()
    public var searchRegionCodes: [String] = ["sa"]
    /// المزوّد الذي يعلنه الخادم (tomtom/google) — للمراقبة؛ اختيار المزوّد الفعلي من إعداد البناء BZ_MAPS_PROVIDER.
    public var mapsProvider: String = "tomtom"
    public init() {}
}

/// يحمّل الإعدادات: افتراضي → نسخة مخزّنة (بياناتنا، لا بيانات Google) → تحديث من الخادم مع ETag.
public actor RemoteConfigService {
    private let api: BackendAPI?
    private let fileURL: URL
    private var current: AppRemoteConfig
    private var etag: String?
    private var lastFetch: Date?
    private let minRefreshInterval: TimeInterval = 15 * 60
    /// لقطة الإقلاع (آخر نسخة مخزّنة أو الافتراضي) — متاحة بلا await لبناء الاعتماديات.
    public nonisolated let initialConfig: AppRemoteConfig

    private struct Stored: Codable { var config: AppRemoteConfig; var etag: String? }

    public init(api: BackendAPI?, directory: URL? = nil) {
        self.api = api
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BedoonZahma", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("remote_config.json")
        var loaded = AppRemoteConfig()
        var loadedTag: String?
        if let data = try? Data(contentsOf: fileURL), let c = try? JSONDecoder().decode(Stored.self, from: data) {
            loaded = c.config
            loadedTag = c.etag
        }
        current = loaded
        etag = loadedTag
        initialConfig = loaded
    }

    public var config: AppRemoteConfig { current }

    @discardableResult
    public func refreshIfNeeded(force: Bool = false) async -> AppRemoteConfig {
        guard let api else { return current }
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < minRefreshInterval { return current }
        lastFetch = Date()
        do {
            let (data, newTag) = try await api.fetchRemoteConfig(etag: etag)
            if let data {
                let decoded = try JSONDecoder().decode(AppRemoteConfig.self, from: data)
                current = decoded
                etag = newTag
                if let out = try? JSONEncoder().encode(Stored(config: decoded, etag: newTag)) { try? out.write(to: fileURL, options: .atomic) }
            }
        } catch {
            // نبقى على آخر نسخة صالحة؛ الإعدادات ليست حرجة للتشغيل.
        }
        return current
    }
}
