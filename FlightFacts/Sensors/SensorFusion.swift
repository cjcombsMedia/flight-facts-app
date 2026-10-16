import Foundation
import CoreLocation

/// A thread-safe copy of the motion sensors at one instant.
struct MotionSnapshot {
    var relativeAltitude: Double = 0
    /// kPa, 0 when there's no barometer.
    var pressure: Double = 0
    var hasBarometer = false
    var accelRMS: Double = 0
    var accelPeak: Double = 0
    var gyro: Double = 0
    var count: Int = 0
}

/// Turns raw CoreLocation fixes into trustworthy `FlightSample`s.
///
/// Pure value type with no CoreLocation manager attached, so every rule here
/// is unit-testable. The rules exist because an aircraft cabin is a bad GPS
/// environment and CoreLocation is honest about it in ways that are easy to
/// mishandle:
///
/// - **Fixes stop.** The cabin attenuates the signal, and toggling airplane mode
///   drops assisted-GPS help. The last fix is still sitting in
///   `CLLocationManager.location`, and re-emitting it with a fresh timestamp
///   freezes every reading while pretending to be live. Instead, past
///   `staleAfter` we dead-reckon along the last good course and flag the sample
///   `est`, so downstream code knows not to make decisions on it.
/// - **Speed, course and altitude can each be invalid on their own.** `-1` speed
///   is "unknown", not "stopped"; `-1` course is "unknown", not "due north";
///   negative `verticalAccuracy` means the altitude is junk. Each is handled
///   separately rather than trusting the whole fix or none of it.
/// - **Course is noise when you're slow.** At the gate the GPS course swings
///   through 360° from position jitter alone, which is what spun the map. Course
///   only updates above `courseMinSpeed`.
struct SensorFusion {

    static let staleAfter: TimeInterval = 6
    static let maxDeadReckon: TimeInterval = 20 * 60
    static let courseMinSpeed: Double = 4          // m/s, ~8 kt
    static let worstUsableAccuracy: Double = 500   // m
    /// Anything implying more than this between fixes is a bad fix, not travel.
    static let maxPlausibleSpeed: Double = 350     // m/s

    private(set) var startedAt: Date
    private var odometer: Double = 0
    private var lastGood: CLLocation?
    private var lastValidSpeed: Double = 0
    private var lastValidCourse: Double?
    private var lastValidAlt: Double?
    private var altHistory: [(t: Date, alt: Double)] = []
    private var baroDatum: Double?

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    /// Last course worth trusting, if we've ever had one.
    var course: Double? { lastValidCourse }

