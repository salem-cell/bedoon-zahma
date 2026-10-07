import Analytics
import DesignSystem
import Domain
import SwiftUI
import TrafficEngine

@MainActor @Observable
final class RouteOptionsViewModel {
    var isLoading = false
    var error: AppError?
    private var env: AppEnvironment?
    private var task: Task<Void, Never>?

    func load(env: AppEnvironment, trip: TripState) {
        self.env = env
        guard trip.options == nil, let origin = trip.origin, let dest = trip.destination else { return }
        task?.cancel()
        isLoading = true
        error = nil
        task = Task { [self] in
            do {
                let settings = await env.settings.get()
                let req = RouteRequest(origin: origin, destination: dest, languageCode: env.languageCode, avoidTolls: settings.avoidTolls)
                let routes = try await env.routing.computeRoutes(req)
                let selector = await env.routeSelector()
                let options = selector.select(from: routes)
                guard !Task.isCancelled else { return }
                trip.options = options
                trip.strategy = options.noStop != nil ? .noStop : .fastest
                env.analytics.track(Events.routeOptionsShown(
                    noStopMin: options.noStop?.durationMinutes, fastestMin: options.fastest?.durationMinutes, shortestMin: options.shortest?.durationMinutes,
                    noStopKm: options.noStop?.distanceKm, fastestKm: options.fastest?.distanceKm, shortestKm: options.shortest?.distanceKm
                ))
            } catch let e as AppError where e != .cancelled {
                error = e
            } catch {}
            isLoading = false
        }
    }

    func retry(trip: TripState) { if let env { trip.options = nil; load(env: env, trip: trip) } }
}

/// مقارنة الطرق: 🟢 بدون توقف / ⚡ أسرع / 📏 أقصر — ثم «ابدأ».
struct RouteOptionsView: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @Environment(TripState.self) private var trip
    @State private var vm = RouteOptionsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            if let env, let origin = trip.origin {
                env.maps.routesMap(origin: origin, destination: trip.destination?.coordinate, overlays: overlays)
            } else { BZColor.mapBase.ignoresSafeArea() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    RoundIconButton("arrow.forward") { router.pop() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("routes.destination")).font(BZFont.small).foregroundStyle(BZColor.mute)
                        Text(trip.destination?.displayName ?? "").font(BZFont.body.weight(.bold)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: BZColor.ink.opacity(0.1), radius: 8, y: 4)
                }
                .padding(.horizontal, 20).padding(.top, 8)
                Spacer()
                BottomPanel {
                    if vm.isLoading {
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 18).fill(BZColor.sand).frame(height: 78) }
                        Text(L("routes.computing")).font(BZFont.caption).foregroundStyle(BZColor.mute)
                    } else if let e = vm.error {
                        ErrorStateView(title: e.userTitle, message: e.userMessage, retryTitle: L("common.retry")) { vm.retry(trip: trip) }
                    } else if let options = trip.options {
                        ForEach(RouteStrategy.allCases) { s in
                            if let r = options.route(for: s) { RouteCard(strategy: s, route: r, selected: trip.strategy == s) { select(s, options: options) } }
                        }
                        if let r = trip.selectedRoute, !r.hasTrafficData {
                            Text(L("routes.notraffic")).font(BZFont.small).foregroundStyle(BZColor.mute)
                        }
                        PrimaryButton(L("routes.start")) { start() }.padding(.top, 4)
                    }
                }
            }
        }
        .bzHideNavBar()
        .onAppear { if let env { vm.load(env: env, trip: trip) } }
    }

    private var overlays: [MapRouteOverlay] {
        guard let o = trip.options else { return [] }
        return RouteStrategy.allCases.compactMap { s in
            guard let r = o.route(for: s) else { return nil }
            return MapRouteOverlay(id: r.id + s.rawValue, encodedPolyline: r.encodedPolyline, highlighted: trip.strategy == s, strategy: s, speedIntervals: r.speedReadingIntervals)
        }
    }

    private func select(_ s: RouteStrategy, options: RouteOptions) {
        withAnimation(.easeOut(duration: 0.15)) { trip.strategy = s }
        if let r = options.route(for: s), let f = options.fastest {
            env?.analytics.track(Events.routeOptionSelected(s, extraKm: r.distanceKm - f.distanceKm, extraMin: r.durationMinutes - f.durationMinutes))
        }
    }

    private func start() {
        guard trip.selectedRoute != nil else { return }
        env?.analytics.track(Events.navigationStarted(trip.strategy, fromPlace: trip.fromPlaceKindID != nil))
        if let k = trip.fromPlaceKindID { env?.analytics.track(Events.placeNavigationStarted(kind: k)) }
        router.push(.navigation)
    }
}

struct RouteCard: View {
    var strategy: RouteStrategy
    var route: RouteModel
    var selected: Bool
    var action: () -> Void

    private var color: Color { strategy == .noStop ? BZColor.green : (strategy == .fastest ? BZColor.sky : BZColor.mute) }
    private var tint: Color { strategy == .noStop ? BZColor.greenTint : (strategy == .fastest ? BZColor.skyTint : BZColor.chipBg) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 12, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(strategy.emoji)
                        Text(strategy.title).font(BZFont.font(17, weight: .heavy))
                    }
                    Text([congestionText, route.summary].compactMap { $0 }.joined(separator: " · "))
                        .font(BZFont.small).foregroundStyle(BZColor.mute).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(route.durationMinutes)").font(BZFont.font(20, weight: .heavy))
                        Text(L("unit.minute")).font(BZFont.small.weight(.semibold))
                    }
                    Text(L("unit.km.value", route.distanceKm)).font(BZFont.small).foregroundStyle(BZColor.mute)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(selected ? tint : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? color : BZColor.line, lineWidth: 2))
            .foregroundStyle(BZColor.ink)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(strategy.title)، \(route.durationMinutes) \(L("unit.minute"))، \(L("unit.km.value", route.distanceKm))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var congestionText: String? {
        switch route.congestionLevel {
        case .light: return L("traffic.light")
        case .moderate: return L("traffic.moderate")
        case .heavy: return L("traffic.heavy")
        case .unknown: return L("traffic.unknown")
        }
    }
}

extension RouteStrategy {
    var emoji: String {
        switch self { case .noStop: return "🟢"; case .fastest: return "⚡"; case .shortest: return "📏" }
    }
    var title: String {
        switch self { case .noStop: return L("strategy.nostop"); case .fastest: return L("strategy.fastest"); case .shortest: return L("strategy.shortest") }
    }
}
