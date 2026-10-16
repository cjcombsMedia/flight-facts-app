import Foundation

/// Live readout of everything the detector is reasoning about.
/// Surfaced verbatim in the scanning UI — the detection logic *is* the fun part.
struct DetectionSignals {
    var speed: Double = 0            // m/s
    var altitude: Double = 0         // m MSL
    var heightAboveGround: Double = 0 // m, against the ground reference
    var verticalRate: Double = 0     // m/s, signed
    var vibration: Double = 0        // accel RMS, g
    var cabinPressure: Double?       // kPa
    var cabinAltitude: Double?       // m
    /// Cabin altitude trend, m/s. Negative = cabin descending = aircraft descending.
    var cabinRate: Double?
    var gpsAccuracy: Double = 0      // m
    var hasFix: Bool = false
    /// True while GPS is out and the position is dead-reckoned.
    var estimated: Bool = false

    /// 0–1. How sure we are that this is a flight and not a very fast train.
    var confidence: Double = 0

    /// Human-readable list of which signals are voting yes, for the UI.
    var evidence: [String] = []
}

/// Phase state machine.
///
/// The rules, in order of how much grief they prevent:
///
/// 1. **Leaving the air needs a landing.** Once airborne, the only way back to a
///    ground phase is ground speed below `landedSpeed` (nothing that flies goes
///    that slowly). Not altitude: the destination can sit a mile higher than the
///    origin (PHX → MEX), so "close to where we started" means nothing.
/// 2. **Airborne is detected at flying speed plus height or climb**, not only
///    above ~195 kt. An airliner climbs out at 150–180 kt; the previous version
///    called that a takeoff roll and then, on the first sample without
///    acceleration, "taxiing".
/// 3. **Estimated samples never drive a transition** — with one exception. When
///    GPS is out, position is dead-reckoned and altitude is frozen, so the phase
///    holds. The exception is the barometer: a sustained fall in cabin altitude
///    at cruise is the top of descent, and that's exactly the alert you want even
///    with no satellites.
/// 4. **Cold-start snap-in.** High and fast commits immediately, no debounce.
/// 5. **Debounce everything else**, so one bad fix can't flip the state.
final class FlightDetector {

    private(set) var phase: FlightPhase = .unknown
    private(set) var signals = DetectionSignals()
    private(set) var hasBeenAirborne = false

    /// Fires on every confirmed phase change: (from, to).
    var onPhaseChange: ((FlightPhase, FlightPhase) -> Void)?

    /// Destination field elevation from the flight plan, metres. Used to decide
    /// when a descent becomes an approach. Falls back to the origin's.
    var destinationElevation: Double?

    /// Smoothed altitude of the ground we were last stationary on.
    private(set) var groundReference: Double?

    private var candidate: FlightPhase = .unknown
    private var candidateSince: Date?
    private var speedHistory: [(t: Date, v: Double)] = []
    private var cabinHistory: [(t: Date, alt: Double)] = []

    // MARK: Thresholds (m/s, m)

    enum T {
        static let taxiSpeed = 1.5
        static let rollSpeed = 36.0          // ~70 kt
        static let flyingSpeed = 45.0        // ~87 kt: below any jet's rotation speed
        static let fastSpeed = 100.0         // ~195 kt: nothing on the ground does this
        static let landedSpeed = 30.0        // ~58 kt: nothing airborne flies this slowly
        static let climbRate = 1.6
        static let sinkRate = -1.6
        static let airborneClimb = 2.5
        static let liftoffHeight = 60.0      // ~200 ft above the runway
        static let cruiseFloor = 4_500.0     // ~15,000 ft
        static let snapAltitude = 5_000.0
        static let approachHeight = 3_000.0  // ~10,000 ft above the destination
        static let cabinDescentRate = -0.8   // m/s of cabin altitude (~160 fpm)
    }

