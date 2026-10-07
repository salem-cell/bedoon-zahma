import Domain
import Features
import GoogleMaps
import GoogleNavigation
import SwiftUI

/// الملاحة بـ Google Navigation SDK for iOS:
/// - يملك GMSMapView واحدًا مفعّل الملاحة (يُعرض عبر NavigationMapRepresentable).
/// - يبدأ بالمسار المختار عبر route token من Routes API (الطريقة الرسمية لتوجيه مسار محسوب مسبقًا)،
///   وإن غاب الرمز يطلب من SDK حساب المسار بنفسه.
/// - الإرشاد الصوتي والرأس العلوي (المناورة التالية والمسافة) من SDK نفسه بلغة الجهاز.
@MainActor
final class GoogleNavigationProvider: NSObject, NavigationProvider, GMSNavigatorListener {
    private(set) var state: NavigationState = .idle {
        didSet { for c in continuations.values { c.yield(state) } }
    }
    /// تيار جديد لكل مشترك (AsyncStream أحادي المستهلك) — كل شاشة ملاحة تحصل على تيار حيّ.
    private var continuations: [UUID: AsyncStream<NavigationState>.Continuation] = [:]
    var stateStream: AsyncStream<NavigationState> {
        AsyncStream { [weak self] c in
            guard let self else { c.finish(); return }
            let id = UUID()
            continuations[id] = c
            c.yield(state)
            c.onTermination = { _ in Task { @MainActor [weak self] in self?.continuations[id] = nil } }
        }
    }

    private(set) lazy var mapView: GMSMapView = {
        let options = GMSMapViewOptions()
        let map = GMSMapView(options: options)
        map.isMyLocationEnabled = true
        map.settings.compassButton = true
        map.travelMode = .driving
        return map
    }()

    private var termsAccepted = false
    private var voiceEnabled = true
    private var pollTask: Task<Void, Never>?

    /// Google تشترط عرض شروط الملاحة وقبولها مرة واحدة قبل تفعيل الملاحة.
    private func ensureTerms() async -> Bool {
        if termsAccepted { return true }
        return await withCheckedContinuation { c in
            let options = GMSNavigationTermsAndConditionsOptions(companyName: "مشوارك أسهل")
            GMSNavigationServices.showTermsAndConditionsDialogIfNeeded(with: options) { accepted in
                c.resume(returning: accepted)
            }
        }
    }

    func start(route: RouteModel, destination: Destination, strategy: RouteStrategy) async throws {
        state = .calculating
        guard await ensureTerms() else {
            state = .failed("terms_declined")
            throw AppError.unknown("navigation_terms_declined")
        }
        termsAccepted = true
        mapView.isNavigationEnabled = true
        guard let navigator = mapView.navigator else {
            state = .failed("navigator_unavailable")
            throw AppError.providerFailure(status: nil, message: "navigator unavailable")
        }
        navigator.add(self)
        navigator.timeUpdateThreshold = 10
        navigator.distanceUpdateThreshold = 50
        applyVoice(navigator)

        let waypoint: GMSNavigationWaypoint?
        switch destination {
        case .place(let id, let name, _):
            waypoint = GMSNavigationWaypoint(placeID: id, title: name)
        case .coordinate(let c, let label):
            waypoint = GMSNavigationWaypoint(location: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), title: label ?? "")
        }
        guard let waypoint else {
            state = .failed("invalid_waypoint")
            throw AppError.noRouteAvailable
        }

