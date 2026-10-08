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
            avoidTolls: request.avoidTolls,
            maxAlternatives: 3,
            vehicleHeading: request.headingDegrees
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
    /// الخادم يحسب كل وجهة بطلب توجيه ملخّص بتزامن 4 (حد TomTom 5 طلبات/ثانية) → 10 وجهات ≈ 3 ثوانٍ.
    public var maxElementsPerRequest: Int { 10 }

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

    /// رموز TomTom العليا: 7315 مطاعم، 9376 مقاهٍ. القسم يُحدَّد بهويته (وجود cafe/coffee_shop = مقاهٍ) لا بكل أنواعه،
    /// لأن قائمة المقاهي تحوي أنواعًا مثل breakfast_restaurant لا يجوز أن تجلب المطاعم.
    static func categorySet(for includedTypes: [String]) -> [Int] {
        let cafeIdentity: Set<String> = ["cafe", "coffee_shop", "coffee_roastery", "coffee_stand", "tea_house"]
        return includedTypes.contains { cafeIdentity.contains($0) } ? [9376] : [7315]
    }

    /// يُبقي النتائج التي فئتها الأساسية (أول عنصر في categorySet، مثل 9376002) تنتمي للفئة العليا المطلوبة.
    static func belongs(_ result: TTSearchResult, to topLevel: [Int]) -> Bool {
        guard let first = result.poi?.categorySet?.first?.id else { return true }
        let prefix = Int(String(first).prefix(4)) ?? first
        return topLevel.contains(prefix)
    }

    public func searchNearby(_ r: NearbySearchRequest) async throws -> [NearbyPlace] {
        let cats = Self.categorySet(for: r.includedTypes)
        let res = try await api.ttNearby(TTNearbyRequest(
            center: TTPoint(latitude: r.center.latitude, longitude: r.center.longitude),
            radiusMeters: r.radiusMeters,
            categorySet: cats,
            limit: 100,
            languageCode: r.languageCode.hasPrefix("ar") ? "ar" : "en-GB"
        ))
        return (res.results ?? []).filter { Self.belongs($0, to: cats) }.compactMap { TomTomMappers.place($0) }
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
