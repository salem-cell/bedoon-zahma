import BackendClient
import Domain
import Foundation

/// تحويل DTOs Google إلى نماذج Domain. أي حقل غائب يبقى nil.
public enum GoogleMappers {
    public static func route(_ g: GRoute, index: Int) -> RouteModel? {
        guard let distance = g.distanceMeters, let duration = parseGoogleDuration(g.duration), let poly = g.polyline?.encodedPolyline else { return nil }
        let labels = (g.routeLabels ?? []).map { RouteLabel(rawValue: $0) ?? .unknown }
        let intervals = g.travelAdvisory?.speedReadingIntervals?.compactMap { iv -> SpeedReadingInterval? in
            // startPolylinePointIndex يُحذف من JSON عندما يساوي 0 (سلوك proto3).
            guard let e = iv.endPolylinePointIndex, let sp = iv.speed.flatMap(TrafficSpeed.init(rawValue:)) else { return nil }
            return SpeedReadingInterval(startPolylinePointIndex: iv.startPolylinePointIndex ?? 0, endPolylinePointIndex: e, speed: sp)
        }
        let steps = (g.legs ?? []).flatMap { $0.steps ?? [] }.map {
            RouteStep(
                instruction: $0.navigationInstruction?.instructions,
                maneuver: $0.navigationInstruction?.maneuver.flatMap(Maneuver.init(rawValue:)),
                distanceMeters: $0.distanceMeters ?? 0,
                staticDurationSeconds: parseGoogleDuration($0.staticDuration)
            )
        }
        var warnings = g.warnings ?? []
        if g.travelAdvisory?.routeRestrictionsPartiallyIgnored == true { warnings.append("ROUTE_RESTRICTIONS_PARTIALLY_IGNORED") }
        let localized = g.localizedValues.map {
            LocalizedRouteValues(distance: $0.distance?.text, duration: $0.duration?.text, staticDuration: $0.staticDuration?.text)
        }
        let id = g.routeToken.map { String($0.suffix(16)) } ?? "\(index)-\(poly.hashValue)"
        return RouteModel(
            id: "route-\(index)-\(id)",
            labels: labels,
            distanceMeters: distance,
            durationSeconds: duration,
            staticDurationSeconds: parseGoogleDuration(g.staticDuration),
            encodedPolyline: poly,
            speedReadingIntervals: intervals,
            steps: steps,
            summary: g.description,
            warnings: warnings,
            routeToken: g.routeToken,
            localized: localized
        )
    }

    public static func place(_ g: GPlace, routing: GRoutingSummary? = nil) -> NearbyPlace? {
        guard let id = g.id, let name = g.displayName?.text, let loc = g.location else { return nil }
        var attrs: Set<PlaceAttribute> = []
        if g.servesBreakfast == true { attrs.insert(.servesBreakfast) }
        if g.servesBrunch == true { attrs.insert(.servesBrunch) }
        if g.servesDessert == true { attrs.insert(.servesDessert) }
        if g.servesCoffee == true { attrs.insert(.servesCoffee) }
        if g.outdoorSeating == true { attrs.insert(.outdoorSeating) }
        if g.takeout == true { attrs.insert(.takeout) }
        if g.dineIn == true { attrs.insert(.dineIn) }
        if g.delivery == true { attrs.insert(.delivery) }
        if g.reservable == true { attrs.insert(.reservable) }

        var access: [String] = []
        if g.accessibilityOptions?.wheelchairAccessibleEntrance == true { access.append("wheelchair_entrance") }
        if g.accessibilityOptions?.wheelchairAccessibleParking == true { access.append("wheelchair_parking") }
        if g.accessibilityOptions?.wheelchairAccessibleSeating == true { access.append("wheelchair_seating") }
        if g.accessibilityOptions?.wheelchairAccessibleRestroom == true { access.append("wheelchair_restroom") }

        let neighborhood = g.addressComponents?.first { c in
            let t = c.types ?? []
            return t.contains("neighborhood") || t.contains("sublocality_level_1") || t.contains("sublocality")
        }?.longText

        let photos = (g.photos ?? []).compactMap { p -> PhotoReference? in
            guard let n = p.name else { return nil }
            return PhotoReference(
                name: n, widthPx: p.widthPx, heightPx: p.heightPx,
                authorAttributions: (p.authorAttributions ?? []).compactMap {
                    guard let d = $0.displayName else { return nil }
                    return AuthorAttribution(displayName: d, uri: $0.uri, photoUri: $0.photoUri)
                }
            )
        }

        let leg = routing?.legs?.first
        return NearbyPlace(
            placeID: id,
            name: name,
            coordinate: Coordinate(latitude: loc.latitude, longitude: loc.longitude),
            types: g.types ?? [],
            primaryType: g.primaryType,
            rating: g.rating,
            ratingCount: g.userRatingCount,
            photos: photos,
            distanceMeters: leg?.distanceMeters,
            drivingETASeconds: parseGoogleDuration(leg?.duration),
            openNow: g.currentOpeningHours?.openNow,
            businessStatus: g.businessStatus.flatMap(BusinessStatus.init(rawValue:)),
            priceLevel: g.priceLevel.flatMap(PriceLevel.init(rawValue:)),
            neighborhood: neighborhood,
            address: g.formattedAddress,
            shortAddress: g.shortFormattedAddress,
            website: g.websiteUri.flatMap(URL.init(string:)),
            phone: g.nationalPhoneNumber ?? g.internationalPhoneNumber,
            googleMapsURI: g.googleMapsUri.flatMap(URL.init(string:)),
            menuURL: nil, // لا يوجد حقل منيو رسمي في Places API (New)
            weekdayHours: g.regularOpeningHours?.weekdayDescriptions ?? g.currentOpeningHours?.weekdayDescriptions,
            attributes: attrs,
            accessibility: access,
            editorialSummary: g.editorialSummary?.text
        )
    }

    public static func suggestion(_ g: GSuggestion) -> SearchSuggestion? {
        guard let p = g.placePrediction, let id = p.placeId else { return nil }
        let main = p.structuredFormat?.mainText?.text ?? p.text?.text ?? ""
        return SearchSuggestion(placeID: id, mainText: main, secondaryText: p.structuredFormat?.secondaryText?.text, distanceMeters: p.distanceMeters)
    }
}
