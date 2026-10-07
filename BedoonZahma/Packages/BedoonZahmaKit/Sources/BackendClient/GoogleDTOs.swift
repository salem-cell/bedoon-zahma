import Foundation

// DTOs مطابقة لاستجابات Google Maps Platform (Routes API v2 / Places API New) كما تمرّ عبر الخادم الخلفي.
// الخادم لا يغيّر الشكل؛ يضيف المفتاح وقناع الحقول فقط.

// MARK: - Routes API

public struct GLatLng: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public struct GLocation: Codable, Hashable, Sendable {
    public var latLng: GLatLng
    public init(latLng: GLatLng) { self.latLng = latLng }
}

public struct GWaypoint: Codable, Hashable, Sendable {
    public var location: GLocation?
    public var placeId: String?
    public init(location: GLocation? = nil, placeId: String? = nil) { self.location = location; self.placeId = placeId }
}

public struct GRouteModifiers: Codable, Hashable, Sendable {
    public var avoidTolls: Bool?
    public var avoidHighways: Bool?
    public var avoidFerries: Bool?
    public init(avoidTolls: Bool? = nil, avoidHighways: Bool? = nil, avoidFerries: Bool? = nil) {
        self.avoidTolls = avoidTolls; self.avoidHighways = avoidHighways; self.avoidFerries = avoidFerries
    }
}

public struct GComputeRoutesRequest: Codable, Hashable, Sendable {
    public var origin: GWaypoint
    public var destination: GWaypoint
    public var travelMode: String = "DRIVE"
    public var routingPreference: String = "TRAFFIC_AWARE_OPTIMAL"
    public var computeAlternativeRoutes: Bool = true
    public var requestedReferenceRoutes: [String] = ["SHORTER_DISTANCE"]
    public var extraComputations: [String] = ["TRAFFIC_ON_POLYLINE"]
    public var routeModifiers: GRouteModifiers?
    public var languageCode: String
    public var units: String = "METRIC"
    public var departureTime: String?
    public var regionCode: String?

    public init(origin: GWaypoint, destination: GWaypoint, languageCode: String, routeModifiers: GRouteModifiers? = nil, departureTime: String? = nil, regionCode: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.languageCode = languageCode
        self.routeModifiers = routeModifiers
        self.departureTime = departureTime
        self.regionCode = regionCode
    }
}

public struct GLocalizedText: Codable, Hashable, Sendable { public var text: String?; public var languageCode: String? }

public struct GLocalizedValues: Codable, Hashable, Sendable {
    public var distance: GLocalizedText?
    public var duration: GLocalizedText?
    public var staticDuration: GLocalizedText?
}

public struct GPolyline: Codable, Hashable, Sendable { public var encodedPolyline: String? }

public struct GSpeedReadingInterval: Codable, Hashable, Sendable {
    public var startPolylinePointIndex: Int?
    public var endPolylinePointIndex: Int?
    public var speed: String?
}

public struct GTravelAdvisory: Codable, Hashable, Sendable {
    public var speedReadingIntervals: [GSpeedReadingInterval]?
    public var routeRestrictionsPartiallyIgnored: Bool?
}

public struct GNavigationInstruction: Codable, Hashable, Sendable {
    public var maneuver: String?
    public var instructions: String?
}

public struct GRouteStep: Codable, Hashable, Sendable {
    public var distanceMeters: Int?
    public var staticDuration: String?
    public var navigationInstruction: GNavigationInstruction?
}

public struct GRouteLeg: Codable, Hashable, Sendable {
    public var distanceMeters: Int?
    public var duration: String?
    public var staticDuration: String?
    public var steps: [GRouteStep]?
}

public struct GRoute: Codable, Hashable, Sendable {
    public var routeLabels: [String]?
    public var distanceMeters: Int?
    public var duration: String?
    public var staticDuration: String?
    public var polyline: GPolyline?
    public var description: String?
    public var warnings: [String]?
    public var legs: [GRouteLeg]?
    public var travelAdvisory: GTravelAdvisory?
    public var routeToken: String?
    public var localizedValues: GLocalizedValues?
}

public struct GComputeRoutesResponse: Codable, Hashable, Sendable {
    public var routes: [GRoute]?
}

public struct GRouteMatrixRequest: Codable, Hashable, Sendable {
    public var origins: [GRouteMatrixWaypoint]
    public var destinations: [GRouteMatrixWaypoint]
    public var travelMode: String = "DRIVE"
    public var routingPreference: String
    public var languageCode: String?
    public init(origins: [GRouteMatrixWaypoint], destinations: [GRouteMatrixWaypoint], routingPreference: String, languageCode: String?) {
        self.origins = origins; self.destinations = destinations; self.routingPreference = routingPreference; self.languageCode = languageCode
    }
}

public struct GRouteMatrixWaypoint: Codable, Hashable, Sendable {
    public var waypoint: GWaypoint
    public init(waypoint: GWaypoint) { self.waypoint = waypoint }
}

public struct GRouteMatrixElement: Codable, Hashable, Sendable {
    public var originIndex: Int?
    public var destinationIndex: Int?
    public var condition: String?
    public var distanceMeters: Int?
    public var duration: String?
    public var staticDuration: String?
}

// MARK: - Places API (New)

public struct GCircle: Codable, Hashable, Sendable {
    public var center: GLatLng
    public var radius: Double
    public init(center: GLatLng, radius: Double) { self.center = center; self.radius = radius }
}

