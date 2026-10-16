import Foundation

/// Sun and moon facts computed from position and time.
///
/// All of this is closed-form astronomy — no network, no data files. That makes
/// it perfect filler over oceans and deserts, where the landmark corpus has
/// nothing to say for hours at a time.
///
/// The interesting one is horizon dip: at 38,000 ft the geometric horizon is
/// depressed about 3.4°, so the sun sets roughly 20 minutes later than it does
/// for anyone directly below you.
final class SkyFacts {

    private var fired = Set<String>()
    private var lastEmitted: Date?

    func reset() {
        fired.removeAll()
        lastEmitted = nil
    }

    /// How far below the true horizontal the horizon sits, degrees.
    static func horizonDip(altitudeM: Double) -> Double {
        guard altitudeM > 0 else { return 0 }
        let r = Geo.earthRadiusM
        return Geo.deg(acos(r / (r + altitudeM)))
    }

    /// Solar elevation above the true horizontal, degrees.
    static func solarElevation(lat: Double, lon: Double, date: Date) -> Double {
        let jd = julianDay(date)
        let n = jd - 2_451_545.0

        // Mean longitude and anomaly (degrees).
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = Geo.rad((357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360))

        // Ecliptic longitude, then declination.
        let lambda = Geo.rad(L + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let epsilon = Geo.rad(23.439 - 0.0000004 * n)
        let declination = asin(sin(epsilon) * sin(lambda))

        // Greenwich hour angle.
        let gmst = (18.697374558 + 24.06570982441908 * n)
            .truncatingRemainder(dividingBy: 24)
        var rightAscension = Geo.deg(atan2(cos(epsilon) * sin(lambda), cos(lambda)))
        if rightAscension < 0 { rightAscension += 360 }

        let hourAngle = Geo.rad((gmst * 15 + lon - rightAscension)
            .truncatingRemainder(dividingBy: 360))

        let latR = Geo.rad(lat)
        let sinElev = sin(latR) * sin(declination)
                    + cos(latR) * cos(declination) * cos(hourAngle)
        return Geo.deg(asin(max(-1, min(1, sinElev))))
    }

    /// Moon phase as a fraction of the synodic month, 0 = new, 0.5 = full.
    static func moonPhase(_ date: Date) -> Double {
        // Reference new moon: 2000-01-06 18:14 UTC.
        let reference = 2_451_550.26
        let synodic = 29.530588853
        let days = julianDay(date) - reference
        let phase = (days / synodic).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }

    static func moonName(_ phase: Double) -> (String, String) {
        switch phase {
        case ..<0.03:   return ("🌑", "new moon")
        case ..<0.22:   return ("🌒", "waxing crescent")
        case ..<0.28:   return ("🌓", "first quarter")
        case ..<0.47:   return ("🌔", "waxing gibbous")
        case ..<0.53:   return ("🌕", "full moon")
        case ..<0.72:   return ("🌖", "waning gibbous")
        case ..<0.78:   return ("🌗", "last quarter")
        case ..<0.97:   return ("🌘", "waning crescent")
        default:        return ("🌑", "new moon")
        }
    }

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }

    // MARK: Emission

    /// Sky facts appropriate to right now, at most one per call.
    func check(_ s: FlightSample, phase: FlightPhase) -> Bubble? {
        guard phase.isAirborne, s.alt > 5_000 else { return nil }

        let elevation = Self.solarElevation(lat: s.lat, lon: s.lon, date: s.t)
        let dip = Self.horizonDip(altitudeM: s.alt)

        /// Marks a fact as served. Returns false if it already has been.
        func claim(_ key: String) -> Bool {
            guard !fired.contains(key) else { return false }
            fired.insert(key)
            lastEmitted = s.t
            return true
        }

        // The best one: sun already down on the ground, still up here.
        if elevation < 0, elevation > -dip, claim("extra-daylight") {
            return Bubble(
                kind: .stat, title: "You're still in sunlight",
                body: "The sun has already set for everyone directly below you. At \(Units.feet(s.alt)) your horizon sits \(String(format: "%.1f", dip))° lower, so up here it's still daylight.",
                detail: ["Altitude buys you sunset. Every 1,000 ft delays it by roughly a minute and a half.",
                         "This is why a window seat at dusk beats anything you can see from the ground."],
                priority: .normal)
        }

        // Deep night at cruise — make the stargazing pitch.
        if elevation < -18, claim("night-cruise") {
            let (glyph, name) = Self.moonName(Self.moonPhase(s.t))
            return Bubble(
                kind: .stat, title: "Astronomical night",
                body: "The sun is \(Int(-elevation))° below the horizon. Above most of the atmosphere and all of the light pollution, this is about as good as stargazing gets without climbing a mountain.",
                detail: ["Tonight's moon is a \(name) \(glyph).",
                         "Cup your hands against the window to kill the cabin reflection, and give your eyes ten minutes to adapt.",
                         "Heading north in winter, the aurora is a real possibility above 55° latitude."],
                priority: .normal)
        }

        // Golden hour.
        if elevation > 0, elevation < 6, claim("golden") {
            return Bubble(
                kind: .stat, title: "Golden hour, from above",
                body: "The sun is \(String(format: "%.1f", elevation))° up. Its light is crossing roughly 12 times more atmosphere than at noon, which is what scatters the blue away and leaves the orange.",
                detail: ["From up here you can often pick out the terminator — the curved shadow line dividing day from night — sweeping across the ground."],
                priority: .low)
        }

        // Sun near the zenith.
        if elevation > 70, claim("high-sun") {
            return Bubble(
                kind: .stat, title: "Sun almost overhead",
                body: "Solar elevation is \(Int(elevation))°. UV at cruise is far stronger than at sea level — roughly double.",
                detail: ["Cabin windows block UVB but pass a good deal of UVA, which is why pilots show measurably more sun damage on their window side."],
                priority: .low)
        }

        return nil
    }
}
