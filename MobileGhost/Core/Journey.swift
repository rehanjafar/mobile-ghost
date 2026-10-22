// Mobile Ghost additions, 2026-10-22. AGPL-3.0.
import Foundation

struct GeoPoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    func distance(to other: Self) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude-latitude)*r/2),2) + cos(latitude*r)*cos(other.latitude*r)*pow(sin((other.longitude-longitude)*r/2),2)
        return 6_371_000 * 2 * atan2(sqrt(min(1,a)),sqrt(max(0,1-a)))
    }
    func interpolated(to other: Self, fraction: Double) -> Self {
        let f = min(1,max(0,fraction))
        var delta = other.longitude-longitude
        if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
        var lon = longitude + delta*f
        if lon > 180 { lon -= 360 }; if lon < -180 { lon += 360 }
        return Self(latitude: latitude+(other.latitude-latitude)*f, longitude: lon)
    }
}
struct JourneyStop: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var point: GeoPoint
    var waitSeconds: Double = 0
    var departureSpeed: Double = 0 // zero inherits the current speed
}
struct JourneyLeg: Codable {
    var points: [GeoPoint]
    var distance: Double { zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to:$1.1) } }
    func position(at meters: Double) -> GeoPoint {
        guard let first = points.first else { return GeoPoint(latitude:0,longitude:0) }
        var remaining = max(0,meters)
        for (a,b) in zip(points,points.dropFirst()) {
            let d = a.distance(to:b)
            if d > 0 && remaining < d { return a.interpolated(to:b, fraction:remaining/d) }
            remaining -= d
        }
        return points.last ?? first
    }
}
struct JourneyPlan: Codable {
    var stops: [JourneyStop]
    var legs: [JourneyLeg]
    var mode: String
    var isValid: Bool {
        stops.count >= 2 && legs.count == stops.count-1 && stops.allSatisfy { $0.point.isValid && (0...86400).contains($0.waitSeconds) && ($0.departureSpeed == 0 || (1...160).contains($0.departureSpeed)) } && legs.allSatisfy { $0.points.count >= 2 && $0.points.allSatisfy(\.isValid) }
    }
    var distance: Double { legs.reduce(0) { $0+$1.distance } }
}
/// Value semantics let the controller commit progress only after the phone acknowledges it.
struct JourneyCursor {
    var plan: JourneyPlan
    var legIndex = 0
    var meters = 0.0
    var waiting = 0.0
    var speed: Double
    var finished = false
    init(plan: JourneyPlan, speed: Double) {
        self.plan = plan; self.speed = speed
        waiting = plan.stops.first?.waitSeconds ?? 0
        if let s = plan.stops.first?.departureSpeed, s > 0 { self.speed = s }
    }
    var point: GeoPoint { finished ? plan.stops.last!.point : plan.legs[legIndex].position(at:meters) }
    mutating func advance(seconds: Double) {
        guard plan.isValid, !finished, seconds.isFinite, seconds > 0, (1...160).contains(speed) else { return }
        var remaining = seconds
        while remaining > 0 && !finished {
            if waiting > 0 { let consumed = min(waiting,remaining); waiting -= consumed; remaining -= consumed; if remaining <= 0 { break } }
            let leg = plan.legs[legIndex]
            let time = max(0,leg.distance-meters)/(speed/3.6)
            if time > remaining { meters += remaining*speed/3.6; return }
            remaining -= time
            legIndex += 1; meters = 0
            if legIndex == plan.legs.count { finished = true; break }
            waiting = plan.stops[legIndex].waitSeconds
            if plan.stops[legIndex].departureSpeed > 0 { speed = plan.stops[legIndex].departureSpeed }
        }
    }
}

/// Switching apps is not an interruption. A gap in actual execution is.
enum BackgroundExecutionPolicy {
    static func mayTick(foreground: Bool, locationActive: Bool) -> Bool {
        foreground || locationActive
    }
    static func interrupted(elapsed: TimeInterval) -> Bool {
        !elapsed.isFinite || elapsed < 0 || elapsed > 3
    }
}