        let status: GMSRouteStatus = await withCheckedContinuation { c in
            if let token = route.routeToken {
                // الطريق الذي اختاره TrafficRouteScorer يُعاد بناؤه داخل SDK من الرمز، وإعادة التوجيه تحافظ على أهدافه.
                navigator.setDestinations([waypoint], routeToken: token) { c.resume(returning: $0) }
            } else {
                let options = GMSNavigationMutableRoutingOptions()
                options.routingStrategy = strategy == .shortest ? .shorter : .defaultBest
                options.alternateRoutesStrategy = .none
                navigator.setDestinations([waypoint], routingOptions: options) { c.resume(returning: $0) }
            }
        }
        guard status == .OK else {
            state = .failed("route_status_\(status.rawValue)")
            throw AppError.noRouteAvailable
        }
        navigator.isGuidanceActive = true
        mapView.cameraMode = .following
        mapView.settings.isNavigationHeaderEnabled = true
        mapView.settings.isNavigationFooterEnabled = false // لدينا بطاقتنا السفلية
        #if DEBUG
        if ProcessInfo.processInfo.environment["BZ_SIMULATE_ROUTE"] == "1" {
            mapView.locationSimulator?.simulateLocationsAlongExistingRoute()
        }
        #endif
        publishProgress(navigator)
        startPolling(navigator)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let navigator = mapView.navigator {
            navigator.isGuidanceActive = false
            navigator.clearDestinations()
            navigator.remove(self)
        }
        mapView.cameraMode = .free
        state = .idle
    }

    func setVoiceGuidance(enabled: Bool) {
        voiceEnabled = enabled
        if let n = mapView.navigator { applyVoice(n) }
    }

    private func applyVoice(_ navigator: GMSNavigator) {
        navigator.voiceGuidance = voiceEnabled ? .alertsAndGuidance : .silent
    }

    /// نقرأ المدة والمسافة المتبقية وتصنيف التأخير من SDK دوريًا (إضافةً إلى أحداث المستمع).
    private func startPolling(_ navigator: GMSNavigator) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.publishProgress(navigator)
            }
        }
    }

    private func publishProgress(_ navigator: GMSNavigator) {
        if case .arrived = state { return }
        let time = navigator.timeToNextDestination
        let dist = navigator.distanceToNextDestination
        let delay: TrafficDelayCategory
        switch navigator.delayCategoryToNextDestination {
        case .light: delay = .light
        case .medium: delay = .medium
        case .heavy: delay = .heavy
        default: delay = .noData
        }
        // قبل أول تثبيت موقع يرجع SDK القيم القصوى (CLTimeIntervalMax/CLLocationDistanceMax) — نعاملها كـ«غير متاح».
        state = .guiding(
            remainingSeconds: time >= 0 && time < Double(Int32.max) ? Int(time) : nil,
            remainingMeters: dist >= 0 && dist < Double(Int32.max) ? Int(dist) : nil,
            delay: delay
        )
    }

    // MARK: GMSNavigatorListener

    nonisolated func navigator(_ navigator: GMSNavigator, didArriveAt waypoint: GMSNavigationWaypoint) {
        Task { @MainActor in
            self.state = .arrived
            self.pollTask?.cancel()
        }
    }

    nonisolated func navigator(_ navigator: GMSNavigator, didUpdateRemainingTime time: TimeInterval) {
        Task { @MainActor in self.publishProgress(navigator) }
    }

    nonisolated func navigator(_ navigator: GMSNavigator, didUpdateRemainingDistance distance: CLLocationDistance) {
        Task { @MainActor in self.publishProgress(navigator) }
    }

    nonisolated func navigatorDidChangeRoute(_ navigator: GMSNavigator) {
        Task { @MainActor in self.publishProgress(navigator) }
    }
}

/// عرض GMSMapView الملاحي داخل SwiftUI.
struct NavigationMapRepresentable: UIViewRepresentable {
    let provider: GoogleNavigationProvider
    func makeUIView(context: Context) -> GMSMapView { provider.mapView }
    func updateUIView(_ uiView: GMSMapView, context: Context) {}
}

/// يُستخدم عندما لا يتوفر مفتاح Maps/Navigation SDK: لا يحاكي شيئًا، بل يفشل بخطأ واضح يعرضه الواجهة.
@MainActor
final class UnavailableNavigationProvider: NavigationProvider {
    private(set) var state: NavigationState = .idle
    var stateStream: AsyncStream<NavigationState> { AsyncStream { c in c.yield(.failed("navigation_sdk_unconfigured")); c.finish() } }
    func start(route: RouteModel, destination: Destination, strategy: RouteStrategy) async throws {
        state = .failed("navigation_sdk_unconfigured")
        throw AppError.providerFailure(status: nil, message: "Navigation SDK غير مفعّل (GOOGLE_MAPS_IOS_KEY مفقود)")
    }
    func stop() { state = .idle }
    func setVoiceGuidance(enabled: Bool) {}
}

/// بديل تطويري (DevMocks): يحاكي تقدّم الرحلة بلا SDK.
@MainActor
final class SimulatedNavigationProvider: NavigationProvider {
    private(set) var state: NavigationState = .idle { didSet { for c in continuations.values { c.yield(state) } } }
    private var continuations: [UUID: AsyncStream<NavigationState>.Continuation] = [:]
    var stateStream: AsyncStream<NavigationState> {
        AsyncStream { [weak self] c in
            guard let self else { c.finish(); return }
            let id = UUID()
            continuations[id] = c
            c.yield(state)
            c.onTermination = { _ in Task { @MainActor [weak self] in self?.continuations[id] = nil } }
        }
    }
    private var task: Task<Void, Never>?

    func start(route: RouteModel, destination: Destination, strategy: RouteStrategy) async throws {
        task?.cancel()
        state = .calculating
        try await Task.sleep(for: .milliseconds(600))
        state = .guiding(remainingSeconds: route.durationSeconds, remainingMeters: route.distanceMeters, delay: .medium)
        task = Task { [weak self] in
            var remaining = route.durationSeconds
            var meters = route.distanceMeters
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                remaining -= 60
                meters -= route.distanceMeters / max(route.durationMinutes, 1)
                self?.state = .guiding(remainingSeconds: max(remaining, 0), remainingMeters: max(meters, 0), delay: .light)
            }
            if !Task.isCancelled { self?.state = .arrived }
        }
    }

    func stop() { task?.cancel(); state = .idle }
    func setVoiceGuidance(enabled: Bool) {}
}
