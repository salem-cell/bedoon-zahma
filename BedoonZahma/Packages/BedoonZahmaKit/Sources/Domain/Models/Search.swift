import Foundation

/// وجهة قابلة للتوجيه إليها — إما مكان Google (placeID) أو نقطة من الخريطة.
public enum Destination: Hashable, Codable, Sendable {
    case place(placeID: String, name: String, coordinate: Coordinate?)
    case coordinate(Coordinate, label: String?)

    public var displayName: String {
        switch self {
        case .place(_, let name, _): return name
        case .coordinate(_, let label): return label ?? ""
        }
    }

    public var placeID: String? {
        if case .place(let id, _, _) = self { return id }
        return nil
    }

    public var coordinate: Coordinate? {
        switch self {
        case .place(_, _, let c): return c
        case .coordinate(let c, _): return c
        }
    }
}

public struct SearchSuggestion: Identifiable, Hashable, Sendable {
    public var placeID: String
    public var mainText: String
    public var secondaryText: String?
    public var distanceMeters: Int?
    public var id: String { placeID }
    public init(placeID: String, mainText: String, secondaryText: String?, distanceMeters: Int?) {
        self.placeID = placeID
        self.mainText = mainText
        self.secondaryText = secondaryText
        self.distanceMeters = distanceMeters
    }
}

/// عنصر سجل البحث. نخزّن placeID (مسموح بتخزينه بلا حد) ونص العرض مع تاريخ انتهاء لإعادة الجلب.
public struct RecentSearch: Identifiable, Codable, Hashable, Sendable {
    public var placeID: String
    public var displayName: String
    public var secondaryText: String?
    public var searchedAt: Date
    public var id: String { placeID }
    public init(placeID: String, displayName: String, secondaryText: String?, searchedAt: Date = .init()) {
        self.placeID = placeID
        self.displayName = displayName
        self.secondaryText = secondaryText
        self.searchedAt = searchedAt
    }
}

/// المنزل/العمل — يُخزّن placeID + اسم يختاره المستخدم.
public struct SavedAddress: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case home, work }
    public var kind: Kind
    public var placeID: String
    public var label: String
    public init(kind: Kind, placeID: String, label: String) {
        self.kind = kind
        self.placeID = placeID
        self.label = label
    }
}

/// مفضلة: نخزّن المعرّف والنوع فقط؛ التفاصيل تُجلب من Google عند العرض (التزامًا بسياسات التخزين).
public struct FavoritePlace: Identifiable, Codable, Hashable, Sendable {
    public var placeID: String
    public var kindID: String
    public var savedAt: Date
    public var id: String { placeID }
    public init(placeID: String, kindID: String, savedAt: Date = .init()) {
        self.placeID = placeID
        self.kindID = kindID
        self.savedAt = savedAt
    }
}
