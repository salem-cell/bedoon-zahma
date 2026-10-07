import BackendClient
import Domain
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// RoutingProvider عبر Routes API v2 (computeRoutes) مع البدائل + أقصر مسافة + المرور على المسار + route token.
public struct GoogleRoutingProvider: RoutingProvider {
    private let api: BackendAPI
    private let regionCode: String

    public init(api: BackendAPI, regionCode: String = "SA") {
        self.api = api
        self.regionCode = regionCode
    }

    public func computeRoutes(_ request: RouteRequest) async throws -> [RouteModel] {
        let origin = GWaypoint(location: GLocation(latLng: GLatLng(latitude: request.origin.latitude, longitude: request.origin.longitude)))
        let destination: GWaypoint
        switch request.destination {
        case .place(let id, _, _): destination = GWaypoint(placeId: id)
        case .coordinate(let c, _): destination = GWaypoint(location: GLocation(latLng: GLatLng(latitude: c.latitude, longitude: c.longitude)))
        }
        let iso = request.departureTime.map { ISO8601DateFormatter().string(from: $0) }
        let body = GComputeRoutesRequest(
            origin: origin, destination: destination, languageCode: request.languageCode,
            routeModifiers: request.avoidTolls ? GRouteModifiers(avoidTolls: true) : nil,
            departureTime: iso, regionCode: regionCode
        )
        let response = try await api.computeRoutes(body)
        let routes = (response.routes ?? []).enumerated().compactMap { GoogleMappers.route($0.element, index: $0.offset) }
        guard !routes.isEmpty else { throw AppError.noRouteAvailable }
        return routes
    }
}

/// TravelTimeProvider عبر Route Matrix (computeRouteMatrix).
public struct GoogleTravelTimeProvider: TravelTimeProvider {
    private let api: BackendAPI
    public init(api: BackendAPI) { self.api = api }

    /// 100 عنصر مع TRAFFIC_AWARE_OPTIMAL (حد Google)، 625 بدون مرور.
    public var maxElementsPerRequest: Int { 100 }

    public func travelTimes(from origin: Coordinate, to destinations: [Coordinate], trafficAware: Bool) async throws -> [TravelTimeResult] {
        guard !destinations.isEmpty else { return [] }
        let body = GRouteMatrixRequest(
            origins: [GRouteMatrixWaypoint(waypoint: GWaypoint(location: GLocation(latLng: GLatLng(latitude: origin.latitude, longitude: origin.longitude))))],
            destinations: destinations.map { GRouteMatrixWaypoint(waypoint: GWaypoint(location: GLocation(latLng: GLatLng(latitude: $0.latitude, longitude: $0.longitude)))) },
            routingPreference: trafficAware ? "TRAFFIC_AWARE_OPTIMAL" : "TRAFFIC_UNAWARE",
            languageCode: nil
        )
        let elements = try await api.computeRouteMatrix(body)
        return elements.map { e in
            // destinationIndex يُحذف من JSON عندما يساوي 0 (proto3).
            let d = e.destinationIndex ?? 0
            return TravelTimeResult(
                destinationIndex: d,
                durationSeconds: parseGoogleDuration(e.duration),
                staticDurationSeconds: parseGoogleDuration(e.staticDuration),
                distanceMeters: e.distanceMeters,
                routeExists: e.condition == "ROUTE_EXISTS"
            )
        }
    }
}

/// PlacesProvider عبر Places API (New): searchNearby (+routingSummaries)، autocomplete، place details، photos.
public struct GooglePlacesProvider: PlacesProvider {
    private let api: BackendAPI
    public init(api: BackendAPI) { self.api = api }

    public func searchNearby(_ r: NearbySearchRequest) async throws -> [NearbyPlace] {
        let body = GNearbySearchRequest(
            includedTypes: r.includedTypes,
            maxResultCount: min(max(r.maxResultCount, 1), 20),
            rankPreference: r.rankByDistance ? "DISTANCE" : "POPULARITY",
            locationRestriction: GLocationRestriction(circle: GCircle(center: GLatLng(latitude: r.center.latitude, longitude: r.center.longitude), radius: min(r.radiusMeters, 50_000))),
            languageCode: r.languageCode,
            regionCode: r.regionCode,
            routingParameters: r.includeDrivingETA ? GRoutingParameters(origin: GLatLng(latitude: r.center.latitude, longitude: r.center.longitude)) : nil
        )
        let res = try await api.searchNearby(body)
        let places = res.places ?? []
        let summaries = res.routingSummaries ?? []
        return places.enumerated().compactMap { i, p in
            GoogleMappers.place(p, routing: i < summaries.count ? summaries[i] : nil)
        }
    }

    public func autocomplete(_ r: AutocompleteRequest) async throws -> [SearchSuggestion] {
        let bias = r.biasCenter.map { GLocationRestriction(circle: GCircle(center: GLatLng(latitude: $0.latitude, longitude: $0.longitude), radius: r.biasRadiusMeters)) }
        let body = GAutocompleteRequest(
            input: r.input, locationBias: bias,
            origin: r.origin.map { GLatLng(latitude: $0.latitude, longitude: $0.longitude) },
            includedRegionCodes: r.regionCodes, languageCode: r.languageCode, sessionToken: r.sessionToken
        )
        let res = try await api.autocomplete(body)
        return (res.suggestions ?? []).compactMap(GoogleMappers.suggestion)
    }

    public func placeDetails(placeID: String, level: PlaceDetailLevel, languageCode: String, sessionToken: String?) async throws -> NearbyPlace {
        let g = try await api.placeDetails(placeID: placeID, level: level.rawValue, languageCode: languageCode, sessionToken: sessionToken)
        guard let p = GoogleMappers.place(g) else { throw AppError.decoding("place \(placeID) missing required fields") }
        return p
    }

    public func photoURL(for photo: PhotoReference, maxWidthPx: Int) -> URL? {
        api.photoURL(name: photo.name, maxWidthPx: min(max(maxWidthPx, 1), 4800))
    }
}
