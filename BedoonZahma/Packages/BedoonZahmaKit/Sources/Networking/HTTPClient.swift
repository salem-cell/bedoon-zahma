import Domain
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux/Windows: URLSession تعيش في وحدة منفصلة
#endif

/// مراقب الاستخدام: عدد الطلبات والأخطاء لكل مسار — للتكلفة والمراقبة.
public actor APIUsageMonitor {
    public struct Counter: Sendable, Codable { public var requests = 0; public var errors = 0; public var totalLatencyMs = 0 }
    private var counters: [String: Counter] = [:]

    public init() {}

    public func record(endpoint: String, latencyMs: Int, failed: Bool) {
        var c = counters[endpoint, default: Counter()]
        c.requests += 1
        c.totalLatencyMs += latencyMs
        if failed { c.errors += 1 }
        counters[endpoint] = c
    }

    public func snapshot() -> [String: Counter] { counters }
}

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public init(maxRetries: Int = 2, baseDelay: TimeInterval = 0.6) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }
}

/// عميل HTTP بسيط مع: إلغاء، مهلة، إعادة محاولة بتراجع أسي لـ 429/5xx/المهلة، وتحويل الأخطاء إلى AppError.
public final class HTTPClient: Sendable {
    private let session: URLSession
    private let retry: RetryPolicy
    private let monitor: APIUsageMonitor?

    public init(session: URLSession? = nil, retry: RetryPolicy = .init(), monitor: APIUsageMonitor? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 30
            #if canImport(Darwin)
            cfg.waitsForConnectivity = false
            #endif
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData // لا نخزّن استجابات Google على القرص
            cfg.urlCache = nil
            self.session = URLSession(configuration: cfg)
        }
        self.retry = retry
        self.monitor = monitor
    }

    public func send(_ request: URLRequest, endpoint: String) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let start = Date()
            do {
                let (data, response) = try await session.data(for: request)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                guard let http = response as? HTTPURLResponse else { throw AppError.unknown("non-http response") }
                if (200..<300).contains(http.statusCode) || http.statusCode == 304 {
                    await monitor?.record(endpoint: endpoint, latencyMs: ms, failed: false)
                    return (data, http)
                }
                await monitor?.record(endpoint: endpoint, latencyMs: ms, failed: true)
                let err = Self.mapStatus(http, data: data)
                if err.isRetryable, attempt < retry.maxRetries, http.statusCode == 429 || http.statusCode >= 500 {
                    attempt += 1
                    try await Task.sleep(for: .seconds(retry.baseDelay * pow(2, Double(attempt - 1))))
                    continue
                }
                throw err
            } catch let e as AppError {
                throw e
            } catch is CancellationError {
                throw AppError.cancelled
            } catch let e as URLError {
                await monitor?.record(endpoint: endpoint, latencyMs: Int(Date().timeIntervalSince(start) * 1000), failed: true)
                let mapped: AppError
                switch e.code {
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: mapped = .offline
                case .timedOut: mapped = .timeout
                case .cancelled: mapped = .cancelled
                default: mapped = .providerFailure(status: nil, message: e.localizedDescription)
                }
                if mapped.isRetryable, mapped != .offline, attempt < retry.maxRetries {
                    attempt += 1
                    try await Task.sleep(for: .seconds(retry.baseDelay * pow(2, Double(attempt - 1))))
                    continue
                }
                throw mapped
            }
        }
    }

    public func json<T: Decodable>(_ request: URLRequest, endpoint: String, as type: T.Type) async throws -> T {
        let (data, _) = try await send(request, endpoint: endpoint)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding("\(endpoint): \(error)")
        }
    }

    private static func mapStatus(_ http: HTTPURLResponse, data: Data) -> AppError {
        let message = String(data: data.prefix(400), encoding: .utf8)
        switch http.statusCode {
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            return .rateLimited(retryAfterSeconds: retryAfter)
        case 404: return .providerFailure(status: 404, message: message)
        default: return .providerFailure(status: http.statusCode, message: message)
        }
    }
}

public extension URLRequest {
    static func json(url: URL, method: String = "POST", body: (any Encodable)? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return r
    }
}

struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeFn = value.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
