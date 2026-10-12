import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// محمّل صور الأماكن: ذاكرة مؤقتة في الذاكرة فقط (لا قرص) التزامًا بشروط Google بعدم تخزين الصور،
/// مع دمج الطلبات المتزامنة للرابط نفسه كي لا تُحمَّل صورة البطاقة مرتين عند التمرير السريع.
@MainActor
final class PlaceImageLoader {
    static let shared = PlaceImageLoader()

    enum LoadError: Error { case badStatus(Int), undecodable }

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: cfg)
        cache.totalCostLimit = 64 * 1024 * 1024 // ~64MB من الصور المفكوكة ضمن الجلسة
        cache.countLimit = 300
    }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL) async throws -> UIImage {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return try await running.value }
        let task = Task<UIImage, Error> { [session] in
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw LoadError.badStatus(http.statusCode) }
            guard let img = UIImage(data: data) else { throw LoadError.undecodable }
            // فكّ الترميز خارج الخيط الرئيسي يمنع التقطيع أثناء التمرير.
            return await Task.detached(priority: .userInitiated) { img.preparingForDisplay() ?? img }.value
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let img = try await task.value
        cache.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4))
        return img
    }

    /// تحميل مسبق لصور الغلاف القادمة في القائمة.
    func prefetch(_ urls: [URL]) {
        for u in urls where cache.object(forKey: u as NSURL) == nil && inFlight[u] == nil {
            Task { _ = try? await image(for: u) }
        }
    }
}

/// صورة شبكية بظهور تدريجي؛ تُبلغ عن الفشل كي يعرض المستدعي بديلًا حقيقيًا.
struct RemoteImage<Placeholder: View>: View {
    var url: URL
    var contentMode: ContentMode = .fill
    var onFailure: (() -> Void)? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            if let hit = PlaceImageLoader.shared.cached(url) { image = hit; return }
            do {
                let img = try await PlaceImageLoader.shared.image(for: url)
                withAnimation(.easeOut(duration: 0.25)) { image = img }
            } catch {
                if !Task.isCancelled { onFailure?() }
            }
        }
    }
}