public struct GLocationRestriction: Codable, Hashable, Sendable {
    public var circle: GCircle
    public init(circle: GCircle) { self.circle = circle }
}

public struct GRoutingParameters: Codable, Hashable, Sendable {
    public var origin: GLatLng
    public var travelMode: String = "DRIVE"
    public var routingPreference: String = "TRAFFIC_AWARE"
    public init(origin: GLatLng) { self.origin = origin }
}

public struct GNearbySearchRequest: Codable, Hashable, Sendable {
    public var includedTypes: [String]
    public var maxResultCount: Int
    public var rankPreference: String
    public var locationRestriction: GLocationRestriction
    public var languageCode: String
    public var regionCode: String
    public var routingParameters: GRoutingParameters?
    public init(includedTypes: [String], maxResultCount: Int, rankPreference: String, locationRestriction: GLocationRestriction, languageCode: String, regionCode: String, routingParameters: GRoutingParameters?) {
        self.includedTypes = includedTypes; self.maxResultCount = maxResultCount; self.rankPreference = rankPreference
        self.locationRestriction = locationRestriction; self.languageCode = languageCode; self.regionCode = regionCode
        self.routingParameters = routingParameters
    }
}

public struct GAuthorAttribution: Codable, Hashable, Sendable {
    public var displayName: String?
    public var uri: String?
    public var photoUri: String?
}

public struct GPhoto: Codable, Hashable, Sendable {
    public var name: String?
    public var widthPx: Int?
    public var heightPx: Int?
    public var authorAttributions: [GAuthorAttribution]?
}

public struct GOpeningHours: Codable, Hashable, Sendable {
    public var openNow: Bool?
    public var weekdayDescriptions: [String]?
}

public struct GAddressComponent: Codable, Hashable, Sendable {
    public var longText: String?
    public var shortText: String?
    public var types: [String]?
}

public struct GAccessibilityOptions: Codable, Hashable, Sendable {
    public var wheelchairAccessibleParking: Bool?
    public var wheelchairAccessibleEntrance: Bool?
    public var wheelchairAccessibleRestroom: Bool?
    public var wheelchairAccessibleSeating: Bool?
}

public struct GPlace: Codable, Hashable, Sendable {
    public var id: String?
    public var displayName: GLocalizedText?
    public var location: GLatLng?
    public var types: [String]?
    public var primaryType: String?
    public var rating: Double?
    public var userRatingCount: Int?
    public var photos: [GPhoto]?
    public var currentOpeningHours: GOpeningHours?
    public var regularOpeningHours: GOpeningHours?
    public var businessStatus: String?
    public var priceLevel: String?
    public var formattedAddress: String?
    public var shortFormattedAddress: String?
    public var addressComponents: [GAddressComponent]?
    public var websiteUri: String?
    public var nationalPhoneNumber: String?
    public var internationalPhoneNumber: String?
    public var googleMapsUri: String?
    public var editorialSummary: GLocalizedText?
    public var accessibilityOptions: GAccessibilityOptions?
    public var servesBreakfast: Bool?
    public var servesBrunch: Bool?
    public var servesDessert: Bool?
    public var servesCoffee: Bool?
    public var outdoorSeating: Bool?
    public var takeout: Bool?
    public var dineIn: Bool?
    public var delivery: Bool?
    public var reservable: Bool?
}

public struct GRoutingSummaryLeg: Codable, Hashable, Sendable {
    public var duration: String?
    public var distanceMeters: Int?
}

public struct GRoutingSummary: Codable, Hashable, Sendable {
    public var legs: [GRoutingSummaryLeg]?
    public var directionsUri: String?
}

public struct GNearbySearchResponse: Codable, Hashable, Sendable {
    public var places: [GPlace]?
    public var routingSummaries: [GRoutingSummary]?
}

public struct GAutocompleteRequest: Codable, Hashable, Sendable {
    public var input: String
    public var locationBias: GLocationRestriction?
    public var origin: GLatLng?
    public var includedRegionCodes: [String]
    public var languageCode: String
    public var sessionToken: String
    public init(input: String, locationBias: GLocationRestriction?, origin: GLatLng?, includedRegionCodes: [String], languageCode: String, sessionToken: String) {
        self.input = input; self.locationBias = locationBias; self.origin = origin
        self.includedRegionCodes = includedRegionCodes; self.languageCode = languageCode; self.sessionToken = sessionToken
    }
}

public struct GFormattableText: Codable, Hashable, Sendable { public var text: String? }

public struct GStructuredFormat: Codable, Hashable, Sendable {
    public var mainText: GFormattableText?
    public var secondaryText: GFormattableText?
}

public struct GPlacePrediction: Codable, Hashable, Sendable {
    public var placeId: String?
    public var text: GFormattableText?
    public var structuredFormat: GStructuredFormat?
    public var distanceMeters: Int?
}

public struct GSuggestion: Codable, Hashable, Sendable { public var placePrediction: GPlacePrediction? }

public struct GAutocompleteResponse: Codable, Hashable, Sendable { public var suggestions: [GSuggestion]? }

/// "123.5s" → 124 ثانية.
public func parseGoogleDuration(_ s: String?) -> Int? {
    guard let s, s.hasSuffix("s"), let v = Double(s.dropLast()) else { return nil }
    return Int(v.rounded())
}