    /// How long a candidate phase must hold before it sticks, seconds.
    private func dwell(for p: FlightPhase) -> TimeInterval {
        switch p {
        case .takeoffRoll: return 3
        case .climb:       return 6
        case .descent:     return 12
        case .cruise:      return 20
        case .approach:    return 10
        case .landed:      return 20
        case .taxi:        return 6
        default:           return 5
        }
    }

    func reset() {
        phase = .unknown
        candidate = .unknown
        candidateSince = nil
        groundReference = nil
        hasBeenAirborne = false
        speedHistory.removeAll()
        cabinHistory.removeAll()
        signals = DetectionSignals()
    }

    // MARK: Ingest

    func ingest(_ s: FlightSample) {
        recordHistory(s)
        updateSignals(s)

        let proposed = classify(s)

        // Cold-start snap-in: overwhelming evidence commits with no dwell.
        if !s.isEstimated, !phase.isAirborne, isUnambiguouslyAirborne(s), proposed.isAirborne {
            commit(proposed)
            return
        }

        if proposed != candidate {
            candidate = proposed
            candidateSince = s.t
        }
        if let since = candidateSince, candidate != phase,
           s.t.timeIntervalSince(since) >= dwell(for: candidate) {
            commit(candidate)
        }
    }

    private func commit(_ next: FlightPhase) {
        let old = phase
        phase = next
        candidate = next
        if next.isAirborne { hasBeenAirborne = true }
        if old != next { onPhaseChange?(old, next) }
    }

    private func recordHistory(_ s: FlightSample) {
        if let p = s.pressure, p > 10 {
            cabinHistory.append((s.t, Self.cabinAltitude(kPa: p)))
            cabinHistory.removeAll { s.t.timeIntervalSince($0.t) > 90 }
        }
        guard !s.isEstimated else { return }

        speedHistory.append((s.t, s.spd))
        speedHistory.removeAll { s.t.timeIntervalSince($0.t) > 6 }

        // Track the ground we're on while slow and not yet flying, so the
        // reference follows you from the curb to the gate to the runway.
        if !phase.isAirborne, phase != .landed, s.spd < 20 {
            groundReference = groundReference.map { $0 * 0.9 + s.alt * 0.1 } ?? s.alt
        }
    }

    // MARK: Classification

    private func isUnambiguouslyAirborne(_ s: FlightSample) -> Bool {
        s.alt > T.snapAltitude && s.spd > T.fastSpeed
    }

    /// Flying, on current evidence. Height needs a ground reference; climb or
    /// sink rate at flying speed doesn't, which covers a cold start mid-climb.
    private func looksAirborne(_ s: FlightSample) -> Bool {
        if isUnambiguouslyAirborne(s) || s.spd > T.fastSpeed { return true }
        guard s.spd > T.flyingSpeed else { return false }
        let v = s.verticalRate
        if v > T.airborneClimb || v < -T.airborneClimb { return true }
        if let ground = groundReference, s.alt - ground > T.liftoffHeight { return true }
        return false
    }

    /// Positive acceleration over the last few seconds of good fixes.
    private var isAccelerating: Bool {
        guard let first = speedHistory.first, let last = speedHistory.last,
              last.t.timeIntervalSince(first.t) >= 2 else { return false }
        return last.v - first.v > 1.5
    }

    /// Cabin altitude trend over the last minute-plus, m/s.
    var cabinRate: Double? {
        guard let first = cabinHistory.first, let last = cabinHistory.last,
              last.t.timeIntervalSince(first.t) >= 45 else { return nil }
        return SensorFusion.slope(cabinHistory)
    }

    private func isNearDestination(_ s: FlightSample) -> Bool {
        let field = destinationElevation ?? groundReference ?? 0
        return s.alt - field < T.approachHeight
    }

