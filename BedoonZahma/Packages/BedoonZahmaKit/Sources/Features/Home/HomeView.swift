import DesignSystem
import Domain
import SwiftUI

@MainActor @Observable
final class HomeViewModel {
    var userLocation: Coordinate?
    var authorization: LocationAuthorization = .notDetermined
    var error: AppError?
    private var env: AppEnvironment?
    private var updatesTask: Task<Void, Never>?

    func bind(_ env: AppEnvironment) {
        guard self.env == nil else { return }
        self.env = env
        Task { [self] in await start() }
    }

    func start() async {
        guard let env else { return }
        authorization = await env.location.authorization
        if authorization == .notDetermined {
            authorization = await env.location.requestWhenInUseAuthorization()
        }
        guard authorization == .whenInUse || authorization == .always else {
            error = .locationPermissionDenied
            return
        }
        do {
            userLocation = try await env.location.currentLocation()
            error = nil
        } catch let e as AppError {
            error = e
        } catch { self.error = .locationUnavailable }
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await c in env.location.locationUpdates() {
                guard !Task.isCancelled else { break }
                self?.userLocation = c
            }
        }
    }

    func stop() { updatesTask?.cancel(); updatesTask = nil }
}

/// الرئيسية: الخريطة أولًا، «وين رايح؟»، ثم مقاهيي/مطاعمي. لا شيء آخر.
struct HomeView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @State private var vm = HomeViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            if let env { env.maps.homeMap(userLocation: vm.userLocation) } else { Color.clear }

            VStack(spacing: 14) {
                HStack {
                    HStack(spacing: 10) {
                        BZLogo(color: BZColor.ink).frame(width: 34, height: 34)
                        Text(L("app.name")).font(BZFont.title).lineLimit(1)
                        DevBadge()
                    }
                    Spacer()
                    RoundIconButton("heart") { router.push(.favorites) }
                        .accessibilityLabel(L("favorites.title"))
                }

                Button { router.push(.search) } label: {
                    HStack(spacing: 12) {
                        Circle().strokeBorder(BZColor.green, lineWidth: 3).frame(width: 12, height: 12)
                        Text(L("home.where")).font(BZFont.font(19, weight: .bold)).foregroundStyle(BZColor.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: BZColor.ink.opacity(0.12), radius: 15, y: 8)
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint(L("home.where.hint"))

                HStack(spacing: 10) {
                    quickButton("☕", L("home.cafes"), BZColor.skyTint) { router.push(.nearby(kindID: "cafes")) }
                    quickButton("🍽️", L("home.restaurants"), BZColor.orangeTint) { router.push(.nearby(kindID: "restaurants")) }
                }

                if let error = vm.error {
                    HStack(spacing: 10) {
                        Image(systemName: "location.slash").foregroundStyle(BZColor.orangeDark)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.userTitle).font(BZFont.caption.weight(.bold))
                            if let m = error.userMessage { Text(m).font(BZFont.small).foregroundStyle(BZColor.mute) }
                        }
                        Spacer()
                        if error == .locationPermissionDenied {
                            Button(L("common.settings")) { openSettings() }.font(BZFont.caption.weight(.bold))
                        } else {
                            Button(L("common.retry")) { Task { await vm.start() } }.font(BZFont.caption.weight(.bold))
                        }
                    }
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .bzHideNavBar()
        .onAppear { if let env { vm.bind(env) } }
        .onDisappear { vm.stop() }
    }

    private func quickButton(_ emoji: String, _ title: String, _ bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(emoji)
                Text(title).font(BZFont.body.weight(.bold)).foregroundStyle(BZColor.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: BZColor.ink.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}
