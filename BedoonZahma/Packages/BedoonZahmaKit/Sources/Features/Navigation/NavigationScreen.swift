import Analytics
import DesignSystem
import Domain
import RemoteConfig
import SwiftUI
import TrafficEngine

@MainActor @Observable
final class NavigationViewModel {
    var state: NavigationState = .idle
    var suggestion: RerouteSuggestion?
    var error: AppError?
    var voiceOn = true
    private var env: AppEnvironment?
    private var trip: TripState?
    private var listenTask: Task<Void, Never>?
    private var rerouteTask: Task<Void, Never>?
    private var lastSuggestionAt: Date?
    private var startedAt = Date()

    func start(env: AppEnvironment, trip: TripState) {
        guard self.env == nil else { return }
        self.env = env
        self.trip = trip
        startedAt = Date()
        Task { [self] in
            voiceOn = await env.settings.get().voiceGuidance
            env.navigation.setVoiceGuidance(enabled: voiceOn)
            await begin()
        }
        listenTask = Task { [weak self] in
            for await s in env.navigation.stateStream {
                guard let self, !Task.isCancelled else { break }
                self.state = s
                if case .arrived = s { self.onArrived() }
            }
        }
    }

    private func begin() async {
        guard let env, let trip, let route = trip.selectedRoute, let dest = trip.destination else { return }
        do {
            try await env.navigation.start(route: route, destination: dest, strategy: trip.strategy)
            error = nil
            scheduleRerouteChecks()
        } catch let e as AppError { error = e } catch { self.error = .unknown("\(error)") }
    }

    /// إعادة التوجيه الديناميكي لـ«بدون توقف»: نعيد الحساب دوريًا من الموقع الحالي ونقارن بالمسار الحالي.
    private func scheduleRerouteChecks() {
        rerouteTask?.cancel()
        guard let env, let trip, trip.strategy == .noStop else { return }
        rerouteTask = Task { [weak self] in
            while !Task.isCancelled {
                let cfg = await env.remoteConfig.config
                guard cfg.flags.dynamicRerouteEnabled else { return }
                try? await Task.sleep(for: .seconds(cfg.rerouteThresholds.checkIntervalSeconds))
                guard let self, !Task.isCancelled else { return }
                guard case .guiding = self.state, self.suggestion == nil else { continue }
                await self.checkReroute(cfg: cfg)
            }
        }
    }

    private func checkReroute(cfg: AppRemoteConfig) async {
        guard let env, let trip, let current = trip.selectedRoute, let dest = trip.destination else { return }
        guard let here = try? await env.location.currentLocation() else { return }
        guard let routes = try? await env.routing.computeRoutes(RouteRequest(origin: here, destination: dest, languageCode: env.languageCode)) else { return }
        // المسار الحالي المُحدَّث = الطريق الذي يشبه المختار (أقرب مسافة كلية)؛ إن لم يُوجد نستخدم الافتراضي.
        let refreshedCurrent = routes.min { abs($0.distanceMeters - current.distanceMeters) < abs($1.distanceMeters - current.distanceMeters) } ?? current
        let decider = RerouteDecider(thresholds: cfg.rerouteThresholds, scorer: TrafficRouteScorer(weights: cfg.trafficWeights))
        if let s = decider.evaluate(current: refreshedCurrent, alternatives: routes, lastSuggestionAt: lastSuggestionAt) {
            lastSuggestionAt = Date()
            suggestion = s
            env.analytics.track(Events.rerouteOffered(savingMin: s.delaySavingSeconds / 60, extraMin: s.extraDurationSeconds / 60))
        }
    }

    func acceptReroute() {
        guard let s = suggestion, let env, let trip, let dest = trip.destination else { return }
        suggestion = nil
        env.analytics.track(Events.rerouteAccepted(true))
        if var o = trip.options { o.noStop = s.alternative; trip.options = o }
        Task { try? await env.navigation.start(route: s.alternative, destination: dest, strategy: trip.strategy) }
    }

    func dismissReroute() {
        suggestion = nil
        env?.analytics.track(Events.rerouteAccepted(false))
    }

    func toggleVoice() {
        voiceOn.toggle()
        env?.navigation.setVoiceGuidance(enabled: voiceOn)
        let on = voiceOn
        Task { [self] in _ = await env?.settings.update { $0.voiceGuidance = on } }
    }

    private func onArrived() {
        guard let env, let trip else { return }
        env.analytics.track(Events.tripCompleted(trip.strategy, minutes: Int(Date().timeIntervalSince(startedAt) / 60)))
        rerouteTask?.cancel()
    }

    func stop() {
        rerouteTask?.cancel()
        listenTask?.cancel()
        env?.navigation.stop()
    }
}

/// الملاحة: خريطة Navigation SDK بملء الشاشة + بطاقة ETA + تنبيه «لقينا لك طريق أهدأ».
struct NavigationScreen: View {
    @Environment(\.appEnv) private var env
    @Environment(AppRouter.self) private var router
    @Environment(TripState.self) private var trip
    @State private var vm = NavigationViewModel()

