import Foundation

/// إحداثية جغرافية مستقلة عن CoreLocation حتى تبقى طبقة Domain خالية من أطر المنصة.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// مسافة الدائرة العظمى بالأمتار (Haversine).
    public func distanceMeters(to other: Coordinate) -> Double {
        let r = 6_371_000.0
        let dLat = (other.latitude - latitude).radians
        let dLng = (other.longitude - longitude).radians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude.radians) * cos(other.latitude.radians) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// تقريب الإحداثية إلى شبكة بحجم تقريبي (بالأمتار) لاستخدامها كمفتاح تخزين مؤقت.
    public func snapped(toGridMeters meters: Double) -> Coordinate {
        let latStep = meters / 111_320.0
        let lngStep = meters / (111_320.0 * max(cos(latitude.radians), 0.01))
        return Coordinate(
            latitude: (latitude / latStep).rounded() * latStep,
            longitude: (longitude / lngStep).rounded() * lngStep
        )
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
}

/// Google Encoded Polyline (precision 5) — الترميز نفسه الذي يرجعه Routes API.
public enum Polyline {
    public static func decode(_ encoded: String) -> [Coordinate] {
        var coords: [Coordinate] = []
        var index = encoded.startIndex
        var lat = 0, lng = 0
        func next() -> Int? {
            var result = 0, shift = 0, byte = 0
            repeat {
                guard index < encoded.endIndex else { return nil }
                byte = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }
        while index < encoded.endIndex {
            guard let dLat = next(), let dLng = next() else { break }
            lat += dLat
            lng += dLng
            coords.append(Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
        }
        return coords
    }

    public static func encode(_ coords: [Coordinate]) -> String {
        var out = ""
        var prevLat = 0, prevLng = 0
        func push(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                out.append(Character(UnicodeScalar((0x20 | (v & 0x1F)) + 63)!))
                v >>= 5
            }
            out.append(Character(UnicodeScalar(v + 63)!))
        }
        for c in coords {
            let lat = Int((c.latitude * 1e5).rounded()), lng = Int((c.longitude * 1e5).rounded())
            push(lat - prevLat)
            push(lng - prevLng)
            prevLat = lat
            prevLng = lng
        }
        return out
    }

    /// طول المسار التراكمي لكل نقطة (بالأمتار) — يُستخدم لتحويل فواصل السرعة إلى مسافات.
    public static func cumulativeDistances(_ coords: [Coordinate]) -> [Double] {
        guard !coords.isEmpty else { return [] }
        var out = [0.0]
        out.reserveCapacity(coords.count)
        for i in 1..<coords.count {
            out.append(out[i - 1] + coords[i - 1].distanceMeters(to: coords[i]))
        }
        return out
    }
}
