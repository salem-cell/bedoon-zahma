import DesignSystem
import Domain
import SwiftUI

/// وجهات التنقل.
public enum AppRoute: Hashable {
    case search
    case mapPicker
    case routeOptions
    case navigation
    case nearby(kindID: String)
    case place(placeID: String, kindID: String)
    case favorites
}

@MainActor @Observable
public final class AppRouter {
    public var path = NavigationPath()
    public init() {}
    public func push(_ r: AppRoute) { path.append(r) }
    public func pop() { if !path.isEmpty { path.removeLast() } }
    public func popToRoot() { path = NavigationPath() }
}

/// الجذر: NavigationStack واحد + حقن البيئة.
public struct RootView: View {
    let env: AppEnvironment
    @State private var router = AppRouter()

    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .search: SearchView()
                    case .mapPicker: MapPickerView()
                    case .routeOptions: RouteOptionsView()
                    case .navigation: NavigationScreen()
                    case .nearby(let kindID): NearbyView(kindID: kindID)
                    case .place(let placeID, let kindID): PlaceDetailsView(placeID: placeID, kindID: kindID)
                    case .favorites: FavoritesView()
                    }
                }
        }
        .environment(\.appEnv, env)
        .environment(router)
        .environment(env.trip)
        .environment(\.layoutDirection, env.isRTL ? .rightToLeft : .leftToRight)
        .tint(BZColor.ink)
        .task { await env.remoteConfig.refreshIfNeeded() }
    }
}

extension View {
    /// إخفاء شريط التنقل (iOS فقط؛ على macOS للاختبارات لا يفعل شيئًا).
    func bzHideNavBar() -> some View {
        #if os(iOS)
        return toolbar(.hidden, for: .navigationBar)
        #else
        return self
        #endif
    }

    /// تبويبات بتمرير صفحات (iOS فقط).
    func bzPagedTabs() -> some View {
        #if os(iOS)
        return tabViewStyle(.page(indexDisplayMode: .automatic))
        #else
        return self
        #endif
    }
}

/// شريط علوي موحّد: زر رجوع + عنوان.
struct ScreenHeader<Trailing: View>: View {
    var title: String?
    var trailing: Trailing
    @Environment(AppRouter.self) private var router

    init(title: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundIconButton("arrow.forward") { router.pop() }
                .accessibilityLabel(L("common.back"))
            if let title {
                Text(title).font(BZFont.title).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("screen.title")
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String? = nil) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// شارة «بيانات تجريبية» عند تشغيل DevMocks.
struct DevBadge: View {
    @Environment(\.appEnv) private var env
    var body: some View {
        if env?.isDevMock == true {
            Text(L("dev.badge"))
                .font(BZFont.mono)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(BZColor.orange, in: Capsule())
                .foregroundStyle(BZColor.ink)
        }
    }
}

extension AppError {
    /// نصوص الأخطاء للمستخدم.
    var userTitle: String {
        switch self {
        case .locationUnavailable: return L("error.gps.title")
        case .locationPermissionDenied: return L("error.permission.title")
        case .offline: return L("error.offline.title")
        case .providerFailure: return L("error.provider.title")
        case .rateLimited: return L("error.rate.title")
        case .timeout: return L("error.timeout.title")
        case .noPlacesFound: return L("error.noplaces.title")
        case .noRouteAvailable: return L("error.noroute.title")
        case .trafficDataUnavailable: return L("error.traffic.title")
        case .photoUnavailable: return L("error.photo.title")
        case .placeTemporarilyClosed: return L("error.closed.title")
        case .cancelled: return ""
        case .decoding, .unknown: return L("error.generic.title")
        }
    }

    var userMessage: String? {
        switch self {
        case .locationPermissionDenied: return L("error.permission.message")
        case .offline: return L("error.offline.message")
        case .rateLimited: return L("error.rate.message")
        case .noRouteAvailable: return L("error.noroute.message")
        default: return nil
        }
    }
}
