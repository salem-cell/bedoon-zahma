import Domain
import Features
import GoogleMaps
import SwiftUI

/// تنفيذ أسطح الخريطة بـ Google Maps SDK for iOS.
@MainActor
final class GoogleMapSurfaces: MapSurfaces {
    private let navigation: GoogleNavigationProvider

    init(navigation: GoogleNavigationProvider) { self.navigation = navigation }

    func homeMap(userLocation: Coordinate?) -> AnyView {
        AnyView(GMSMapRepresentable(center: userLocation, zoom: 14, showsUser: true, overlays: [], pins: [], destination: nil, onPinTap: nil, onRegionMoved: nil).ignoresSafeArea())
    }

    func routesMap(origin: Coordinate, destination: Coordinate?, overlays: [MapRouteOverlay]) -> AnyView {
        AnyView(GMSMapRepresentable(center: origin, zoom: 12, showsUser: true, overlays: overlays, pins: [], destination: destination, onPinTap: nil, onRegionMoved: nil, fitOverlays: true).ignoresSafeArea())
    }

    func nearbyMap(center: Coordinate, pins: [MapPin], onPinTap: @escaping (String) -> Void, onRegionMoved: @escaping (Coordinate) -> Void) -> AnyView {
        AnyView(GMSMapRepresentable(center: center, zoom: 13, showsUser: true, overlays: [], pins: pins, destination: nil, onPinTap: onPinTap, onRegionMoved: onRegionMoved))
    }

    func navigationMap() -> AnyView {
        AnyView(NavigationMapRepresentable(provider: navigation).ignoresSafeArea())
    }

    func pickerMap(initial: Coordinate, onMove: @escaping (Coordinate) -> Void) -> AnyView {
        AnyView(GMSMapRepresentable(center: initial, zoom: 15, showsUser: true, overlays: [], pins: [], destination: nil, onPinTap: nil, onRegionMoved: onMove).ignoresSafeArea())
    }
}

/// GMSMapView داخل SwiftUI: مسارات ملوّنة بالمرور، دبابيس، وموقع المستخدم.
struct GMSMapRepresentable: UIViewRepresentable {
    var center: Coordinate?
    var zoom: Float
    var showsUser: Bool
    var overlays: [MapRouteOverlay]
    var pins: [MapPin]
    var destination: Coordinate?
    var onPinTap: ((String) -> Void)?
    var onRegionMoved: ((Coordinate) -> Void)?
    var fitOverlays = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        if let c = center { options.camera = GMSCameraPosition(latitude: c.latitude, longitude: c.longitude, zoom: zoom) }
        let map = GMSMapView(options: options)
        map.isMyLocationEnabled = showsUser
        map.settings.myLocationButton = false
        map.settings.compassButton = false
        map.isBuildingsEnabled = false
        map.delegate = context.coordinator
        if let style = try? GMSMapStyle(jsonString: Self.calmStyle) { map.mapStyle = style }
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastCenter != center, let c = center, overlays.isEmpty {
            context.coordinator.lastCenter = center
            map.animate(to: GMSCameraPosition(latitude: c.latitude, longitude: c.longitude, zoom: zoom))
        }
        context.coordinator.render(on: map)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GMSMapRepresentable
        var lastCenter: Coordinate?
        private var drawn: [GMSOverlay] = []
        private var lastSignature = ""

        init(_ parent: GMSMapRepresentable) { self.parent = parent }

