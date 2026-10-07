import Foundation

/// نوع القسم: ☕ مقاهيي / 🍽️ مطاعمي — قابل للتوسع (محطات، صيدليات…) بلا تغيير محرك Nearby.
public struct PlaceKind: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    /// أنواع Google (Table A) المُرسلة في includedTypes.
    public var includedTypes: [String]
    /// التصنيفات القابلة للاشتقاق بثقة من بيانات Google لهذا النوع.
    public var categories: [PlaceCategory]

    public init(id: String, includedTypes: [String], categories: [PlaceCategory]) {
        self.id = id
        self.includedTypes = includedTypes
        self.categories = categories
    }
}

/// تصنيف يُشتق من `types` أو حقول Atmosphere. لا نخترع تصنيفًا لا يمكن تحديده من البيانات.
public struct PlaceCategory: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    /// أنواع Google التي تُثبت هذا التصنيف.
    public var matchingTypes: Set<String>
    /// حقول منطقية (مثل servesBreakfast / outdoorSeating) التي تُثبته أيضًا.
    public var matchingAttributes: Set<PlaceAttribute>

    public init(id: String, matchingTypes: Set<String> = [], matchingAttributes: Set<PlaceAttribute> = []) {
        self.id = id
        self.matchingTypes = matchingTypes
        self.matchingAttributes = matchingAttributes
    }
}

public enum PlaceAttribute: String, Codable, Sendable, CaseIterable {
    case servesBreakfast, servesBrunch, servesDessert, servesCoffee, outdoorSeating, takeout, dineIn, delivery, reservable
}

public enum PriceLevel: String, Codable, Sendable {
    case free = "PRICE_LEVEL_FREE"
    case inexpensive = "PRICE_LEVEL_INEXPENSIVE"
    case moderate = "PRICE_LEVEL_MODERATE"
    case expensive = "PRICE_LEVEL_EXPENSIVE"
    case veryExpensive = "PRICE_LEVEL_VERY_EXPENSIVE"
    case unspecified = "PRICE_LEVEL_UNSPECIFIED"

    public var symbols: String? {
        switch self {
        case .inexpensive: return "﷼"
        case .moderate: return "﷼﷼"
        case .expensive: return "﷼﷼﷼"
        case .veryExpensive: return "﷼﷼﷼﷼"
        case .free, .unspecified: return nil
        }
    }
}

public struct PhotoReference: Codable, Hashable, Sendable {
    /// `places/{placeId}/photos/{photo}` — يُستخدم مع Place Photos (New).
    public var name: String
    public var widthPx: Int?
    public var heightPx: Int?
    public var authorAttributions: [AuthorAttribution]
    public init(name: String, widthPx: Int?, heightPx: Int?, authorAttributions: [AuthorAttribution]) {
        self.name = name
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.authorAttributions = authorAttributions
    }
}

public struct AuthorAttribution: Codable, Hashable, Sendable {
    public var displayName: String
    public var uri: String?
    public var photoUri: String?
    public init(displayName: String, uri: String?, photoUri: String?) {
        self.displayName = displayName
        self.uri = uri
        self.photoUri = photoUri
    }
}

public enum BusinessStatus: String, Codable, Sendable {
    case operational = "OPERATIONAL"
    case closedTemporarily = "CLOSED_TEMPORARILY"
    case closedPermanently = "CLOSED_PERMANENTLY"
    case unspecified = "BUSINESS_STATUS_UNSPECIFIED"
}

/// مكان قريب كما يحتاجه المنتج. الحقول الاختيارية تعكس ما توفره Google فعليًا لكل مكان.
public struct NearbyPlace: Identifiable, Codable, Hashable, Sendable {
    public var placeID: String
    public var name: String
    public var coordinate: Coordinate
    public var types: [String]
    public var primaryType: String?
    public var rating: Double?
    public var ratingCount: Int?
    public var photos: [PhotoReference]
    public var distanceMeters: Int?
    /// وقت القيادة الفعلي بالمرور الحالي (من routingSummaries أو Route Matrix). nil = لم يُحسب.
    public var drivingETASeconds: Int?
    public var openNow: Bool?
    public var businessStatus: BusinessStatus?
    public var priceLevel: PriceLevel?
    public var neighborhood: String?
    public var address: String?
    public var shortAddress: String?
    public var website: URL?
    public var phone: String?
    public var googleMapsURI: URL?
    /// لا يوفر Google بيانات منيو منظمة؛ يبقى nil إلا عند توفر مصدر رسمي.
    public var menuURL: URL?
    public var weekdayHours: [String]?
    public var attributes: Set<PlaceAttribute>
    public var accessibility: [String]
    public var editorialSummary: String?

    public var id: String { placeID }

    public init(
        placeID: String, name: String, coordinate: Coordinate, types: [String] = [], primaryType: String? = nil,
        rating: Double? = nil, ratingCount: Int? = nil, photos: [PhotoReference] = [], distanceMeters: Int? = nil,
        drivingETASeconds: Int? = nil, openNow: Bool? = nil, businessStatus: BusinessStatus? = nil,
        priceLevel: PriceLevel? = nil, neighborhood: String? = nil, address: String? = nil, shortAddress: String? = nil,
        website: URL? = nil, phone: String? = nil, googleMapsURI: URL? = nil, menuURL: URL? = nil,
        weekdayHours: [String]? = nil, attributes: Set<PlaceAttribute> = [], accessibility: [String] = [],
        editorialSummary: String? = nil
    ) {
        self.placeID = placeID; self.name = name; self.coordinate = coordinate; self.types = types
        self.primaryType = primaryType; self.rating = rating; self.ratingCount = ratingCount; self.photos = photos
        self.distanceMeters = distanceMeters; self.drivingETASeconds = drivingETASeconds; self.openNow = openNow
        self.businessStatus = businessStatus; self.priceLevel = priceLevel; self.neighborhood = neighborhood
        self.address = address; self.shortAddress = shortAddress; self.website = website; self.phone = phone
        self.googleMapsURI = googleMapsURI; self.menuURL = menuURL; self.weekdayHours = weekdayHours
        self.attributes = attributes; self.accessibility = accessibility; self.editorialSummary = editorialSummary
    }

    public var drivingETAMinutes: Int? { drivingETASeconds.map { Int((Double($0) / 60).rounded(.up)) } }
    public var distanceKm: Double? { distanceMeters.map { Double($0) / 1000 } }
    public var coverPhoto: PhotoReference? { photos.first }

    public func matches(_ category: PlaceCategory) -> Bool {
        if !category.matchingTypes.isDisjoint(with: types) { return true }
        if let p = primaryType, category.matchingTypes.contains(p) { return true }
        return !category.matchingAttributes.isDisjoint(with: attributes)
    }
}

/// فلتر الوقت: «الأماكن التي أصل إليها بالسيارة خلال X دقائق الآن».
public enum TravelTimeFilter: Int, CaseIterable, Codable, Sendable, Identifiable {
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    public var id: Int { rawValue }
    public var seconds: Int { rawValue * 60 }
}

/// ترتيب القائمة.
public enum PlaceSort: String, CaseIterable, Codable, Sendable, Identifiable {
    case best           // 🏆 الأفضل حولي (تقييم موزون)
    case rating         // ⭐ الأعلى تقييمًا (Rating DESC)
    case ratingCount    // 🔥 الأكثر تقييمًا (Count DESC)
    case eta            // ⚡ الأسرع وصولًا (ETA ASC)
    case distance       // 📍 الأقرب (Distance ASC)
    public var id: String { rawValue }
}
