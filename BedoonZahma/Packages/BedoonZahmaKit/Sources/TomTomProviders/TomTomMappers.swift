import BackendClient
import Domain
import Foundation

/// تحويل استجابات TomTom إلى نماذج Domain. أي حقل غير متاح يبقى nil.
public enum TomTomMappers {
    // MARK: Routes

    /// `shorterDistance` يُعلَّم الطرق القادمة من طلب routeType=shortest.
    public static func route(_ r: TTRoute, index: Int, labels: [RouteLabel]) -> RouteModel? {
        guard let s = r.summary, let length = s.lengthInMeters, let travel = s.travelTimeInSeconds else { return nil }
        let points = (r.legs ?? []).flatMap { $0.points ?? [] }.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        guard points.count >= 2 else { return nil }
        let encoded = Polyline.encode(points)

        // أقسام المرور → فواصل سرعة. magnitudeOfDelay: 0 مجهول، 1 بسيط، 2 متوسط، 3 كبير، 4 غير محدد.
        var intervals: [SpeedReadingInterval] = []
        var incidents = 0
        for sec in (r.sections ?? []) where sec.sectionType?.uppercased() == "TRAFFIC" {
            guard let a = sec.startPointIndex, let b = sec.endPointIndex, b > a else { continue }
            // magnitudeOfDelay: 0 مجهول، 1 بسيط، 2 متوسط، 3 كبير، 4 غير محدد (نعتمد السرعة الفعلية عندها).
            let magnitude = sec.magnitudeOfDelay ?? 0
            let speed = sec.effectiveSpeedInKmh ?? 999
            let isJam = magnitude == 3 || speed <= 15 || sec.simpleCategory == "ROAD_CLOSURE"
            // قسم «أعمال طرق» بسرعة طبيعية (≥ 50 كم/س) ودرجة غير محددة لا يُعدّ بطئًا، لكنه يبقى حادثًا.
            let isSlow = !isJam && !(magnitude == 4 && speed >= 50) && !(magnitude == 0 && speed >= 50)
            if isJam || isSlow {
                intervals.append(SpeedReadingInterval(startPolylinePointIndex: a, endPolylinePointIndex: b, speed: isJam ? .trafficJam : .slow))
            }
            if let cat = sec.simpleCategory, cat != "JAM" { incidents += 1 } // ROAD_WORK / ROAD_CLOSURE / OTHER = حوادث فعلية
        }

        let instr = r.guidance?.instructions ?? []
        var steps: [RouteStep] = []
        for (i, ins) in instr.enumerated() {
            let next = i + 1 < instr.count ? (instr[i + 1].routeOffsetInMeters ?? length) : length
            let dist = max(next - (ins.routeOffsetInMeters ?? 0), 0)
            let nextTime = i + 1 < instr.count ? (instr[i + 1].travelTimeInSeconds ?? travel) : travel
            steps.append(RouteStep(
                instruction: ins.message ?? ins.combinedMessage,
                maneuver: maneuver(ins.maneuver),
                distanceMeters: dist,
                staticDurationSeconds: max(nextTime - (ins.travelTimeInSeconds ?? 0), 0),
                routeOffsetMeters: ins.routeOffsetInMeters,
                pointIndex: ins.pointIndex,
                coordinate: ins.point.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) },
                streetName: ins.street
            ))
        }

        // ملخص الطريق: أطول شارعين على المسار (TomTom لا يعطي وصفًا جاهزًا).
        var streetLen: [String: Int] = [:]
        for st in steps { if let n = st.streetName, !n.isEmpty { streetLen[n, default: 0] += st.distanceMeters } }
        let summary = streetLen.sorted { $0.value > $1.value }.prefix(2).map(\.key).joined(separator: " ← ")

        var m = RouteModel(
            id: "tt-\(labels.contains(.shorterDistance) ? "s" : "p")\(index)-\(encoded.hashValue)",
            labels: labels,
            distanceMeters: length,
            durationSeconds: travel,
            staticDurationSeconds: s.noTrafficTravelTimeInSeconds ?? (s.trafficDelayInSeconds.map { travel - $0 }),
            encodedPolyline: encoded,
            speedReadingIntervals: intervals.isEmpty && s.trafficDelayInSeconds == nil ? nil : intervals,
            steps: steps,
            summary: summary.isEmpty ? nil : summary,
            warnings: [],
            routeToken: nil,
            localized: nil
        )
        m.incidentCount = incidents
        return m
    }

    public static func routes(_ bundle: TTRoutesBundle) -> [RouteModel] {
        var out: [RouteModel] = []
        for (i, r) in (bundle.primary?.routes ?? []).enumerated() {
            if let m = route(r, index: i, labels: [i == 0 ? .defaultRoute : .defaultRouteAlternate]) { out.append(m) }
        }
        for (i, r) in (bundle.shortest?.routes ?? []).enumerated() {
            if let m = route(r, index: i, labels: [.shorterDistance]) {
                // تجاهل الأقصر إن كان مطابقًا لطريق موجود (نفس المسار).
                if !out.contains(where: { $0.encodedPolyline == m.encodedPolyline }) { out.append(m) }
            }
        }
        return out
    }

    public static func maneuver(_ code: String?) -> Maneuver? {
        switch code?.uppercased() {
        case "TURN_LEFT": return .turnLeft
        case "TURN_RIGHT": return .turnRight
        case "SHARP_LEFT": return .turnSharpLeft
        case "SHARP_RIGHT": return .turnSharpRight
        case "BEAR_LEFT": return .turnSlightLeft
        case "BEAR_RIGHT": return .turnSlightRight
        case "KEEP_LEFT": return .forkLeft
        case "KEEP_RIGHT": return .forkRight
        case "MAKE_UTURN", "TRY_MAKE_UTURN": return .uturnLeft
        case "ROUNDABOUT_LEFT": return .roundaboutLeft
        case "ROUNDABOUT_RIGHT", "ROUNDABOUT_CROSS", "ROUNDABOUT_BACK": return .roundaboutRight
        case "ENTER_MOTORWAY", "ENTER_FREEWAY", "ENTER_HIGHWAY", "ENTRANCE_RAMP": return .rampRight
        case "TAKE_EXIT", "MOTORWAY_EXIT_RIGHT": return .rampRight
        case "MOTORWAY_EXIT_LEFT": return .rampLeft
        case "SWITCH_PARALLEL_ROAD", "SWITCH_MAIN_ROAD": return .merge
        case "TAKE_FERRY": return .ferry
        case "STRAIGHT", "FOLLOW": return .straight
        case "DEPART": return .depart
        case "ARRIVE", "ARRIVE_LEFT", "ARRIVE_RIGHT", "WAYPOINT_REACHED", "WAYPOINT_LEFT", "WAYPOINT_RIGHT": return nil
        default: return nil
        }
    }

    // MARK: Places

    /// أنواع TomTom (أسماء التصنيف بالإنجليزية) → أنواع Google-like التي يعتمدها PlaceKindCatalog.
    static let typeByName: [String: String] = [
        "coffee shop": "coffee_shop", "café": "cafe", "cafe": "cafe", "café/pub": "cafe", "cafe/pub": "cafe",
        "tea house": "tea_house", "internet café": "cafe", "internet cafe": "cafe",
        "restaurant": "restaurant", "italian": "italian_restaurant", "pizza": "pizza_restaurant", "hamburgers": "hamburger_restaurant",
        "fast food": "fast_food_restaurant", "seafood": "seafood_restaurant", "indian": "indian_restaurant",
        "chinese": "chinese_restaurant", "japanese": "japanese_restaurant", "thai": "thai_restaurant", "korean": "korean_restaurant",
        "asian (other)": "asian_restaurant", "lebanese": "lebanese_restaurant", "middle eastern": "middle_eastern_restaurant",
        "arabian": "middle_eastern_restaurant", "turkish": "turkish_restaurant", "barbecue": "barbecue_restaurant",
        "grill": "barbecue_restaurant", "steak house": "steak_house", "ice cream parlor": "ice_cream_shop",
        "food drinks: bakers": "bakery", "bakery": "bakery", "sushi": "sushi_restaurant", "mediterranean": "mediterranean_restaurant",
        "breakfast": "breakfast_restaurant", "sandwich": "sandwich_shop", "dessert": "dessert_shop", "pub": "bar", "microbrewery/beer garden": "bar",
    ]

    public static func types(for poi: TTPOI?) -> [String] {
        var out: [String] = []
        let names = (poi?.classifications ?? []).flatMap { c -> [String] in
            let en = (c.names ?? []).filter { ($0.nameLocale ?? "").lowercased().hasPrefix("en") }.compactMap(\.name)
            return en.isEmpty ? (c.names ?? []).compactMap(\.name) : en
        } + (poi?.categories ?? [])
        for n in names {
            if let t = typeByName[n.lowercased()], !out.contains(t) { out.append(t) }
        }
        if out.isEmpty {
            for c in poi?.categorySet ?? [] {
                if c.id == 7315 { out.append("restaurant") } else if c.id == 9376 { out.append("cafe") }
            }
        }
        return out
    }

    public static func place(_ r: TTSearchResult, details: TTPoiDetailsResponse? = nil) -> NearbyPlace? {
        guard let id = r.id, let name = r.poi?.name, let pos = r.position else { return nil }
        let ts = types(for: r.poi)
        let hood = r.address?.municipalitySubdivision
        let open = openNow(r.poi?.openingHours)
        var place = NearbyPlace(
            placeID: id,
            name: name,
            coordinate: Coordinate(latitude: pos.lat, longitude: pos.lon),
            types: ts,
            primaryType: ts.first,
            rating: nil,
            ratingCount: nil,
            photos: [],
            distanceMeters: r.dist.map { Int($0.rounded()) },
            drivingETASeconds: nil,
            openNow: open,
            businessStatus: .operational,
            priceLevel: nil,
            neighborhood: hood,
            address: r.address?.freeformAddress,
            shortAddress: [r.address?.streetName, hood].compactMap { $0 }.joined(separator: "، "),
            website: r.poi?.url.flatMap { URL(string: $0.hasPrefix("http") ? $0 : "https://\($0)") },
            phone: r.poi?.phone,
            googleMapsURI: nil,
            menuURL: nil,
            weekdayHours: hoursDescriptions(r.poi?.openingHours),
            attributes: [],
            accessibility: [],
            editorialSummary: nil
        )
        if let d = details?.result {
            if let v = d.rating?.value {
                // TomTom يعيد التقييم على مقياسه (عادة 0–5)؛ نُطبّعه إلى 5.
                let max = d.rating?.scale?.max ?? 5
                place.rating = max > 0 ? (v / max) * 5 : v
                place.ratingCount = d.rating?.totalRatings
            }
            if let start = d.priceRange?.scaledRange?.start?.value {
                switch Int(start.rounded()) {
                case ...1: place.priceLevel = .inexpensive
                case 2: place.priceLevel = .moderate
                case 3: place.priceLevel = .expensive
                default: place.priceLevel = .veryExpensive
                }
            }
            place.photos = (d.photos ?? []).compactMap { $0.id }.map { PhotoReference(name: "tt:\($0)", widthPx: nil, heightPx: nil, authorAttributions: []) }
            place.editorialSummary = d.description?.value
        }
        return place
    }

    public static func suggestion(_ r: TTSearchResult) -> SearchSuggestion? {
        guard let id = r.id, let pos = r.position else { return nil }
        let main = r.poi?.name ?? r.address?.freeformAddress ?? r.address?.streetName ?? ""
        guard !main.isEmpty else { return nil }
        let secondary = r.poi != nil ? r.address?.freeformAddress : [r.address?.municipalitySubdivision, r.address?.municipality].compactMap { $0 }.joined(separator: "، ")
        return SearchSuggestion(placeID: id, mainText: main, secondaryText: secondary?.isEmpty == false ? secondary : nil, distanceMeters: r.dist.map { Int($0.rounded()) }, coordinate: Coordinate(latitude: pos.lat, longitude: pos.lon))
    }

    // MARK: Opening hours (mode nextSevenDays)

    static func openNow(_ h: TTOpeningHours?, now: Date = .init()) -> Bool? {
        guard let ranges = h?.timeRanges, !ranges.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        for r in ranges {
            guard let s = r.startTime, let e = r.endTime, let sd = s.date, let ed = e.date,
                  let start = f.date(from: String(format: "%@ %02d:%02d", sd, s.hour ?? 0, s.minute ?? 0)),
                  let end = f.date(from: String(format: "%@ %02d:%02d", ed, e.hour ?? 0, e.minute ?? 0)) else { continue }
            if now >= start && now <= end { return true }
        }
        return false
    }

    static func hoursDescriptions(_ h: TTOpeningHours?) -> [String]? {
        guard let ranges = h?.timeRanges, !ranges.isEmpty else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        let day = DateFormatter(); day.dateFormat = "EEEE"
        var out: [String] = []
        for r in ranges.prefix(7) {
            guard let s = r.startTime, let e = r.endTime, let sd = s.date, let d = df.date(from: sd) else { continue }
            out.append("\(day.string(from: d)): \(String(format: "%02d:%02d", s.hour ?? 0, s.minute ?? 0)) – \(String(format: "%02d:%02d", e.hour ?? 0, e.minute ?? 0))")
        }
        return out.isEmpty ? nil : out
    }
}
