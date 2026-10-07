import Foundation

/// أخطاء المنتج الموحّدة — كل حالة لها UX واضح في الواجهة.
public enum AppError: Error, Equatable, Sendable {
    case locationUnavailable
    case locationPermissionDenied
    case offline
    case providerFailure(status: Int?, message: String?)
    case rateLimited(retryAfterSeconds: Int?)
    case timeout
    case noPlacesFound
    case noRouteAvailable
    case trafficDataUnavailable
    case photoUnavailable
    case placeTemporarilyClosed
    case cancelled
    case decoding(String)
    case unknown(String)

    public var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .rateLimited, .providerFailure: return true
        default: return false
        }
    }
}
