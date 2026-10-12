import Domain
import Foundation
import MapKit
import SwiftUI
import UIKit

/// صورة شارع حقيقية من Apple Look Around لموقع المكان — بديل مجاني وقانوني عندما لا يوفر مزوّد الأماكن صورًا.
/// التغطية ليست مضمونة في كل مدينة؛ عند غيابها تُعاد nil ويعرض المستدعي بديلًا مخططًا (لا نزيّف صورة).
@MainActor
final class LookAroundCoverStore {
    static let shared = LookAroundCoverStore()

    private var images: [String: UIImage] = [:]
    private var unavailable: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    func cached(for placeID: String) -> UIImage? { images[placeID] }
    func isUnavailable(_ placeID: String) -> Bool { unavailable.contains(placeID) }

    func image(for placeID: String, at coordinate: Coordinate, size: CGSize) async -> UIImage? {
        if let img = images[placeID] { return img }
        if unavailable.contains(placeID) { return nil }
        if let running = inFlight[placeID] { return await running.value }
        let task = Task<UIImage?, Never> {
            let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard let scene = try? await request.scene else { return nil }
            let options = MKLookAroundSnapshotter.Options()
            options.size = CGSize(width: max(size.width, 320), height: max(size.height, 200))
            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
            return try? await snapshotter.snapshot.image
        }
        inFlight[placeID] = task
        let img = await task.value
        inFlight[placeID] = nil
        if let img { images[placeID] = img } else { unavailable.insert(placeID) }
        return img
    }
}

struct LookAroundCoverView<Placeholder: View>: View {
    var placeID: String
    var coordinate: Coordinate
    var size: CGSize
    var showBadge: Bool = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var resolved = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                if showBadge {
                    Text(L("photo.lookaround"))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            } else {
                placeholder()
            }
        }
        .task(id: placeID) {
            if let hit = LookAroundCoverStore.shared.cached(for: placeID) { image = hit; return }
            if LookAroundCoverStore.shared.isUnavailable(placeID) { return }
            let img = await LookAroundCoverStore.shared.image(for: placeID, at: coordinate, size: size)
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.25)) { image = img } }
        }
    }
}
