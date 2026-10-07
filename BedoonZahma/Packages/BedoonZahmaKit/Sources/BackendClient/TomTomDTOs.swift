import Foundation

// DTOs مطابقة لاستجابات TomTom (Routing API v1، Search API v2، POI Details) كما تمرّ عبر الخادم الخلفي.

// MARK: - Routing

public struct TTPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

public struct TTRouteSummary: Codable, Hashable, Sendable {
    public var lengthInMeters: Int?
    public var travelTimeInSeconds: Int?
    public var trafficDelayInSeconds: Int?
    public var noTrafficTravelTimeInSeconds: Int?
    public var historicTrafficTravelTimeInSeconds: Int?
    public var liveTrafficIncidentsTravelTimeInSeconds: Int?
    public var departureTime: String?
    public var arrivalTime: String?
}

public struct TTLeg: Codable, Hashable, Sendable {
    public var summary: TTRouteSummary?
    public var points: [TTPoint]?
}

public struct TTSection: Codable, Hashable, Sendable {
    public var startPointIndex: Int?
    public var endPointIndex: Int?
    public var sectionType: String?
    public var simpleCategory: String?
    public var effectiveSpeedInKmh: Int?
    public var delayInSeconds: Int?
    public var magnitudeOfDelay: Int?
}

public struct TTInstruction: Codable, Hashable, Sendable {
    public var routeOffsetInMeters: Int?
    public var travelTimeInSeconds: Int?
    public var point: TTPoint?
    public var pointIndex: Int?
    public var instructionType: String?
    public var street: String?
    public var maneuver: String?
    public var message: String?
    public var combinedMessage: String?
}

public struct TTGuidance: Codable, Hashable, Sendable {
    public var instructions: [TTInstruction]?
}

public struct TTRoute: Codable, Hashable, Sendable {
    public var summary: TTRouteSummary?
    public var legs: [TTLeg]?
    public var sections: [TTSection]?
    public var guidance: TTGuidance?
}

public struct TTRoutesResponse: Codable, Hashable, Sendable {
    public var routes: [TTRoute]?
}

/// استجابة الخادم لـ /v1/tt/routes: الطرق (الأسرع + بدائله) وطريق أقصر مسافة مرجعي.
public struct TTRoutesBundle: Codable, Hashable, Sendable {
    public var primary: TTRoutesResponse?
    public var shortest: TTRoutesResponse?
}

public struct TTRoutesRequest: Codable, Hashable, Sendable {
    public var origin: TTPoint
    public var destination: TTPoint
    public var languageCode: String
    public var avoidTolls: Bool
    public var maxAlternatives: Int
    public init(origin: TTPoint, destination: TTPoint, languageCode: String, avoidTolls: Bool, maxAlternatives: Int = 3) {
        self.origin = origin; self.destination = destination; self.languageCode = languageCode; self.avoidTolls = avoidTolls; self.maxAlternatives = maxAlternatives
    }
}

public struct TTMatrixRequest: Codable, Hashable, Sendable {
    public var origin: TTPoint
    public var destinations: [TTPoint]
    public init(origin: TTPoint, destinations: [TTPoint]) { self.origin = origin; self.destinations = destinations }
}

public struct TTMatrixCell: Codable, Hashable, Sendable {
    public var originIndex: Int?
    public var destinationIndex: Int?
    public var routeSummary: TTRouteSummary?
}

public struct TTMatrixResponse: Codable, Hashable, Sendable {
    public var data: [TTMatrixCell]?
}

// MARK: - Search

public struct TTPosition: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double
}

public struct TTCategory: Codable, Hashable, Sendable { public var id: Int? }

public struct TTClassificationName: Codable, Hashable, Sendable {
    public var nameLocale: String?
    public var name: String?
}

public struct TTClassification: Codable, Hashable, Sendable {
    public var code: String?
    public var names: [TTClassificationName]?
}

public struct TTTimeRangePoint: Codable, Hashable, Sendable {
    public var date: String?
    public var hour: Int?
    public var minute: Int?
}

