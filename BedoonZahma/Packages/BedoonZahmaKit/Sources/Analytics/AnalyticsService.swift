import BackendClient
import Domain
import Foundation

/// أسماء الأحداث المتفق عليها — بلا بيانات شخصية ولا إحداثيات خام.
public enum Events {
    public static func destinationSearched(hasResults: Bool) -> AnalyticsEvent { .init(name: "destination_searched", params: ["has_results": hasResults.description]) }
    public static func routeOptionsShown(noStopMin: Int?, fastestMin: Int?, shortestMin: Int?, noStopKm: Double?, fastestKm: Double?, shortestKm: Double?) -> AnalyticsEvent {
        var p: [String: String] = [:]
        if let v = noStopMin { p["no_stop_min"] = String(v) }
        if let v = fastestMin { p["fastest_min"] = String(v) }
        if let v = shortestMin { p["shortest_min"] = String(v) }
        if let v = noStopKm { p["no_stop_km"] = String(format: "%.1f", v) }
        if let v = fastestKm { p["fastest_km"] = String(format: "%.1f", v) }
        if let v = shortestKm { p["shortest_km"] = String(format: "%.1f", v) }
        return .init(name: "route_options_shown", params: p)
    }
    /// extra_km / extra_min: كم مسافة ووقت إضافيين قبل المستخدم مقابل الانسيابية (نسبةً لأسرع طريق).
    public static func routeOptionSelected(_ s: RouteStrategy, extraKm: Double, extraMin: Int) -> AnalyticsEvent {
        .init(name: "route_option_selected", params: ["strategy": s.rawValue, "extra_km": String(format: "%.1f", extraKm), "extra_min": String(extraMin)])
    }
    public static func navigationStarted(_ s: RouteStrategy, fromPlace: Bool) -> AnalyticsEvent { .init(name: "navigation_started", params: ["strategy": s.rawValue, "from_place": fromPlace.description]) }
    public static func rerouteOffered(savingMin: Int, extraMin: Int) -> AnalyticsEvent { .init(name: "reroute_offered", params: ["saving_min": String(savingMin), "extra_min": String(extraMin)]) }
    public static func rerouteAccepted(_ accepted: Bool) -> AnalyticsEvent { .init(name: accepted ? "reroute_accepted" : "reroute_dismissed") }
    public static func tripCompleted(_ s: RouteStrategy, minutes: Int) -> AnalyticsEvent { .init(name: "trip_completed", params: ["strategy": s.rawValue, "minutes": String(minutes)]) }

    public static func nearbyOpened(kind: String) -> AnalyticsEvent { .init(name: kind == "cafes" ? "cafe_opened" : (kind == "restaurants" ? "restaurant_opened" : "nearby_opened"), params: ["kind": kind]) }
    public static func nearbyTimeFilterSelected(_ f: TravelTimeFilter) -> AnalyticsEvent { .init(name: "nearby_time_filter_selected", params: ["minutes": String(f.rawValue)]) }
    public static func placeSortSelected(_ s: PlaceSort) -> AnalyticsEvent { .init(name: "place_sort_selected", params: ["sort": s.rawValue]) }
    public static func placeOpened(kind: String) -> AnalyticsEvent { .init(name: "place_opened", params: ["kind": kind]) }
    public static func placeSaved(kind: String, saved: Bool) -> AnalyticsEvent { .init(name: "place_saved", params: ["kind": kind, "saved": saved.description]) }
    public static func placeNavigationStarted(kind: String) -> AnalyticsEvent { .init(name: "place_navigation_started", params: ["kind": kind]) }
}

/// يجمّع الأحداث ويرسلها دفعات إلى الخادم (كل 30 ثانية أو 20 حدثًا). يحترم إيقاف التحليلات من المستخدم.
public actor AnalyticsService: AnalyticsClient {
    private let api: BackendAPI?
    private var queue: [AnalyticsEvent] = []
    private var flushTask: Task<Void, Never>?
    private let batchSize = 20
    private let interval: Duration = .seconds(30)
    private var enabled = true

    public init(api: BackendAPI?) {
        self.api = api
    }

    public func setEnabled(_ on: Bool) { enabled = on; if !on { queue.removeAll() } }

    nonisolated public func track(_ event: AnalyticsEvent) {
        Task { await self.enqueue(event) }
    }

    private func enqueue(_ e: AnalyticsEvent) {
        guard enabled else { return }
        queue.append(e)
        if queue.count >= batchSize { Task { await flush() } } else { scheduleFlush() }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [interval] in
            try? await Task.sleep(for: interval)
            await self.flush()
        }
    }

    public func flush() async {
        flushTask?.cancel()
        flushTask = nil
        guard let api, !queue.isEmpty else { return }
        let batch = queue
        queue.removeAll()
        do { try await api.sendAnalytics(batch) } catch {
            // عند الفشل نحتفظ بالدفعة (بحد أقصى 200) ونحاول لاحقًا.
            queue = Array((batch + queue).suffix(200))
            scheduleFlush()
        }
    }
}
