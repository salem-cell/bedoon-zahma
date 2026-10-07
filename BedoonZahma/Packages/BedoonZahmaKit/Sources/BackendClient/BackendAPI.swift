import Domain
import Foundation
import Networking
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// إعدادات الاتصال بالخادم الخلفي («مشوارك أسهل» Backend) الذي يحمل مفاتيح Google الخادمية.
public struct BackendConfiguration: Sendable {
    public var baseURL: URL
    /// مفتاح تطبيق بسيط لتقييد الوصول (يُستبدل/يُعزَّز بـ App Attest لاحقًا).
    public var appKey: String
    public var appVersion: String
    public init(baseURL: URL, appKey: String, appVersion: String) {
        self.baseURL = baseURL
        self.appKey = appKey
        self.appVersion = appVersion
    }
}

/// عميل REST للخادم الخلفي. المسارات تمرّر استجابات Google كما هي.
public final class BackendAPI: Sendable {
    public let http: HTTPClient
    public let config: BackendConfiguration

    public init(http: HTTPClient, config: BackendConfiguration) {
        self.http = http
        self.config = config
    }

    private var headers: [String: String] {
        ["X-App-Key": config.appKey, "X-App-Version": config.appVersion]
    }

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var c = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        return c.url!
    }

    // MARK: Routes

    public func computeRoutes(_ body: GComputeRoutesRequest) async throws -> GComputeRoutesResponse {
        let r = try URLRequest.json(url: url("v1/routes/compute"), body: body, headers: headers)
        return try await http.json(r, endpoint: "routes.compute", as: GComputeRoutesResponse.self)
    }

    public func computeRouteMatrix(_ body: GRouteMatrixRequest) async throws -> [GRouteMatrixElement] {
        let r = try URLRequest.json(url: url("v1/routes/matrix"), body: body, headers: headers)
        return try await http.json(r, endpoint: "routes.matrix", as: [GRouteMatrixElement].self)
    }

    // MARK: Places

    public func searchNearby(_ body: GNearbySearchRequest) async throws -> GNearbySearchResponse {
        let r = try URLRequest.json(url: url("v1/places/nearby"), body: body, headers: headers)
        return try await http.json(r, endpoint: "places.nearby", as: GNearbySearchResponse.self)
    }

    public func placeDetails(placeID: String, level: String, languageCode: String, sessionToken: String?) async throws -> GPlace {
        var q = [URLQueryItem(name: "level", value: level), URLQueryItem(name: "languageCode", value: languageCode)]
        if let sessionToken { q.append(URLQueryItem(name: "sessionToken", value: sessionToken)) }
        let r = try URLRequest.json(url: url("v1/places/\(placeID)", query: q), method: "GET", headers: headers)
        return try await http.json(r, endpoint: "places.details", as: GPlace.self)
    }

    public func autocomplete(_ body: GAutocompleteRequest) async throws -> GAutocompleteResponse {
        let r = try URLRequest.json(url: url("v1/places/autocomplete"), body: body, headers: headers)
        return try await http.json(r, endpoint: "places.autocomplete", as: GAutocompleteResponse.self)
    }

    /// الخادم يستدعي Place Photos (New) بـ skipHttpRedirect ثم يعيد توجيه العميل إلى الصورة — لا تخزين.
    public func photoURL(name: String, maxWidthPx: Int) -> URL {
        url("v1/places/photo", query: [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "maxWidthPx", value: String(maxWidthPx)),
            URLQueryItem(name: "k", value: config.appKey),
        ])
    }

    // MARK: TomTom (المزوّد المجاني الافتراضي)

    public func ttRoutes(_ body: TTRoutesRequest) async throws -> TTRoutesBundle {
        let r = try URLRequest.json(url: url("v1/tt/routes"), body: body, headers: headers)
        return try await http.json(r, endpoint: "tt.routes", as: TTRoutesBundle.self)
    }

    public func ttMatrix(_ body: TTMatrixRequest) async throws -> TTMatrixResponse {
        let r = try URLRequest.json(url: url("v1/tt/matrix"), body: body, headers: headers)
        return try await http.json(r, endpoint: "tt.matrix", as: TTMatrixResponse.self)
    }

    public func ttNearby(_ body: TTNearbyRequest) async throws -> TTSearchResponse {
        let r = try URLRequest.json(url: url("v1/tt/nearby"), body: body, headers: headers)
        return try await http.json(r, endpoint: "tt.nearby", as: TTSearchResponse.self)
    }

    public func ttSearch(_ body: TTSearchTextRequest) async throws -> TTSearchResponse {
        let r = try URLRequest.json(url: url("v1/tt/search"), body: body, headers: headers)
        return try await http.json(r, endpoint: "tt.search", as: TTSearchResponse.self)
    }

    public func ttPlace(id: String, languageCode: String, withDetails: Bool) async throws -> TTPlaceBundle {
        let q = [URLQueryItem(name: "languageCode", value: languageCode), URLQueryItem(name: "details", value: withDetails ? "1" : "0")]
        let r = try URLRequest.json(url: url("v1/tt/place/\(id)", query: q), method: "GET", headers: headers)
        return try await http.json(r, endpoint: "tt.place", as: TTPlaceBundle.self)
    }

    public func ttPhotoURL(id: String, width: Int, height: Int) -> URL {
        url("v1/tt/photo", query: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "k", value: config.appKey),
        ])
    }

    // MARK: Config & Analytics

    public func fetchRemoteConfig(etag: String?) async throws -> (data: Data?, etag: String?) {
        var h = headers
        if let etag { h["If-None-Match"] = etag }
        let r = try URLRequest.json(url: url("v1/config"), method: "GET", headers: h)
        let (data, http) = try await self.http.send(r, endpoint: "config")
        if http.statusCode == 304 { return (nil, etag) }
        return (data, http.value(forHTTPHeaderField: "ETag"))
    }

    public func sendAnalytics(_ events: [AnalyticsEvent]) async throws {
        struct Body: Encodable { let events: [AnalyticsEvent] }
        let r = try URLRequest.json(url: url("v1/analytics/events"), body: Body(events: events), headers: headers)
        _ = try await http.send(r, endpoint: "analytics")
    }
}