public struct TTTimeRange: Codable, Hashable, Sendable {
    public var startTime: TTTimeRangePoint?
    public var endTime: TTTimeRangePoint?
}

public struct TTOpeningHours: Codable, Hashable, Sendable {
    public var mode: String?
    public var timeRanges: [TTTimeRange]?
}

public struct TTPOI: Codable, Hashable, Sendable {
    public var name: String?
    public var phone: String?
    public var url: String?
    public var categorySet: [TTCategory]?
    public var categories: [String]?
    public var classifications: [TTClassification]?
    public var openingHours: TTOpeningHours?
}

public struct TTAddress: Codable, Hashable, Sendable {
    public var streetName: String?
    public var municipalitySubdivision: String?
    public var municipality: String?
    public var freeformAddress: String?
    public var countrySubdivision: String?
}

public struct TTPoiDetailsSource: Codable, Hashable, Sendable { public var id: String? }
public struct TTDataSources: Codable, Hashable, Sendable { public var poiDetails: [TTPoiDetailsSource]? }

public struct TTSearchResult: Codable, Hashable, Sendable {
    public var type: String?
    public var id: String?
    public var dist: Double?
    public var poi: TTPOI?
    public var address: TTAddress?
    public var position: TTPosition?
    public var dataSources: TTDataSources?
}

public struct TTSearchResponse: Codable, Hashable, Sendable {
    public var results: [TTSearchResult]?
}

public struct TTNearbyRequest: Codable, Hashable, Sendable {
    public var center: TTPoint
    public var radiusMeters: Double
    public var categorySet: [Int]
    public var limit: Int
    public var languageCode: String
    public init(center: TTPoint, radiusMeters: Double, categorySet: [Int], limit: Int, languageCode: String) {
        self.center = center; self.radiusMeters = radiusMeters; self.categorySet = categorySet; self.limit = limit; self.languageCode = languageCode
    }
}

public struct TTSearchTextRequest: Codable, Hashable, Sendable {
    public var query: String
    public var center: TTPoint?
    public var radiusMeters: Double?
    public var limit: Int
    public var languageCode: String
    public var countrySet: [String]
    public init(query: String, center: TTPoint?, radiusMeters: Double?, limit: Int, languageCode: String, countrySet: [String]) {
        self.query = query; self.center = center; self.radiusMeters = radiusMeters; self.limit = limit; self.languageCode = languageCode; self.countrySet = countrySet
    }
}

// MARK: - POI Details

public struct TTRating: Codable, Hashable, Sendable {
    public var totalRatings: Int?
    public var value: Double?
    public var scale: TTScale?
}

public struct TTScale: Codable, Hashable, Sendable {
    public var min: Double?
    public var max: Double?
}

public struct TTPriceLabel: Codable, Hashable, Sendable {
    public var label: String?
    public var value: Double?
}

public struct TTScaledRange: Codable, Hashable, Sendable {
    public var scale: TTScale?
    public var start: TTPriceLabel?
    public var end: TTPriceLabel?
}

public struct TTPriceRange: Codable, Hashable, Sendable { public var scaledRange: TTScaledRange? }
public struct TTPhoto: Codable, Hashable, Sendable { public var id: String? }
public struct TTDescription: Codable, Hashable, Sendable { public var value: String?; public var language: String? }

public struct TTPoiDetailsResult: Codable, Hashable, Sendable {
    public var description: TTDescription?
    public var rating: TTRating?
    public var priceRange: TTPriceRange?
    public var photos: [TTPhoto]?
}

public struct TTPoiDetailsResponse: Codable, Hashable, Sendable {
    public var id: String?
    public var result: TTPoiDetailsResult?
}

/// استجابة /v1/tt/place/:id — المكان من Search + تفاصيل POI إن وُجدت.
public struct TTPlaceBundle: Codable, Hashable, Sendable {
    public var place: TTSearchResult?
    public var details: TTPoiDetailsResponse?
}
