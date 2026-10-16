import Foundation
import CoreLocation

/// Plays back a recorded `TrackSessionFile` — including RRCC exports — through
/// the same pipeline a live flight uses.
final class ReplaySource: SampleSource {

    var onSample: ((FlightSample) -> Void)?
    var isLive: Bool { false }

    private let samples: [FlightSample]
    private var index = 0
    private var timer: Timer?

    /// Playback multiplier. 1 = real time, 60 = a minute a second.
    var speed: Double

    init(samples: [FlightSample], speed: Double = 1) {
        self.samples = samples.sorted { $0.t < $1.t }
        self.speed = speed
    }

    /// Loads a `TrackSession-*.json` file from the app bundle or a file URL.
    convenience init?(url: URL, speed: Double = 1) {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder.trackSession.decode(TrackSessionFile.self, from: data)
        else { return nil }
        self.init(samples: file.samples, speed: speed)
    }

    func start() {
        index = 0
        scheduleNext()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNext() {
        guard index < samples.count else { stop(); return }

        let sample = samples[index]
        onSample?(sample)
        index += 1

        guard index < samples.count else { stop(); return }
        let gap = samples[index].t.timeIntervalSince(sample.t)
        let delay = max(0.02, gap / max(0.1, speed))

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.scheduleNext()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

/// Generates a complete, physically plausible flight on the fly — gate, taxi,
/// takeoff roll, climb, cruise, descent, approach, rollout — along a named route.
///
/// Samples are computed lazily from simulated elapsed time, so a five-hour
/// flight costs nothing to "load" and the speed multiplier is just a scale
/// factor on the clock.
final class SyntheticFlightSource: SampleSource {

    var onSample: ((FlightSample) -> Void)?
    var isLive: Bool { false }

    let route: DemoRoute
    /// Playback multiplier against the simulated clock.
    var speed: Double

    private var timer: Timer?
    private var wallStart: Date?
    private var simTime: TimeInterval = 0
    private var startedAt = Date()

    init(route: DemoRoute, speed: Double = 60) {
        self.route = route
        self.speed = speed
    }

    /// Never let two samples be more than this far apart in simulated time.
    /// Below this, short phases start getting skipped entirely — the takeoff
    /// roll is only ~35 s, so a 100 s step would step straight over it.
    private let maxSimStep: TimeInterval = 15

    func start() {
        wallStart = Date()
        startedAt = Date()
        simTime = 0
        // Tick faster as the multiplier rises so simulated resolution stays put.
        let interval = min(0.25, maxSimStep / max(1, speed))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick(step: interval * (self?.speed ?? 1))
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(step: TimeInterval) {
        simTime += step
        guard simTime <= route.totalDuration else { stop(); return }
        onSample?(route.sample(at: simTime, wallClock: startedAt.addingTimeInterval(simTime)))
    }
}

// MARK: - Route model

/// A demo route described by waypoints plus a vertical/speed profile.
struct DemoRoute: Identifiable, Hashable {

    var id: String
    var name: String
    var subtitle: String
    var waypoints: [CLLocationCoordinate2D]
    /// Cruise altitude, metres.
    var cruiseAlt: Double = 11_582   // FL380
    /// Cruise true airspeed, m/s (~475 kt).
    var cruiseSpeed: Double = 244
    /// Field elevation at each end, metres.
    var originElevation: Double = 30
    var destElevation: Double = 4

    // Segment durations in seconds of simulated time.
    var gateSecs: Double = 45
    var taxiOutSecs: Double = 210
    var rollSecs: Double = 35
    var climbSecs: Double = 1_320
    var descentSecs: Double = 1_500
    var flareSecs: Double = 90
    var taxiInSecs: Double = 150

    /// Total route length in metres, along the waypoint polyline.
    var pathLength: Double {
        guard waypoints.count > 1 else { return 0 }
        return zip(waypoints, waypoints.dropFirst())
            .reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    /// Cruise leg is whatever time is left after the fixed phases, derived from
    /// how long the route actually takes at cruise speed.
    var cruiseSecs: Double {
        // Climb and descent each cover roughly half their duration's distance.
        let coveredByClimbDescent = cruiseSpeed * 0.62 * (climbSecs + descentSecs)
        let remaining = max(0, pathLength - coveredByClimbDescent)
        return max(120, remaining / cruiseSpeed)
    }

    var totalDuration: Double {
        gateSecs + taxiOutSecs + rollSecs + climbSecs + cruiseSecs + descentSecs + flareSecs + taxiInSecs
    }

    // MARK: Profile

    /// Fraction of the route flown at simulated time `t`, 0...1.
    private func distanceFlown(at t: Double) -> Double {
        var d = 0.0
        var cursor = t

        // Gate: no movement.
        let gate = min(cursor, gateSecs); cursor -= gate
        if cursor <= 0 { return 0 }

        // Taxi out at ~8 m/s.
        let taxi = min(cursor, taxiOutSecs); d += taxi * 8; cursor -= taxi
        if cursor <= 0 { return d }

        // Takeoff roll: 0 -> 80 m/s.
        let roll = min(cursor, rollSecs); d += 0.5 * 80 * roll * (roll / rollSecs); cursor -= roll
        if cursor <= 0 { return d }

        // Climb: accelerating 80 -> cruise.
        let climb = min(cursor, climbSecs)
        let f = climb / climbSecs
        d += (80 + (cruiseSpeed - 80) * f / 2) * climb
        cursor -= climb
        if cursor <= 0 { return d }

        // Cruise.
        let cruise = min(cursor, cruiseSecs); d += cruise * cruiseSpeed; cursor -= cruise
        if cursor <= 0 { return d }

        // Descent: decelerating cruise -> 80.
        let desc = min(cursor, descentSecs)
        let g = desc / descentSecs
        d += (cruiseSpeed - (cruiseSpeed - 80) * g / 2) * desc
        cursor -= desc
        if cursor <= 0 { return d }

        // Flare + rollout, then taxi in.
        let flare = min(cursor, flareSecs); d += flare * 45; cursor -= flare
        if cursor <= 0 { return d }
        d += min(cursor, taxiInSecs) * 3.5   // average of the 7 → 0 ramp
        return d
    }

    private func altitude(at t: Double) -> Double {
        let ground = gateSecs + taxiOutSecs
        if t < ground + rollSecs { return originElevation }

        let climbStart = ground + rollSecs
        if t < climbStart + climbSecs {
            // Ease-out: airliners climb fast low, slowly in the flight levels.
            let f = (t - climbStart) / climbSecs
            let eased = 1 - pow(1 - f, 2.2)
            return originElevation + (cruiseAlt - originElevation) * eased
        }

        let cruiseStart = climbStart + climbSecs
        if t < cruiseStart + cruiseSecs {
            // Gentle step-climbs as the aircraft burns off fuel.
            let f = (t - cruiseStart) / max(1, cruiseSecs)
            return cruiseAlt + 300 * f + sin(t / 220) * 25
        }

        let descStart = cruiseStart + cruiseSecs
        if t < descStart + descentSecs {
            let f = (t - descStart) / descentSecs
            let eased = pow(f, 1.35)   // shallow at first, steeper on approach
            return cruiseAlt + 300 - (cruiseAlt + 300 - destElevation) * eased
        }
        return destElevation
    }

    private func speed(at t: Double) -> Double {
        let ground = gateSecs + taxiOutSecs
        if t < gateSecs { return 0 }
        if t < ground {
            // Taxi with a couple of hold-short stops.
            let f = (t - gateSecs) / taxiOutSecs
            return 8 * (0.55 + 0.45 * sin(f * .pi * 3.5))
        }
        if t < ground + rollSecs { return 80 * ((t - ground) / rollSecs) }

        let climbStart = ground + rollSecs
        if t < climbStart + climbSecs {
            return 80 + (cruiseSpeed - 80) * ((t - climbStart) / climbSecs)
        }
        let cruiseStart = climbStart + climbSecs
        if t < cruiseStart + cruiseSecs { return cruiseSpeed + sin(t / 180) * 3 }

        let descStart = cruiseStart + cruiseSecs
        if t < descStart + descentSecs {
            return cruiseSpeed - (cruiseSpeed - 80) * ((t - descStart) / descentSecs)
        }
        if t < descStart + descentSecs + flareSecs { return 45 }
        // Taxi in, coasting to a stop at the gate so the flight actually ends.
        let f = (t - (descStart + descentSecs + flareSecs)) / max(1, taxiInSecs)
        return 7 * max(0, 1 - f)
    }

    /// Position at simulated time, walked along the waypoint polyline.
    private func position(at t: Double) -> (CLLocationCoordinate2D, Double) {
        let target = min(distanceFlown(at: t), pathLength)
        var travelled = 0.0
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            let leg = Geo.distance(a, b)
            if travelled + leg >= target {
                let f = leg > 0 ? (target - travelled) / leg : 0
                let p = Geo.interpolate(a, b, f)
                return (p, Geo.bearing(from: a, to: b))
            }
            travelled += leg
        }
        let last = waypoints.last ?? waypoints[0]
        let prev = waypoints.count > 1 ? waypoints[waypoints.count - 2] : last
        return (last, Geo.bearing(from: prev, to: last))
    }

    func sample(at t: Double, wallClock: Date) -> FlightSample {
        let (coord, course) = position(at: t)
        let alt = altitude(at: t)
        let spd = speed(at: t)

        // Vertical rate by central difference on the profile itself.
        let vRate = (altitude(at: t + 3) - altitude(at: t - 3)) / 6

        // Cabin pressurisation: cabin altitude tops out around 2,000 m even at FL380.
        let cabinAlt = min(2_000, alt * 0.175)
        let pressure = 101.325 * pow(1 - cabinAlt / 44_330.0, 5.255)

        // Vibration signature per phase — this is what the detector's
        // corroborating signals key off.
        let turbulence = 0.012 + 0.010 * abs(sin(t / 47)) * (alt > 6_000 ? 1 : 0)
        let rms: Double
        let ground = gateSecs + taxiOutSecs
        if t < gateSecs { rms = 0.004 }
        else if t < ground { rms = 0.085 }                    // taxi: bumpy
        else if t < ground + rollSecs { rms = 0.26 }          // roll: loud
        else if vRate > 2 { rms = 0.052 }                     // climb
        else if vRate < -2 { rms = 0.038 }                    // descent
        else { rms = turbulence }                             // cruise

        return FlightSample(
            t: wallClock,
            lat: coord.latitude,
            lon: coord.longitude,
            alt: alt,
            rawAlt: alt + Double.random(in: -6...6),
            hAcc: 2 + Double.random(in: 0...1.5),
            vAcc: 3,
            spd: spd,
            course: course,
            asc: max(0, vRate),
            dsc: max(0, -vRate),
            odo: distanceFlown(at: t),
            elapsed: t,
            baro: cabinAlt - min(2_000, originElevation * 0.175),
            pressure: pressure,
            gyro: rms * 1.8,
            rms: rms,
            peak: rms * 3.2,
            n: 20,
            hr: Int(72 + (t < ground + rollSecs + 240 ? 22 : 0) + sin(t / 90) * 4),
            rrMs: nil,
            tank: max(15, 100 - Int(t / 240))
        )
    }
}

// MARK: - Bundled demo routes

extension DemoRoute {
    static func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Classic transcon. Routed over the Colorado Plateau so the demo actually
    /// flies past the good stuff.
    static let transcon = DemoRoute(
        id: "lax-jfk",
        name: "LAX → JFK",
        subtitle: "Transcon · 5h 10m · Grand Canyon, Rockies, Chicago",
        waypoints: [
            c(33.9416, -118.4085),   // LAX
            c(34.8, -117.0),         // Mojave
            c(35.9, -113.5),         // near Grand Canyon
            c(36.9, -110.0),         // Monument Valley
            c(38.6, -106.0),         // Rockies
            c(39.86, -104.67),       // Denver
            c(40.6, -98.0),          // Nebraska
            c(41.6, -90.5),          // Quad Cities
            c(41.98, -87.90),        // Chicago O'Hare
            c(41.5, -81.7),          // Cleveland
            c(41.2, -77.0),          // Pennsylvania
            c(40.6413, -73.7781)     // JFK
        ],
        originElevation: 38, destElevation: 4
    )

    /// Coast-to-coast diagonal with mountains, plains and the Gulf.
    static let seaMia = DemoRoute(
        id: "sea-mia",
        name: "SEA → MIA",
        subtitle: "Diagonal · 5h 40m · Cascades, Rockies, Gulf Coast",
        waypoints: [
            c(47.4502, -122.3088),   // SEA
            c(46.85, -121.76),       // Mt Rainier
            c(45.0, -116.0),
            c(43.6, -110.7),         // Tetons
            c(40.0, -105.3),         // Front Range
            c(37.0, -100.0),
            c(34.0, -95.0),
            c(31.0, -90.0),          // Mississippi
            c(28.5, -85.0),          // Gulf
            c(25.7959, -80.2870)     // MIA
        ],
        cruiseAlt: 11_278, originElevation: 132, destElevation: 3
    )

    /// The corridor the sample RRCC recording sits in.
    static let mexico = DemoRoute(
        id: "mex-lax",
        name: "MEX → LAX",
        subtitle: "Northbound · 3h 55m · Sierra Madre, Baja, Sonora",
        waypoints: [
            c(19.4363, -99.0721),    // MEX
            c(20.7, -100.4),
            c(21.9, -101.14),        // the RRCC sample sits right about here
            c(24.8, -104.0),
            c(28.6, -106.1),         // Chihuahua
            c(31.3, -110.9),
            c(32.7, -114.6),         // Yuma
            c(33.9416, -118.4085)    // LAX
        ],
        cruiseAlt: 11_582, originElevation: 2_230, destElevation: 38
    )

    static let all: [DemoRoute] = [.transcon, .seaMia, .mexico]
}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public static func == (a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Bool {
        a.latitude == b.latitude && a.longitude == b.longitude
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude); hasher.combine(longitude)
    }
}
