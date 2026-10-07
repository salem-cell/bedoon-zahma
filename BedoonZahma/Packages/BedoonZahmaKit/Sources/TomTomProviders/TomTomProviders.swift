import BackendClient
import Domain
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// RoutingProvider عبر TomTom Routing API (مرور حي، بدائل، أقصر مسافة، إرشادات بالعربية).
public struct TomTomRoutingProvider: RoutingProvider {
    private let api: BackendAPI
    public init(api: BackendAPI) { self.api = api }

    public func computeRoutes(_ request: RouteRequest) async throws -> [RouteModel] {
        guard let dest = request.destination.coordinate else { throw AppError.noRouteAvailable }
        let body = TTRoutesRequest(
            origin: TTPoint(latitude: request.origin.latitude, longitude: request.origin.longitude),
            destination: TTPoint(latitude: dest.latitude, longitude: dest.longitude),
            languageCode: request.languageCode.hasPrefix("ar") ? "ar" : "en-GB",
            avoidTolls: request.avoidTolls
        )
        let bundle = try await api.ttRoutes(body)
        let routes = TomTomMappers.routes(bundle)
        guard !routes.isEmpty else { throw AppError.noRouteAvailable }
        return routes
    }
}

/// TravelTimeProvider عبر الخادم: Matrix Routing v2 أو حسابات طرق فردية حسب إعداد الخادم (الخطة المجانية).
public struct TomTomTravelTimeProvider: TravelTimeProvider {
    private let api: BackendAPI
    public init(api: BackendAPI) { self.api = api }
    public var maxElementsPerRequest: Int { 25 }

    public func travelTimes(from origin: Coordinate, to destinations: [Coordinate], trafficAware: Bool) async throws -> [TravelTimeResult] {
        guard !destinations.isEmpty else { return [] }
        let res = try await api.ttMatrix(TTMatrixRequest(origin: TTPoint(latitude: origin.latitude, longitude: origin.longitude), destinations: destinations.map { TTPoint(latitude: $0.latitude, longitude: $0.longitude) }))
        return (res.data ?? []).map { c in
            let s = c.routeSummary
            return TravelTimeResult(
                destinationIndex: c.destinationIndex ?? 0,
                durationSeconds: s?.travelTimeInSeconds,
                staticDurationSeconds: (s?.travelTimeInSeconds).flatMap { t in (s?.trafficDelayInSeconds).map { t - $0 } },
                distanceMeters: s?.lengthInMeters,
                routeExists: s?.travelTimeInSeconds != nil
            )
        }
    }
}

/// PlacesProvider عبر TomTom Search API (بحث قريب، بحث نصي بإحداثيات، تفاصيل POI بتقييم وصور).
public struct TomTomPlacesProvider: PlacesProvider {
    private let api: BackendAPI
    public init(api: BackendAPI) { self.api = api }

    /// رموز TomTom العليا: 7315 مطاعم، 9376 مقاهٍ. التصنيف الدقيق يُشتق من أسماء التصنيفات في النتيجة.
    static func categorySet(for includedTypes: [String]) -> [Int] {
        let cafeLike: Set<String> = ["cafe", "coffee_shop", "coffee_roastery", "coffee_stand", "tea_house", "bakery", "pastry_shop", "cake_shop", "dessert_shop", "dessert_restaurant", "ice_cream_shop", "juice_shop"]
        let wantsCafes = includedTypes.contains { cafeLike.contains($0) }
        let wantsRestaurants = includedTypes.contains { $0.hasSuffix("restaurant") || $0 == "steak_house" }
        var set: [Int] = []
        if wantsCafes { set.append(9376) }
        if wantsRestaurants || set.isEmpty { set.append(7315) }
        return set
    }

    public func searchNearby(_ r: NearbySearchRequest) async throws -> [NearbyPlace] {
        let res = try await api.ttNearby(TTNearbyRequest(
            center: TTPoint(latitude: r.center.latitude, longitude: r.center.longitude),
            radiusMeters: r.radiusMeters,
            categorySet: Self.categorySet(for: r.includedTypes),
            limit: 100,
            languageCode: r.languageCode.hasPrefix("ar") ? "ar" : "en-GB"
        ))
        return (res.results ?? []).compactMap { TomTomMappers.place($0) }
    }

    public func autocomplete(_ r: AutocompleteRequest) async throws -> [SearchSuggestion] {
        let res = try await api.ttSearch(TTSearchTextRequest(
            query: r.input,
            center: r.biasCenter.map { TTPoint(latitude: $0.latitude, longitude: $0.longitude) },
            radiusMeters: r.biasCenter == nil ? nil : r.biasRadiusMeters,
            limit: 7,
            languageCode: r.languageCode.hasPrefix("ar") ? "ar" : "en-GB",
            countrySet: r.regionCodes.map { $0.uppercased() }
        ))
        return (res.results ?? []).compactMap(TomTomMappers.suggestion)
    }

    public func placeDetails(placeID: String, level: PlaceDetailLevel, languageCode: String, sessionToken: String?) async throws -> NearbyPlace {
        let bundle = try await api.ttPlace(id: placeID, languageCode: languageCode.hasPrefix("ar") ? "ar" : "en-GB", withDetails: level != .basic)
        guard let p = bundle.place, let place = TomTomMappers.place(p, details: bundle.details) else { throw AppError.decoding("tt place \(placeID) missing fields") }
        return place
    }

    public func photoURL(for photo: PhotoReference, maxWidthPx: Int) -> URL? {
        guard photo.name.hasPrefix("tt:") else { return nil }
        let w = min(max(maxWidthPx, 100), 1200)
        return api.ttPhotoURL(id: String(photo.name.dropFirst(3)), width: w, height: Int(Double(w) * 0.66))
    }
}
