import XCTest
import CoreLocation
@testable import Flight_Facts

final class SensorFusionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_785_000_000)
    private let motion = MotionSnapshot()

    private func fix(_ lat: Double, _ lon: Double, alt: Double = 10_000, at t: Double,
                     speed: Double = 240, course: Double = 90,
                     vAcc: Double = 8, hAcc: Double = 5) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: alt, horizontalAccuracy: hAcc, verticalAccuracy: vAcc,
                   course: course, courseAccuracy: course >= 0 ? 2 : -1,
                   speed: speed, speedAccuracy: speed >= 0 ? 1 : -1,
                   timestamp: t0.addingTimeInterval(t))
    }

    func testNoFixYieldsNoSample() {
        var f = SensorFusion(startedAt: t0)
        XCTAssertNil(f.sample(location: nil, motion: motion, battery: 80, now: t0))
    }

    /// The bug behind the in-flight "lock-up": a stale fix used to be re-emitted
    /// as if it were current. Now it's flagged and the position keeps moving.
    func testStaleFixIsDeadReckonedAndFlagged() throws {
        var f = SensorFusion(startedAt: t0)
        let start = fix(30, -105, at: 0)
        let first = try XCTUnwrap(f.sample(location: start, motion: motion, battery: 80, now: t0.addingTimeInterval(0.5)))
        XCTAssertFalse(first.isEstimated)

        // A minute later CoreLocation is still holding the same old fix.
        let later = try XCTUnwrap(f.sample(location: start, motion: motion, battery: 80,
                                           now: t0.addingTimeInterval(60)))
        XCTAssertTrue(later.isEstimated)
        XCTAssertEqual(later.spd, 240, accuracy: 0.01)
        XCTAssertEqual(later.alt, 10_000, accuracy: 0.01)
        XCTAssertEqual(later.verticalRate, 0)

        let moved = Geo.distance(start.coordinate, later.coordinate)
        XCTAssertEqual(moved, 240 * 60, accuracy: 240 * 60 * 0.01, "should project along the course")
        XCTAssertGreaterThan(later.lon, start.coordinate.longitude, "course 90° is east")
    }

    /// `speed == -1` means unknown, not stopped. It used to be clamped to 0.
    func testInvalidSpeedIsDerivedFromPositions() throws {
        var f = SensorFusion(startedAt: t0)
        let a = fix(30, -105, at: 0, speed: -1, course: -1)
        let b = CLLocation(coordinate: Geo.destination(from: a.coordinate, bearing: 90, distance: 200),
                           altitude: 10_000, horizontalAccuracy: 5, verticalAccuracy: 8,
                           course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1,
                           timestamp: t0.addingTimeInterval(1))
        _ = f.sample(location: a, motion: motion, battery: nil, now: t0.addingTimeInterval(0.2))
        let s = try XCTUnwrap(f.sample(location: b, motion: motion, battery: nil, now: t0.addingTimeInterval(1.2)))
        XCTAssertEqual(s.spd, 200, accuracy: 2)
        XCTAssertEqual(s.course, 90, accuracy: 1, "course derived from movement when CoreLocation's is invalid")
    }

    /// At the gate: jittering position and a garbage course must not move the
    /// odometer or set a course — that random course is what spun the map.
    func testStationaryJitterHoldsCourseAndOdometer() throws {
        var f = SensorFusion(startedAt: t0)
        var gen = SystemRandomNumberGenerator()
        var last: FlightSample?
        for i in 0..<120 {
            let jitter = Geo.destination(from: CLLocationCoordinate2D(latitude: 33.43, longitude: -112.01),
                                         bearing: .random(in: 0..<360, using: &gen),
                                         distance: .random(in: 0...4, using: &gen))
            let loc = CLLocation(coordinate: jitter, altitude: 347, horizontalAccuracy: 5, verticalAccuracy: 6,
                                 course: .random(in: 0..<360, using: &gen), courseAccuracy: 90,
                                 speed: .random(in: 0...0.6, using: &gen), speedAccuracy: 1,
                                 timestamp: t0.addingTimeInterval(Double(i)))
            last = f.sample(location: loc, motion: motion, battery: nil, now: t0.addingTimeInterval(Double(i) + 0.3))
        }
        let s = try XCTUnwrap(last)
        XCTAssertNil(f.course, "no course should be set while stationary")
        XCTAssertLessThan(s.odo, 10, "jitter must not accumulate distance")
    }

    func testInvalidAltitudeHoldsLastGoodValue() throws {
        var f = SensorFusion(startedAt: t0)
        _ = f.sample(location: fix(30, -105, alt: 9_000, at: 0), motion: motion, battery: nil,
                     now: t0.addingTimeInterval(0.2))
        let junk = fix(30, -104.99, alt: 0, at: 1, vAcc: -1)
        let s = try XCTUnwrap(f.sample(location: junk, motion: motion, battery: nil, now: t0.addingTimeInterval(1.2)))
        XCTAssertEqual(s.alt, 9_000, accuracy: 0.01)
    }

    /// Fixes resuming after a long dropout must not be rejected as a teleport,
    /// and must not invent a vertical rate across the gap.
    func testRecoveryAfterLongGap() throws {
        var f = SensorFusion(startedAt: t0)
        let a = fix(30, -105, at: 0)
        _ = f.sample(location: a, motion: motion, battery: nil, now: t0.addingTimeInterval(0.2))
        let far = Geo.destination(from: a.coordinate, bearing: 90, distance: 240 * 600)
        let b = CLLocation(coordinate: far, altitude: 10_500, horizontalAccuracy: 5, verticalAccuracy: 8,
                           course: 90, courseAccuracy: 2, speed: 240, speedAccuracy: 1,
                           timestamp: t0.addingTimeInterval(600))
        let s = try XCTUnwrap(f.sample(location: b, motion: motion, battery: nil, now: t0.addingTimeInterval(600.2)))
        XCTAssertFalse(s.isEstimated)
        XCTAssertEqual(s.odo, 240 * 600, accuracy: 240 * 600 * 0.01)
        XCTAssertEqual(s.verticalRate, 0, "a single fix after a gap has no trend yet")
    }
}
