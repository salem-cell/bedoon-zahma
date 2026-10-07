import CoreLocation
import Domain
import Foundation

/// CoreLocation بصلاحية When In Use فقط، تحديثات موفّرة للبطارية خارج الملاحة، بلا تخزين لسجل الموقع.
public final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var authContinuations: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var locationContinuations: [CheckedContinuation<Coordinate, Error>] = []
    private var streamContinuations: [UUID: AsyncStream<Coordinate>.Continuation] = [:]
    private let lock = NSLock()

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        #if os(iOS)
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .automotiveNavigation
        #endif
    }

    public var authorization: LocationAuthorization {
        get async { Self.map(manager.authorizationStatus) }
    }

    public func requestWhenInUseAuthorization() async -> LocationAuthorization {
        let current = Self.map(manager.authorizationStatus)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { c in
            lock.withLock { authContinuations.append(c) }
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation() async throws -> Coordinate {
        let status = Self.map(manager.authorizationStatus)
        switch status {
        case .denied, .restricted: throw AppError.locationPermissionDenied
        case .notDetermined:
            let s = await requestWhenInUseAuthorization()
            if s == .denied || s == .restricted { throw AppError.locationPermissionDenied }
        default: break
        }
        if let loc = manager.location, Date().timeIntervalSince(loc.timestamp) < 60 {
            return Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        }
        return try await withCheckedThrowingContinuation { c in
            lock.withLock { locationContinuations.append(c) }
            manager.requestLocation()
        }
    }

    public func locationUpdates() -> AsyncStream<Coordinate> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock { streamContinuations[id] = continuation }
            manager.startUpdatingLocation()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    self.streamContinuations[id] = nil
                    if self.streamContinuations.isEmpty { self.manager.stopUpdatingLocation() }
                }
            }
        }
    }

    // MARK: CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.map(manager.authorizationStatus)
        guard status != .notDetermined else { return }
        let waiting = lock.withLock { let w = authContinuations; authContinuations.removeAll(); return w }
        waiting.forEach { $0.resume(returning: status) }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        let (waiting, streams) = lock.withLock {
            let w = locationContinuations; locationContinuations.removeAll()
            return (w, Array(streamContinuations.values))
        }
        waiting.forEach { $0.resume(returning: c) }
        streams.forEach { $0.yield(c) }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let waiting = lock.withLock { let w = locationContinuations; locationContinuations.removeAll(); return w }
        let mapped: AppError = (error as? CLError)?.code == .denied ? .locationPermissionDenied : .locationUnavailable
        waiting.forEach { $0.resume(throwing: mapped) }
    }

    private static func map(_ s: CLAuthorizationStatus) -> LocationAuthorization {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedWhenInUse: return .whenInUse
        case .authorizedAlways: return .always
        @unknown default: return .notDetermined
        }
    }
}