        func render(on map: GMSMapView) {
            let signature = parent.overlays.map { "\($0.id)\($0.highlighted)" }.joined() + parent.pins.map { "\($0.id)\($0.selected)" }.joined() + "\(parent.destination?.latitude ?? 0)"
            guard signature != lastSignature else { return }
            lastSignature = signature
            drawn.forEach { $0.map = nil }
            drawn.removeAll()
            var bounds = GMSCoordinateBounds()

            // المسارات غير المختارة أولًا ثم المختار فوقها.
            for o in parent.overlays.sorted(by: { !$0.highlighted && $1.highlighted }) {
                let coords = Polyline.decode(o.encodedPolyline)
                let path = GMSMutablePath()
                coords.forEach { path.add(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
                let line = GMSPolyline(path: path)
                line.strokeWidth = o.highlighted ? 7 : 4
                line.zIndex = o.highlighted ? 10 : 1
                let base: UIColor = o.highlighted ? Self.color(for: o.strategy) : UIColor(white: 0.78, alpha: 1)
                if o.highlighted, let intervals = o.speedIntervals, !intervals.isEmpty {
                    // تلوين فواصل المرور على المسار المختار (NORMAL = لون الاستراتيجية، SLOW = برتقالي، JAM = أحمر).
                    var spans: [GMSStyleSpan] = []
                    for iv in intervals {
                        let seg = max(iv.endPolylinePointIndex - iv.startPolylinePointIndex, 1)
                        let c: UIColor = iv.speed == .normal ? base : (iv.speed == .slow ? UIColor(red: 0.95, green: 0.6, blue: 0.29, alpha: 1) : UIColor(red: 0.85, green: 0.22, blue: 0.17, alpha: 1))
                        spans.append(GMSStyleSpan(style: GMSStrokeStyle.solidColor(c), segments: Double(seg)))
                    }
                    line.spans = spans
                } else {
                    line.strokeColor = base
                }
                line.map = map
                drawn.append(line)
                coords.forEach { bounds = bounds.includingCoordinate(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            }

            if let d = parent.destination {
                let m = GMSMarker(position: CLLocationCoordinate2D(latitude: d.latitude, longitude: d.longitude))
                m.icon = GMSMarker.markerImage(with: UIColor(red: 0.055, green: 0.11, blue: 0.133, alpha: 1))
                m.map = map
                drawn.append(m)
                bounds = bounds.includingCoordinate(m.position)
            }

            for pin in parent.pins {
                let m = GMSMarker(position: CLLocationCoordinate2D(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
                m.userData = pin.id
                m.iconView = Self.pinView(text: pin.subtitle ?? pin.title, selected: pin.selected)
                m.groundAnchor = CGPoint(x: 0.5, y: 1)
                m.zIndex = pin.selected ? 5 : 1
                m.map = map
                drawn.append(m)
            }

            if parent.fitOverlays, bounds.isValid {
                map.animate(with: GMSCameraUpdate.fit(bounds, with: UIEdgeInsets(top: 140, left: 40, bottom: 360, right: 40)))
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String { parent.onPinTap?(id) }
            return true
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            parent.onRegionMoved?(Coordinate(latitude: position.target.latitude, longitude: position.target.longitude))
        }

        static func color(for s: RouteStrategy?) -> UIColor {
            switch s {
            case .noStop: return UIColor(red: 0.082, green: 0.725, blue: 0.561, alpha: 1)
            case .fastest: return UIColor(red: 0.125, green: 0.651, blue: 0.847, alpha: 1)
            default: return UIColor(red: 0.42, green: 0.478, blue: 0.47, alpha: 1)
            }
        }

        static func pinView(text: String, selected: Bool) -> UIView {
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .heavy)
            label.textColor = selected ? .white : UIColor(red: 0.055, green: 0.11, blue: 0.133, alpha: 1)
            label.sizeToFit()
            let v = UIView(frame: CGRect(x: 0, y: 0, width: label.bounds.width + 20, height: 30))
            v.backgroundColor = selected ? UIColor(red: 0.125, green: 0.651, blue: 0.847, alpha: 1) : .white
            v.layer.cornerRadius = 15
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.18
            v.layer.shadowRadius = 6
            v.layer.shadowOffset = CGSize(width: 0, height: 3)
            label.center = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
            v.addSubview(label)
            return v
        }
    }

    /// نمط خريطة هادئ يطابق هوية «بوابة الوصول» (ألوان فاتحة، إخفاء نقاط الاهتمام لتقليل الازدحام البصري).
    static let calmStyle = """
    [
      {"elementType":"geometry","stylers":[{"color":"#eef1ef"}]},
      {"elementType":"labels.text.fill","stylers":[{"color":"#6b7a78"}]},
      {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"}]},
      {"featureType":"poi","stylers":[{"visibility":"off"}]},
      {"featureType":"transit","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
      {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
      {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#f6f8f7"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#dfe4e1"}]},
      {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#f9faf9"}]},
      {"featureType":"water","elementType":"geometry","stylers":[{"color":"#d7e9f3"}]},
      {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e2e7e4"}]}
    ]
    """
}
