import Domain
import Foundation

/// مخزن JSON بسيط ومعزول (actor) في Application Support. يخزّن بيانات المستخدم فقط
/// (معرّفات أماكن، تفضيلات) — لا يخزّن محتوى Google خارج ما تسمح به السياسات.
public actor JSONFileStore<T: Codable & Sendable> {
    private let url: URL
    private var cached: T?
    private let defaultValue: T

    public init(fileName: String, defaultValue: T, directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BedoonZahma", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(fileName)
        self.defaultValue = defaultValue
    }

    public func load() -> T {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(T.self, from: data) else {
            cached = defaultValue
            return defaultValue
        }
        cached = v
        return v
    }

    public func save(_ value: T) {
        cached = value
        if let data = try? JSONEncoder().encode(value) {
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtection)
            #endif
            try? data.write(to: url, options: options)
        }
    }

    public func update(_ mutate: (inout T) -> Void) -> T {
        var v = load()
        mutate(&v)
        save(v)
        return v
    }

    public func wipe() {
        cached = defaultValue
        try? FileManager.default.removeItem(at: url)
    }
}

public actor FavoritesStore {
    private let store: JSONFileStore<[FavoritePlace]>
    public init(directory: URL? = nil) { store = JSONFileStore(fileName: "favorites.json", defaultValue: [], directory: directory) }
    public func all() async -> [FavoritePlace] { await store.load().sorted { $0.savedAt > $1.savedAt } }
    public func isFavorite(_ placeID: String) async -> Bool { await store.load().contains { $0.placeID == placeID } }
    @discardableResult
    public func toggle(placeID: String, kindID: String) async -> Bool {
        var list = await store.load()
        let nowFavorite: Bool
        if let i = list.firstIndex(where: { $0.placeID == placeID }) {
            list.remove(at: i)
            nowFavorite = false
        } else {
            list.append(FavoritePlace(placeID: placeID, kindID: kindID))
            nowFavorite = true
        }
        await store.save(list)
        return nowFavorite
    }
}

public actor RecentSearchesStore {
    private let store: JSONFileStore<[RecentSearch]>
    private let maxItems: Int
    /// نص العرض المخزّن يُعتبر منتهي الصلاحية بعد 30 يومًا ويُعاد جلبه بالـ placeID.
    public static let displayTTL: TimeInterval = 30 * 24 * 3600

    public init(maxItems: Int = 15, directory: URL? = nil) {
        self.maxItems = maxItems
        store = JSONFileStore(fileName: "recent_searches.json", defaultValue: [], directory: directory)
    }

    public func all() async -> [RecentSearch] {
        let cutoff = Date().addingTimeInterval(-Self.displayTTL)
        return await store.load().filter { $0.searchedAt > cutoff }.sorted { $0.searchedAt > $1.searchedAt }
    }

    public func add(_ item: RecentSearch) async {
        _ = await store.update { list in
            list.removeAll { $0.placeID == item.placeID }
            list.insert(item, at: 0)
            if list.count > maxItems { list = Array(list.prefix(maxItems)) }
        }
    }

    public func clear() async { await store.wipe() }
}

public actor SavedAddressesStore {
    private let store: JSONFileStore<[SavedAddress]>
    public init(directory: URL? = nil) { store = JSONFileStore(fileName: "saved_addresses.json", defaultValue: [], directory: directory) }
    public func all() async -> [SavedAddress] { await store.load() }
    public func get(_ kind: SavedAddress.Kind) async -> SavedAddress? { await store.load().first { $0.kind == kind } }
    public func set(_ address: SavedAddress) async {
        _ = await store.update { list in
            list.removeAll { $0.kind == address.kind }
            list.append(address)
        }
    }
    public func remove(_ kind: SavedAddress.Kind) async { _ = await store.update { $0.removeAll { $0.kind == kind } } }
}

public struct UserSettings: Codable, Hashable, Sendable {
    public var voiceGuidance: Bool = true
    public var avoidTolls: Bool = false
    public var analyticsEnabled: Bool = true
    public var preferredLanguage: String? = nil // nil = لغة النظام
    public init() {}
}

public actor SettingsStore {
    private let store: JSONFileStore<UserSettings>
    public init(directory: URL? = nil) { store = JSONFileStore(fileName: "settings.json", defaultValue: UserSettings(), directory: directory) }
    public func get() async -> UserSettings { await store.load() }
    public func update(_ mutate: (inout UserSettings) -> Void) async -> UserSettings { await store.update(mutate) }
}
