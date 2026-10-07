import Domain
import Features
import MapKit
import SwiftUI

/// أسطح الخريطة بـ Apple MapKit (مجاني، بلا مفتاح). يُستخدم مع مزوّد TomTom للبيانات.
@MainActor
final class MapKitMapSurfaces: MapSurfaces {
    private let navigation: GuidanceNavigationProvider

    init(navigation: GuidanceNavigationProvider) { self.navigation = navigation }

    func homeMap(userLocation: Coordinate?) -> AnyView { AnyView(HomeMapView(userLocation: userLocation)) }
    func routesMap(origin: Coordinate, destination: Coordinate?, overlays: [MapRouteOverlay]) -> AnyView { AnyView(RoutesMapView(origin: origin, destination: destination, overlays: overlays)) }
    func nearbyMap(center: Coordinate, pins: [Domain.MapPin], onPinTap: @escaping (String) -> Void, onRegionMoved: @escaping (Coordinate) -> Void) -> AnyView {
        AnyView(NearbyMapView(center: center, pins: pins, onPinTap: onPinTap, onRegionMoved: onRegionMoved))
    }
    func navigationMap() -> AnyView { AnyView(NavigationMapView(provider: navigation)) }
    func pickerMap(initial: Coordinate, onMove: @escaping (Coordinate) -> Void) -> AnyView { AnyView(PickerMapView(initial: initial, onMove: onMove)) }
}

private extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private func strategyColor(_ s: RouteStrategy?) -> Color {
    switch s { case .noStop: return Color(red: 0.082, green: 0.725, blue: 0.561); case .fastest: return Color(red: 0.125, green: 0.651, blue: 0.847); default: return Color(red: 0.42, green: 0.478, blue: 0.47) }
}

private func rect(for coords: [CLLocationCoordinate2D]) -> MKMapRect {
    coords.reduce(MKMapRect.null) { r, c in
        let p = MKMapPoint(c)
        return r.union(MKMapRect(x: p.x, y: p.y, width: 0.1, height: 0.1))
    }
}

/// نمط موحّد: خريطة هادئة بلا نقاط اهتمام (الأماكن تأتي من مزوّدنا).
private extension View {
    func calmMapStyle() -> some View {
        mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
    }
}

struct HomeMapView: View {
    var userLocation: Coordinate?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) { UserAnnotation() }
            .calmMapStyle()
            .mapControls { }
            .ignoresSafeArea()
            .onChange(of: userLocation) { _, new in
                if let c = new, position == .automatic { position = .camera(MapCamera(centerCoordinate: c.cl, distance: 2500)) }
            }
    }
}

struct RoutesMapView: View {
    var origin: Coordinate
    var destination: Coordinate?
    var overlays: [MapRouteOverlay]
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(overlays.sorted { !$0.highlighted && $1.highlighted }) { o in
                MapPolyline(coordinates: Polyline.decode(o.encodedPolyline).map(\.cl))
                    .stroke(o.highlighted ? strategyColor(o.strategy) : Color(white: 0.78), style: StrokeStyle(lineWidth: o.highlighted ? 7 : 4, lineCap: .round, lineJoin: .round))
            }
            Annotation("", coordinate: origin.cl) { Circle().fill(strategyColor(.noStop)).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 3)) }
            if let d = destination { Marker("", coordinate: d.cl).tint(Color(red: 0.055, green: 0.11, blue: 0.133)) }
        }
        .calmMapStyle()
        .mapControls { }
        .ignoresSafeArea()
        .onAppear(perform: fit)
        .onChange(of: overlays.map(\.id)) { _, _ in fit() }
    }

    private func fit() {
        var coords = overlays.flatMap { Polyline.decode($0.encodedPolyline).map(\.cl) }
        coords.append(origin.cl)
        if let d = destination { coords.append(d.cl) }
        guard coords.count > 1 else { position = .camera(MapCamera(centerCoordinate: origin.cl, distance: 4000)); return }
        position = .rect(rect(for: coords).insetBy(dx: -800, dy: -800))
    }
}

struct NearbyMapView: View {
    var center: Coordinate
    var pins: [Domain.MapPin]
    var onPinTap: (String) -> Void
    var onRegionMoved: (Coordinate) -> Void
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate.cl, anchor: .bottom) {
                    Button { onPinTap(pin.id) } label: {
                        Text(pin.subtitle ?? pin.title)
                            .font(.system(size: 12, weight: .heavy))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(pin.selected ? strategyColor(.fastest) : Color.white, in: Capsule())
                            .foregroundStyle(pin.selected ? .white : Color(red: 0.055, green: 0.11, blue: 0.133))
                            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
                    }
                }
            }
        }
        .calmMapStyle()
        .mapControls { }
        .onAppear { position = .camera(MapCamera(centerCoordinate: center.cl, distance: 6000)) }
        .onMapCameraChange(frequency: .onEnd) { ctx in onRegionMoved(Coordinate(latitude: ctx.camera.centerCoordinate.latitude, longitude: ctx.camera.centerCoordinate.longitude)) }
    }
}

struct PickerMapView: View {
    var initial: Coordinate
    var onMove: (Coordinate) -> Void
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) { UserAnnotation() }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .all))
            .ignoresSafeArea()
            .onAppear { position = .camera(MapCamera(centerCoordinate: initial.cl, distance: 1500)) }
            .onMapCameraChange(frequency: .onEnd) { ctx in onMove(Coordinate(latitude: ctx.camera.centerCoordinate.latitude, longitude: ctx.camera.centerCoordinate.longitude)) }
    }
}

/// خريطة الملاحة: المسار النشط + موقع المستخدم مع متابعة الاتجاه.
struct NavigationMapView: View {
    let provider: GuidanceNavigationProvider
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            if let r = provider.activeRoute {
                MapPolyline(coordinates: Polyline.decode(r.encodedPolyline).map(\.cl))
                    .stroke(strategyColor(provider.strategy), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            }
            if let d = provider.destinationCoordinate { Marker("", coordinate: d.cl).tint(Color(red: 0.055, green: 0.11, blue: 0.133)) }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: true))
        .mapControls { MapCompass() }
        .ignoresSafeArea()
    }
}
