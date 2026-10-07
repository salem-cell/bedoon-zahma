import AVFoundation
import CoreLocation
import Domain
import Features
import Foundation
import TrafficEngine

/// إرشاد منعطف‑بمنعطف ذاتي فوق MapKit (بلا SDK مدفوع):
/// - يتتبع الموقع على مسار TomTom، يحسب المتبقي من المسافة والوقت (بنسبة المرور الحالي)،
/// - يعلن المناورة التالية صوتيًا بالعربية (AVSpeechSynthesizer) على مسافات 400/120/25 م،
/// - يكتشف الخروج عن المسار (>60 م لثلاث قراءات) ويعيد الحساب عبر RoutingProvider بنفس الاستراتيجية.
@MainActor @Observable
final class GuidanceNavigationProvider: NavigationProvider {
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

    private(set) var activeRoute: RouteModel?
    private(set) var currentLocation: Coordinate?
    private(set) var strategy: RouteStrategy = .noStop
    var destinationCoordinate: Coordinate? { destination?.coordinate ?? points.last }

    private let routing: RoutingProvider
    private let makeSelector: @MainActor () async -> RouteSelector
    private let feed = LocationFeed()
    private let speech = AVSpeechSynthesizer()
    private var destination: Destination?
    private var points: [Coordinate] = []
    private var cumulative: [Double] = []
    private var voiceOn = true
    private var announced: Set<String> = []
    private var offRouteStreak = 0
    private var rerouting = false
    private var lastRerouteAt: Date?

    init(routing: RoutingProvider, makeSelector: @escaping @MainActor () async -> RouteSelector) {
        self.routing = routing
        self.makeSelector = makeSelector
        feed.onLocation = { [weak self] loc in self?.handle(loc) }
    }

    func start(route: RouteModel, destination: Destination, strategy: RouteStrategy) async throws {
        self.destination = destination
        self.strategy = strategy
        apply(route: route)
        announced.removeAll()
        offRouteStreak = 0
        state = .calculating
        let auth = await feed.ensureAuthorization()
        guard auth else { state = .failed("location_denied"); throw AppError.locationPermissionDenied }
        feed.start()
        state = .guiding(remainingSeconds: route.durationSeconds, remainingMeters: route.distanceMeters, delay: delayCategory(route), instruction: firstInstruction())
        speak(L("strategy.\(strategy == .noStop ? "nostop" : strategy.rawValue)") + " — " + (firstInstruction()?.text ?? ""))
    }

    func stop() {
        feed.stop()
        speech.stopSpeaking(at: .immediate)
        activeRoute = nil
        points = []
        cumulative = []
        state = .idle
    }

    func setVoiceGuidance(enabled: Bool) {
        voiceOn = enabled
        if !enabled { speech.stopSpeaking(at: .immediate) }
    }

    // MARK: - Core

    private func apply(route: RouteModel) {
        activeRoute = route
        points = Polyline.decode(route.encodedPolyline)
        cumulative = Polyline.cumulativeDistances(points)
    }

    private func handle(_ loc: CLLocation) {
        guard let route = activeRoute, points.count >= 2, let total = cumulative.last, total > 0 else { return }
        let here = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        currentLocation = here
        if case .arrived = state { return }

        let (along, crossTrack) = project(here)
        let remainingMeters = max(total - along, 0)
        let remainingSeconds = Int((Double(route.durationSeconds) * remainingMeters / total).rounded())

        // الوصول
        if remainingMeters < 30 || (points.last.map { here.distanceMeters(to: $0) } ?? 1e9) < 30 {
            state = .arrived
            speak(L("nav.arrive.voice"))
            feed.stop()
            return
        }

        // الخروج عن المسار
        if crossTrack > 60, loc.horizontalAccuracy < 50 {
            offRouteStreak += 1
            if offRouteStreak >= 3 { reroute(from: here) }
        } else {
            offRouteStreak = 0
        }

        let instruction = nextInstruction(along: along)
        state = .guiding(remainingSeconds: remainingSeconds, remainingMeters: Int(remainingMeters), delay: delayCategory(route), instruction: instruction)
        announceIfNeeded(instruction)
    }

