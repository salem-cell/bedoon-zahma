import Foundation

/// روابط خرائط Google الرسمية (Google Maps URLs) — مجانية ولا تحتاج مفتاحًا ولا فوترة.
/// تفتح تطبيق خرائط Google إن كان مثبتًا وإلا المتصفح. المرجع: developers.google.com/maps/documentation/urls
public enum GoogleMapsURLs {
    /// ملاحة بالسيارة إلى وجهة.
    public static func directions(to destination: Coordinate, label: String? = nil, from origin: Coordinate? = nil, avoidTolls: Bool = false) -> URL {
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving"),
            URLQueryItem(name: "dir_action", value: "navigate"),
        ]
        if let origin { items.append(URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)")) }
        if avoidTolls { items.append(URLQueryItem(name: "avoid", value: "tolls")) }
        c.queryItems = items
        return c.url!
    }

    /// عرض مكان بالاسم والإحداثية (بحث) في خرائط Google.
    public static func place(name: String, coordinate: Coordinate) -> URL {
        var c = URLComponents(string: "https://www.google.com/maps/search/")!
        c.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(name) \(coordinate.latitude),\(coordinate.longitude)"),
        ]
        return c.url!
    }
}