    var body: some View {
        ZStack {
            if let env { env.maps.navigationMap() } else { BZColor.night.ignoresSafeArea() }

            VStack(spacing: 12) {
                if let e = vm.error {
                    CardContainer {
                        ErrorStateView(title: e.userTitle, message: e.userMessage, retryTitle: L("common.back")) { finish() }
                    }
                    .padding(.horizontal, 16)
                }
                if let s = vm.suggestion { RerouteBanner(suggestion: s, accept: { vm.acceptReroute() }, dismiss: { vm.dismissReroute() }).padding(.horizontal, 16).transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                bottomCard
            }
            .padding(.top, 8)
        }
        .bzHideNavBar()
        .navigationBarBackButtonHidden(true)
        .onAppear { if let env { vm.start(env: env, trip: trip) } }
        .onDisappear { vm.stop() }
        .animation(.spring(duration: 0.35), value: vm.suggestion != nil)
    }

    private var bottomCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(etaText).font(BZFont.font(22, weight: .heavy)).foregroundStyle(BZColor.green)
                Text(subText).font(BZFont.small).foregroundStyle(BZColor.mute)
            }
            Spacer()
            Button(action: vm.toggleVoice) {
                HStack(spacing: 6) {
                    Image(systemName: vm.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Text(trip.strategy.title).font(BZFont.small)
                }
                .foregroundStyle(BZColor.mute)
            }
            .accessibilityLabel(L("nav.voice"))
            Button(L("nav.end")) { finish() }
                .accessibilityIdentifier("nav.end")
                .font(BZFont.caption.weight(.bold))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(BZColor.chipBg, in: Capsule())
                .foregroundStyle(BZColor.ink)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var etaText: String {
        switch vm.state {
        case .guiding(let secs, _, _):
            if let secs { return "\(Int((Double(secs) / 60).rounded())) \(L("unit.minute"))" }
            return "\(trip.selectedRoute?.durationMinutes ?? 0) \(L("unit.minute"))"
        case .arrived: return L("nav.arrived")
        case .calculating: return L("nav.calculating")
        case .failed: return L("error.noroute.title")
        case .idle: return "\(trip.selectedRoute?.durationMinutes ?? 0) \(L("unit.minute"))"
        }
    }

    private var subText: String {
        if case .guiding(let secs, let meters, let delay) = vm.state {
            var parts: [String] = []
            if let meters { parts.append(L("unit.km.value", Double(meters) / 1000)) }
            if let secs { parts.append(L("nav.arrival", Date().addingTimeInterval(Double(secs)).formatted(date: .omitted, time: .shortened))) }
            switch delay {
            case .heavy: parts.append(L("traffic.heavy"))
            case .medium: parts.append(L("traffic.moderate"))
            case .light: parts.append(L("traffic.light"))
            case .noData: break
            }
            return parts.joined(separator: " · ")
        }
        if let r = trip.selectedRoute { return L("unit.km.value", r.distanceKm) }
        return ""
    }

    private func finish() {
        vm.stop()
        trip.options = nil
        router.popToRoot()
    }
}

struct RerouteBanner: View {
    var suggestion: RerouteSuggestion
    var accept: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("reroute.title")).font(BZFont.headline)
            HStack(spacing: 10) {
                column(L("reroute.current"), "\(suggestion.current.durationMinutes) \(L("unit.minute"))", L("reroute.delay", (suggestion.current.trafficDelaySeconds ?? 0) / 60), bg: BZColor.ink.opacity(0.1), sub: BZColor.ink)
                column(L("reroute.alternative"), "\(suggestion.alternative.durationMinutes) \(L("unit.minute"))", trafficLabel(suggestion.alternative), bg: .white, sub: BZColor.greenDark)
            }
            HStack(spacing: 10) {
                Button(action: accept) {
                    Text(L("reroute.accept")).font(BZFont.caption.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(BZColor.sky, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }
                Button(action: dismiss) {
                    Text(L("reroute.keep")).font(BZFont.caption.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(BZColor.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(BZColor.ink)
                }
            }
        }
        .padding(18)
        .background(BZColor.orange, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(BZColor.ink)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    private func trafficLabel(_ r: RouteModel) -> String {
        switch r.congestionLevel { case .light: return L("traffic.light"); case .moderate: return L("traffic.moderate"); case .heavy: return L("traffic.heavy"); case .unknown: return L("traffic.unknown") }
    }

    private func column(_ title: String, _ value: String, _ sub: String, bg: Color, sub subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(BZFont.small.weight(.semibold)).foregroundStyle(BZColor.mute)
            Text(value).font(BZFont.body.weight(.heavy))
            Text(sub).font(BZFont.small).foregroundStyle(subColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(bg, in: RoundedRectangle(cornerRadius: 12))
    }
}