    /// Fuses the most recent fix (which may be stale) with motion data.
    /// Returns nil until the first usable fix arrives.
    mutating func sample(location: CLLocation?,
                         motion: MotionSnapshot,
                         battery: Int?,
                         now: Date) -> FlightSample? {

        if baroDatum == nil, motion.hasBarometer { baroDatum = motion.relativeAltitude }

        let usable: CLLocation? = location.flatMap { loc in
            let accurate = loc.horizontalAccuracy >= 0
                && loc.horizontalAccuracy <= Self.worstUsableAccuracy
            let fresh = now.timeIntervalSince(loc.timestamp) <= Self.staleAfter
            return accurate && fresh ? loc : nil
        }

        let coord: CLLocationCoordinate2D
        let speed: Double
        let alt: Double
        let vRate: Double
        let hAcc: Double
        let vAcc: Double
        var estimated = false

        if let loc = usable {
            let isNewFix = lastGood.map { loc.timestamp > $0.timestamp } ?? true

            // Speed: trust CoreLocation's if valid, otherwise derive it.
            if loc.speed >= 0, loc.speedAccuracy < 0 || loc.speedAccuracy <= 25 {
                speed = loc.speed
            } else if let prev = lastGood, isNewFix,
                      loc.timestamp.timeIntervalSince(prev.timestamp) >= 0.5 {
                let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                let derived = loc.distance(from: prev) / dt
                speed = derived <= Self.maxPlausibleSpeed ? derived : lastValidSpeed
            } else {
                speed = lastValidSpeed
            }
            lastValidSpeed = speed

            // Course: only meaningful when actually moving.
            if speed >= Self.courseMinSpeed {
                if loc.course >= 0, loc.courseAccuracy < 0 || loc.courseAccuracy <= 30 {
                    lastValidCourse = loc.course
                } else if let prev = lastGood, isNewFix, loc.distance(from: prev) > 30 {
                    lastValidCourse = Geo.bearing(from: prev.coordinate, to: loc.coordinate)
                }
            }

            // Altitude: hold the last good value rather than accept junk.
            if loc.verticalAccuracy > 0, loc.verticalAccuracy < 200 {
                lastValidAlt = loc.altitude
                if isNewFix { altHistory.append((loc.timestamp, loc.altitude)) }
            }
            alt = lastValidAlt ?? loc.altitude

            // Vertical rate from the last 12 s of *fixes*, keyed on fix time so
            // a gap never gets bridged by a straight line.
            if let newest = altHistory.last?.t {
                altHistory.removeAll { newest.timeIntervalSince($0.t) > 12 }
            }
            vRate = Self.slope(altHistory)

            // Odometer: only real movement, never jitter or teleports.
            if let prev = lastGood, isNewFix {
                let step = loc.distance(from: prev)
                let dt = max(0.5, loc.timestamp.timeIntervalSince(prev.timestamp))
                let plausible = step / dt <= Self.maxPlausibleSpeed
                // Two fixes each within ±hAcc of the truth can sit 2×hAcc apart
                // while you haven't moved at all, so that's the jitter floor.
                let moving = speed >= 1 || step > max(2 * loc.horizontalAccuracy, 10)
                if plausible && moving { odometer += step }
            }
            if isNewFix { lastGood = loc }

            coord = loc.coordinate
            hAcc = loc.horizontalAccuracy
            vAcc = loc.verticalAccuracy
        } else {
            // No usable fix right now. Without any history there's nothing to say.
            guard let base = lastGood else { return nil }
            estimated = true

            let gap = now.timeIntervalSince(base.timestamp)
            // Dead-reckon only at flying speed with a known course, and only for
            // so long — after 20 minutes the estimate is worse than useless.
            if lastValidSpeed > 30, let course = lastValidCourse, gap <= Self.maxDeadReckon {
                coord = Geo.destination(from: base.coordinate, bearing: course,
                                        distance: lastValidSpeed * gap)
            } else {
                coord = base.coordinate
            }
            speed = lastValidSpeed
            alt = lastValidAlt ?? base.altitude
            // No GPS altitude trend to report. The detector uses the barometer instead.
            vRate = 0
            hAcc = -1
            vAcc = -1
            altHistory.removeAll()
        }

        let odo = estimated
            ? odometer + (lastGood.map { lastValidSpeed * min(now.timeIntervalSince($0.timestamp), Self.maxDeadReckon) } ?? 0)
            : odometer

        return FlightSample(
            t: now,
            lat: coord.latitude,
            lon: coord.longitude,
            alt: alt,
            rawAlt: usable?.altitude,
            hAcc: hAcc,
            vAcc: vAcc,
            spd: speed,
            course: lastValidCourse ?? 0,
            asc: max(0, vRate),
            dsc: max(0, -vRate),
            odo: odo,
            elapsed: now.timeIntervalSince(startedAt),
            baro: baroDatum.map { motion.relativeAltitude - $0 },
            pressure: motion.pressure > 0 ? motion.pressure : nil,
            gyro: motion.gyro,
            rms: motion.accelRMS,
            peak: motion.accelPeak,
            n: motion.count,
            hr: nil,
            rrMs: nil,
            tank: battery,
            est: estimated ? true : nil
        )
    }

    /// Least-squares slope of altitude over time, m/s.
    static func slope(_ pts: [(t: Date, alt: Double)]) -> Double {
        guard pts.count >= 3, let t0 = pts.first?.t else { return 0 }
        let xs = pts.map { $0.t.timeIntervalSince(t0) }
        let ys = pts.map(\.alt)
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in 0..<pts.count {
            num += (xs[i] - mx) * (ys[i] - my)
            den += (xs[i] - mx) * (xs[i] - mx)
        }
        return den > 0.001 ? num / den : 0
    }
}