    /// إسقاط النقطة على أقرب قطعة من المسار: (المسافة المقطوعة على المسار، البعد العرضي عن المسار) بالأمتار.
    private func project(_ p: Coordinate) -> (along: Double, crossTrack: Double) {
        let cosLat = cos(p.latitude * .pi / 180)
        func xy(_ c: Coordinate) -> (Double, Double) { ((c.longitude - p.longitude) * 111_320 * cosLat, (c.latitude - p.latitude) * 110_540) }
        var best = (along: 0.0, cross: Double.greatestFiniteMagnitude)
        for i in 0..<(points.count - 1) {
            let (ax, ay) = xy(points[i]), (bx, by) = xy(points[i + 1])
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, (-(ax * dx + ay * dy)) / len2)) : 0
            let px = ax + t * dx, py = ay + t * dy
            let dist = (px * px + py * py).squareRoot()
            if dist < best.cross {
                best = (cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), dist)
            }
        }
        return (best.along, best.cross)
    }

    private func nextInstruction(along: Double) -> GuidanceInstruction? {
        guard let steps = activeRoute?.steps else { return nil }
        for s in steps {
            guard let offset = s.routeOffsetMeters, let text = s.instruction, s.maneuver != .depart else { continue }
            if Double(offset) >= along - 15 {
                return GuidanceInstruction(text: text, maneuver: s.maneuver, distanceMeters: max(offset - Int(along), 0), streetName: s.streetName)
            }
        }
        return nil
    }

    private func firstInstruction() -> GuidanceInstruction? { nextInstruction(along: 0) }

    private func announceIfNeeded(_ ins: GuidanceInstruction?) {
        guard let ins, voiceOn else { return }
        let key = "\(ins.text)|\(ins.distanceMeters > 400 ? "far" : ins.distanceMeters > 120 ? "mid" : "near")"
        guard !announced.contains(key) else { return }
        if ins.distanceMeters <= 450 && ins.distanceMeters > 380 || ins.distanceMeters <= 140 && ins.distanceMeters > 100 || ins.distanceMeters <= 30 {
            announced.insert(key)
            let dist = ins.distanceMeters > 60 ? "بعد \(Int((Double(ins.distanceMeters) / 50).rounded()) * 50) متر، " : ""
            speak(dist + ins.text)
        }
    }

    private func reroute(from here: Coordinate) {
        guard !rerouting, let destination else { return }
        if let last = lastRerouteAt, Date().timeIntervalSince(last) < 20 { return }
        rerouting = true
        lastRerouteAt = Date()
        speak(L("nav.offroute"))
        Task { [weak self] in
            guard let self else { return }
            defer { self.rerouting = false; self.offRouteStreak = 0 }
            do {
                let routes = try await self.routing.computeRoutes(RouteRequest(origin: here, destination: destination, languageCode: Locale.current.language.languageCode?.identifier.hasPrefix("ar") == true ? "ar" : "en"))
                let options = await self.makeSelector().select(from: routes)
                if let r = options.route(for: self.strategy) ?? routes.first {
                    self.apply(route: r)
                    self.announced.removeAll()
                }
            } catch {
                // نبقى على المسار القديم ونعيد المحاولة مع القراءة التالية خارج المسار.
            }
        }
    }

    private func delayCategory(_ r: RouteModel) -> TrafficDelayCategory {
        switch r.congestionLevel { case .light: return .light; case .moderate: return .medium; case .heavy: return .heavy; case .unknown: return .noData }
    }

    private func speak(_ text: String) {
        guard voiceOn, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier.hasPrefix("ar") == true ? "ar-SA" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        speech.speak(u)
    }
}

/// غلاف CLLocationManager دقيق للملاحة (يعمل في الخلفية مع إذن «أثناء الاستخدام» وبوضع location في UIBackgroundModes).
final class LocationFeed: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocation) -> Void)?
    private var authContinuation: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    func ensureAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                authContinuation = c
                manager.requestWhenInUseAuthorization()
            }
        default: return false
        }
    }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let c = authContinuation else { return }
        authContinuation = nil
        c.resume(returning: manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 100 else { return }
        onLocation?(l)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
