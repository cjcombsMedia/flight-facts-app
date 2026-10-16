import XCTest
import CoreLocation
@testable import Flight_Facts

/// Scenario tests for the phase detector. Each one is a flight profile fed in
/// one sample per second, the way the live sensor source delivers them.
final class FlightDetectorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_785_000_000)

    private func sample(_ t: Double, alt: Double, spd: Double, v: Double = 0,
                        est: Bool = false, pressure: Double? = nil) -> FlightSample {
        FlightSample(t: t0.addingTimeInterval(t), lat: 33.43, lon: -112.01,
                     alt: alt, rawAlt: alt, hAcc: est ? -1 : 4, vAcc: est ? -1 : 6,
                     spd: spd, course: 90, asc: max(0, v), dsc: max(0, -v),
                     odo: 0, elapsed: t, baro: nil, pressure: pressure,
                     gyro: 0.02, rms: 0.02, peak: 0.05, n: 20,
                     hr: nil, rrMs: nil, tank: 90, est: est ? true : nil)
    }

    /// Pressure that puts the cabin at `h` metres.
    private func kPa(cabin h: Double) -> Double {
        101.325 * pow(1 - h / 44_330.0, 5.255)
    }

    private func run(_ samples: [FlightSample], into d: FlightDetector) -> [FlightPhase] {
        var phases: [FlightPhase] = []
        d.onPhaseChange = { _, to in phases.append(to) }
        samples.forEach(d.ingest)
        return phases
    }

    // MARK: The reported bug

    /// Takeoff from PHX, initial climb below 195 kt, then GPS drops out at
    /// 2,200 ft — what actually happened on the real flight. The old detector
    /// read the climb as a takeoff roll, then "taxiing".
    func testClimbOutBelow195KnotsThenGPSLossNeverReturnsToGround() {
        let field = 347.0
        var s: [FlightSample] = []
        for t in 0..<60   { s.append(sample(Double(t), alt: field, spd: 0)) }                  // gate
        for t in 60..<240 { s.append(sample(Double(t), alt: field, spd: 8)) }                  // taxi
        for t in 240..<275 {                                                                   // roll
            s.append(sample(Double(t), alt: field, spd: 80 * Double(t - 240) / 35))
        }
        var alt = field
        for t in 275..<320 {                                                                   // climb out
            alt += 8
            // Noisy speed, ~160–175 kt, deliberately not monotonic.
            let spd = 84 + (t % 3 == 0 ? -2.0 : 1.5)
            s.append(sample(Double(t), alt: alt, spd: spd, v: 8))
        }
        XCTAssertGreaterThan(alt * 3.28084, 2_200)
        for t in 320..<620 {                                                                   // GPS gone
            s.append(sample(Double(t), alt: alt, spd: 86, est: true))
        }

        let d = FlightDetector()
        let phases = run(s, into: d)

        let firstClimb = phases.firstIndex(of: .climb)
        XCTAssertNotNil(firstClimb, "never detected the climb: \(phases)")
        if let i = firstClimb {
            let after = phases[i...]
            XCTAssertFalse(after.contains { !$0.isAirborne },
                           "dropped back to a ground phase after takeoff: \(phases)")
        }
        XCTAssertEqual(d.phase, .climb)
        XCTAssertTrue(phases.contains(.takeoffRoll), "takeoff roll not seen: \(phases)")
    }

    // MARK: Landing

    /// PHX (347 m) → MEX (2,230 m). The destination is 1,900 m higher than the
    /// origin, so "close to the starting altitude" can never mean landed.
    func testLandsAtDestinationHigherThanOrigin() {
        let mex = 2_230.0
        var s: [FlightSample] = []
        var t = 0.0
        var alt = 11_000.0
        for _ in 0..<60 { s.append(sample(t, alt: alt, spd: 240)); t += 1 }            // cruise
        while alt > mex + 20 {                                                           // descent
            alt = max(mex, alt - 9)
            s.append(sample(t, alt: alt, spd: max(75, 240 - (11_000 - alt) / 45), v: -9)); t += 1
        }
        var spd = 70.0
        while spd > 8 {                                                                  // rollout + taxi
            spd = max(8, spd - 2.5)
            s.append(sample(t, alt: mex, spd: spd)); t += 1
        }
        for _ in 0..<40 { s.append(sample(t, alt: mex, spd: 6)); t += 1 }

        let d = FlightDetector()
        d.destinationElevation = mex
        let phases = run(s, into: d)

        XCTAssertEqual(phases.first, .cruise)
        XCTAssertTrue(phases.contains(.descent), "\(phases)")
        XCTAssertTrue(phases.contains(.approach), "\(phases)")
        XCTAssertEqual(d.phase, .landed, "\(phases)")
    }

    // MARK: Cold start

    func testColdStartAtCruiseSnapsInImmediately() {
        let d = FlightDetector()
        d.ingest(sample(0, alt: 11_200, spd: 245))
        XCTAssertEqual(d.phase, .cruise)
    }

    /// Opening the app mid-climb with no ground reference at all.
    func testColdStartMidClimbAtLowSpeed() {
        let d = FlightDetector()
        var alt = 1_200.0
        for t in 0..<20 {
            alt += 7
            d.ingest(sample(Double(t), alt: alt, spd: 85, v: 7))
        }
        XCTAssertEqual(d.phase, .climb)
    }

    // MARK: GPS out

    /// At cruise with no satellites, a sustained fall in cabin altitude is the
    /// top of descent — the alert that matters most.
    func testBarometricTopOfDescentWithGPSLost() {
        var s: [FlightSample] = []
        for t in 0..<60 { s.append(sample(Double(t), alt: 11_000, spd: 240, pressure: kPa(cabin: 2_000))) }
        var cabin = 2_000.0
        for t in 60..<240 {
            cabin -= 2   // cabin descending ~400 fpm
            s.append(sample(Double(t), alt: 11_000, spd: 240, est: true, pressure: kPa(cabin: cabin)))
        }
        let d = FlightDetector()
        let phases = run(s, into: d)
        XCTAssertEqual(d.phase, .descent, "\(phases)")
    }

    /// GPS out at cruise with a steady cabin: hold cruise, don't guess.
    func testGPSLossAtCruiseHoldsPhase() {
        var s: [FlightSample] = []
        for t in 0..<30  { s.append(sample(Double(t), alt: 11_000, spd: 240, pressure: kPa(cabin: 2_000))) }
        for t in 30..<900 { s.append(sample(Double(t), alt: 11_000, spd: 240, est: true, pressure: kPa(cabin: 2_000))) }
        let d = FlightDetector()
        _ = run(s, into: d)
        XCTAssertEqual(d.phase, .cruise)
    }

    // MARK: False positives

    func testStationaryJitterStaysAtGate() {
        var gen = SystemRandomNumberGenerator()
        let d = FlightDetector()
        let phases = run((0..<300).map { t in
            sample(Double(t), alt: 347 + Double.random(in: -6...6, using: &gen),
                   spd: Double.random(in: 0...1.2, using: &gen))
        }, into: d)
        XCTAssertEqual(d.phase, .atGate)
        XCTAssertFalse(phases.contains(.taxi), "\(phases)")
    }

    /// Highway driving with hills, at 85–95 mph: never airborne.
    func testHighwayDriveIsNeverAirborne() {
        let d = FlightDetector()
        var phases: [FlightPhase] = []
        d.onPhaseChange = { _, to in phases.append(to) }
        for t in 0..<900 {
            let alt = 600 + 40 * sin(Double(t) / 60)
            let v = 40.0 / 60 * cos(Double(t) / 60)
            d.ingest(sample(Double(t), alt: alt, spd: 38 + 4 * sin(Double(t) / 25), v: v))
        }
        XCTAssertFalse(d.hasBeenAirborne, "\(phases)")
        XCTAssertFalse(phases.contains { $0.isAirborne }, "\(phases)")
    }

    // MARK: Whole demo route

    /// The synthetic demo flies the full profile; the detector should walk it in
    /// order and never go backwards to the ground mid-flight.
    func testSyntheticRouteProgressesThroughEveryPhase() {
        let route = DemoRoute.mexico
        let d = FlightDetector()
        d.destinationElevation = route.destElevation
        var phases: [FlightPhase] = []
        d.onPhaseChange = { _, to in phases.append(to) }

        var t = 0.0
        while t < route.totalDuration {
            d.ingest(route.sample(at: t, wallClock: t0.addingTimeInterval(t)))
            t += 2
        }

        for expected: FlightPhase in [.taxi, .takeoffRoll, .climb, .cruise, .descent, .approach, .landed] {
            XCTAssertTrue(phases.contains(expected), "missing \(expected): \(phases)")
        }
        if let lift = phases.firstIndex(of: .climb), let land = phases.lastIndex(of: .landed) {
            XCTAssertFalse(phases[lift..<land].contains { !$0.isAirborne }, "\(phases)")
        }
        XCTAssertEqual(d.phase, .landed)
    }
}
