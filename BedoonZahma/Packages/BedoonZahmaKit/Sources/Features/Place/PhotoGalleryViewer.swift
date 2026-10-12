import DesignSystem
import Domain
import SwiftUI

/// عارض صور بملء الشاشة: تمرير بين الصور، تكبير بالقرص ونقرتين، عدّاد، إسناد المصوّر (مطلوب في شروط Google)، وإغلاق بالسحب للأسفل.
struct PhotoGalleryViewer: View {
    var photos: [PhotoReference]
    @Binding var index: Int
    var onClose: () -> Void
    @Environment(\.appEnv) private var env
    @Environment(\.openURL) private var openURL
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea().opacity(1 - min(abs(dragOffset) / 600, 0.6))
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, ph in
                    ZoomableRemotePhoto(url: env?.places.photoURL(for: ph, maxWidthPx: 1600))
                        .tag(i)
                        .accessibilityIdentifier("gallery.photo.\(i)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in if abs(v.translation.height) > abs(v.translation.width) { dragOffset = v.translation.height } }
                    .onEnded { v in
                        if abs(v.translation.height) > 120 { onClose() } else { withAnimation(.spring(duration: 0.3)) { dragOffset = 0 } }
                    }
            )

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.white.opacity(0.18), in: Circle())
                }
                .accessibilityLabel(L("photo.viewer.close"))
                .accessibilityIdentifier("gallery.close")
                Spacer()
                Text(L("photo.counter", index + 1, photos.count))
                    .font(BZFont.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.18), in: Capsule())
            }
            .padding(.horizontal, 16).padding(.top, 8)

            if photos.indices.contains(index), let a = photos[index].authorAttributions.first {
                VStack {
                    Spacer()
                    Button {
                        if let s = a.uri, let u = URL(string: s) { openURL(u) }
                    } label: {
                        Label(L("photo.by", a.displayName), systemImage: "camera.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7).background(.white.opacity(0.18), in: Capsule())
                    }
                    .disabled(a.uri == nil)
                    .padding(.bottom, 24)
                }
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }
}

/// صورة قابلة للتكبير بالقرص (1x–4x) مع إعادة الضبط بنقرتين.
struct ZoomableRemotePhoto: View {
    var url: URL?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let url {
                    RemoteImage(url: url, contentMode: .fit) {
                        ProgressView().tint(.white)
                    }
                } else {
                    Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(lastScale * v.magnification, 1), 4) }
                    .onEnded { _ in lastScale = scale; if scale == 1 { withAnimation { offset = .zero; lastOffset = .zero } } }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } else { scale = 2.5; lastScale = 2.5 }
                }
            }
        }
    }
}
