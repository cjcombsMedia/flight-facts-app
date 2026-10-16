import Foundation
import CoreLocation

/// Great-circle helpers. Everything here is pure — easy to unit test later.
enum Geo {
    static let earthRadiusM = 6_371_000.0

    static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    static func deg(_ rad: Double) -> Double { rad * 180 / .pi }

    /// Haversine distance in metres.
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
              + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earthRadiusM * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, degrees true 0–360.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (deg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Project `from` along `bearing` for `distance` metres.
    static func destination(from origin: CLLocationCoordinate2D,
                            bearing bearingDeg: Double,
                            distance meters: Double) -> CLLocationCoordinate2D {
        let d = meters / earthRadiusM
        let br = rad(bearingDeg)
        let lat1 = rad(origin.latitude), lon1 = rad(origin.longitude)
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(br))
        let lon2 = lon1 + atan2(sin(br) * sin(d) * cos(lat1),
                                cos(d) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(
            latitude: deg(lat2),
            longitude: (deg(lon2) + 540).truncatingRemainder(dividingBy: 360) - 180
        )
    }

    /// Interpolate along the great circle between two points. `f` in 0...1.
    static func interpolate(_ a: CLLocationCoordinate2D,
                            _ b: CLLocationCoordinate2D,
                            _ f: Double) -> CLLocationCoordinate2D {
        let d = distance(a, b) / earthRadiusM
        guard d > 1e-9 else { return a }
        let A = sin((1 - f) * d) / sin(d)
        let B = sin(f * d) / sin(d)
        let lat1 = rad(a.latitude), lon1 = rad(a.longitude)
        let lat2 = rad(b.latitude), lon2 = rad(b.longitude)
        let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
        let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
        let z = A * sin(lat1) + B * sin(lat2)
        return CLLocationCoordinate2D(latitude: deg(atan2(z, sqrt(x * x + y * y))),
                                      longitude: deg(atan2(y, x)))
    }

    /// Smallest signed angle from `a` to `b`, in -180...180.
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Relative bearing expressed as a clock face: 12 dead ahead, 3 off the right wing.
    static func clockPosition(course: Double, bearingToTarget: Double) -> Int {
        let rel = (angleDelta(course, bearingToTarget) + 360).truncatingRemainder(dividingBy: 360)
        let hour = Int((rel / 30).rounded()) % 12
        return hour == 0 ? 12 : hour
    }

    static func side(course: Double, bearingToTarget: Double) -> POISighting.Side {
        let d = angleDelta(course, bearingToTarget)
        if abs(d) <= 20 { return .ahead }
        if abs(d) >= 160 { return .behind }
        return d > 0 ? .right : .left
    }

    /// Clock and side together, kept consistent with each other.
    ///
    /// The "ahead" cone is ±20° but clock positions bucket every 30°, so the two
    /// disagree at the edges — you'd get "straight ahead · 1 o'clock". Anything
    /// in the ahead cone is pinned to 12; anything behind, to 6.
    static func relativePosition(course: Double,
                                 bearingToTarget: Double) -> (clock: Int, side: POISighting.Side) {
        let s = side(course: course, bearingToTarget: bearingToTarget)
        switch s {
        case .ahead:  return (12, s)
        case .behind: return (6, s)
        default:      return (clockPosition(course: course, bearingToTarget: bearingToTarget), s)
        }
    }

    /// How far the horizon is at a given altitude, metres.
    /// Includes the standard 1.07 refraction fudge — at cruise this is ~350 km.
    static func horizonDistance(altitudeM: Double) -> Double {
        guard altitudeM > 0 else { return 0 }
        return sqrt(2 * earthRadiusM * altitudeM * 1.07)
    }
}

// MARK: - Unit formatting

enum Units {
    static func km(_ meters: Double) -> String {
        meters < 1000
            ? "\(Int(meters)) m"
            : String(format: "%.0f km", meters / 1000)
    }

    static func miles(_ meters: Double) -> String {
        String(format: "%.0f mi", meters / 1609.344)
    }

    static func feet(_ meters: Double) -> String {
        let ft = meters * 3.280839895
        return ft.formatted(.number.precision(.fractionLength(0))) + " ft"
    }

    static func knots(_ mps: Double) -> String {
        String(format: "%.0f kt", mps * 1.943844)
    }

    static func mph(_ mps: Double) -> String {
        String(format: "%.0f mph", mps * 2.236936)
    }

    static func fpm(_ mps: Double) -> String {
        let v = mps * 196.850394
        return String(format: "%+.0f fpm", v)
    }

    /// Speed of sound falls with temperature; ~295 m/s at typical cruise altitude.
    static func mach(_ mps: Double, altitudeM: Double) -> String {
        let a = altitudeM > 11_000 ? 295.0 : 340.3 - (altitudeM / 11_000) * 45.3
        return String(format: "Mach %.2f", mps / a)
    }

    static func compass(_ deg: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360)
                     .truncatingRemainder(dividingBy: 360) / 22.5).rounded()) % 16
        return points[i]
    }
}