    private func classify(_ s: FlightSample) -> FlightPhase {
        if phase == .landed { return .landed }

        let v = s.verticalRate
        let cabinDescending = (cabinRate ?? 0) < T.cabinDescentRate

        // --- GPS out: hold, unless the barometer says we've started down. ----
        if s.isEstimated {
            if phase == .cruise, cabinDescending { return .descent }
            return phase
        }

        // --- In the air ------------------------------------------------------
        if phase.isAirborne {
            if s.spd < T.landedSpeed { return .landed }
            if v > T.climbRate { return .climb }
            if v < T.sinkRate || (phase == .cruise && cabinDescending && v < 0.5) {
                return isNearDestination(s) ? .approach : .descent
            }
            // Level. High enough means cruise; a low level-off keeps whatever
            // we were doing (an ATC hold on climb-out is still the climb).
            if s.alt > T.cruiseFloor { return .cruise }
            return phase
        }

        // --- On the ground (or not sure yet) ---------------------------------
        if looksAirborne(s) {
            if v < T.sinkRate { return isNearDestination(s) ? .approach : .descent }
            if v > T.climbRate || s.alt <= T.cruiseFloor { return .climb }
            return .cruise
        }
        if s.spd >= T.rollSpeed {
            // Stay in the roll through the plateau just before rotation; a
            // rejected takeoff drops below roll speed and falls through to taxi.
            if isAccelerating || phase == .takeoffRoll { return .takeoffRoll }
            return .taxi
        }
        if s.spd >= T.taxiSpeed { return .taxi }
        return .atGate
    }

    // MARK: Signals & confidence

    static func cabinAltitude(kPa p: Double) -> Double {
        44_330.0 * (1.0 - pow(p / 101.325, 0.1902632))
    }

    private func updateSignals(_ s: FlightSample) {
        var sig = DetectionSignals()
        sig.speed = s.spd
        sig.altitude = s.alt
        sig.heightAboveGround = s.alt - (groundReference ?? s.alt)
        sig.verticalRate = s.verticalRate
        sig.vibration = s.rms ?? 0
        sig.cabinPressure = s.pressure
        sig.cabinRate = cabinRate
        sig.gpsAccuracy = max(0, s.hAcc)
        sig.estimated = s.isEstimated
        sig.hasFix = !s.isEstimated && s.hAcc > 0 && s.hAcc < 100
        if let p = s.pressure, p > 10 { sig.cabinAltitude = Self.cabinAltitude(kPa: p) }

        // Weighted vote. Each signal can be wrong on its own; together they aren't.
        var score = 0.0
        var evidence: [String] = []

        if s.spd > T.fastSpeed {
            score += 0.40
            evidence.append("Ground speed \(Units.knots(s.spd)) — faster than anything on rails")
        } else if s.spd > T.flyingSpeed {
            score += 0.20
            evidence.append("Moving at \(Units.knots(s.spd)) — flying speed")
        } else if s.spd > T.rollSpeed {
            score += 0.10
            evidence.append("Rolling at \(Units.knots(s.spd))")
        }

        if s.alt > T.snapAltitude {
            score += 0.35
            evidence.append("Altitude \(Units.feet(s.alt)) — above every road on Earth")
        } else if sig.heightAboveGround > 300 {
            score += 0.20
            evidence.append("Climbed \(Units.feet(sig.heightAboveGround)) since you started")
        }

        if let cabin = sig.cabinAltitude, cabin > 900 {
            score += 0.15
            evidence.append("Cabin pressure \(String(format: "%.1f", s.pressure ?? 0)) kPa — pressurised")
        }

        if abs(s.verticalRate) > T.climbRate {
            score += 0.10
            evidence.append("Vertical rate \(Units.fpm(s.verticalRate))")
        }

        if let rate = sig.cabinRate, abs(rate) > 0.5 {
            evidence.append("Cabin altitude \(rate > 0 ? "rising" : "falling") \(Units.fpm(rate))")
        }

        if s.isEstimated {
            evidence.append("GPS dropped out — position is estimated from the last fix")
        }

        if hasBeenAirborne { score = max(score, 0.9) }
        sig.confidence = min(1, score)
        sig.evidence = evidence
        signals = sig
    }
}
