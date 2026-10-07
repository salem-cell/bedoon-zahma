import Domain
import Foundation

/// يشتق مقاييس الاحتكاك من بيانات Google المتاحة فقط. لا يخترع قيمًا.
public enum RouteMetricsDeriver {
    public static func enrich(_ route: RouteModel) -> RouteModel {
        var r = route

        if let s = r.staticDurationSeconds {
            r.trafficDelaySeconds = max(r.durationSeconds - s, 0)
        }

        if let intervals = r.speedReadingIntervals, !intervals.isEmpty {
            let points = Polyline.decode(r.encodedPolyline)
            let cum = Polyline.cumulativeDistances(points)
            var slow = 0.0, jam = 0.0, jamSegments = 0
            for iv in intervals {
                guard !cum.isEmpty else { break }
                let a = min(max(iv.startPolylinePointIndex, 0), cum.count - 1)
                let b = min(max(iv.endPolylinePointIndex, 0), cum.count - 1)
                let len = max(cum[b] - cum[a], 0)
                switch iv.speed {
                case .slow: slow += len
                case .trafficJam:
                    jam += len
                    jamSegments += 1
                case .normal: break
                }
            }
            r.slowTrafficDistanceMeters = Int(slow.rounded())
            r.trafficJamDistanceMeters = Int(jam.rounded())
            r.trafficJamSegmentCount = jamSegments
        }

        if !r.steps.isEmpty {
            r.turnCount = r.steps.filter { $0.maneuver?.isTurn == true }.count
            r.uTurnCount = r.steps.filter { $0.maneuver?.isUTurn == true }.count
        }

        return r
    }

    public static func enrich(_ routes: [RouteModel]) -> [RouteModel] { routes.map(enrich) }
}
