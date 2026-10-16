import Foundation
import CoreLocation

/// One fused sensor tick.
///
/// Key names intentionally mirror the RRCC `TrackSession` schema (schema 3) so a
/// recording from either app decodes in the other. Everything optional in RRCC
/// stays optional here — a phone with no barometer or no paired watch still
/// produces valid samples.
struct FlightSample: Codable, Identifiable, Equatable {

    // Identity is derived, not persisted — keeps the JSON byte-compatible.
    var id: Date { t }

    /// Sample timestamp (RRCC: ISO-8601 `Z`).
    var t: Date

    // MARK: Position

    var lat: Double
    var lon: Double
    /// Fused altitude in metres MSL.
    var alt: Double
    /// Unsmoothed GPS altitude in metres MSL.
    var rawAlt: Double?
    /// Horizontal accuracy, metres.
    var hAcc: Double
    /// Vertical accuracy, metres.
    var vAcc: Double

    // MARK: Movement

    /// Ground speed, metres/second.
    var spd: Double
    /// True course over ground, degrees 0–360.
    var course: Double
    /// Climb rate, m/s. Positive number, zero when not climbing.
    var asc: Double
    /// Sink rate, m/s. Positive number, zero when not descending.
    var dsc: Double
    /// Cumulative distance, metres.
    var odo: Double
    /// Seconds since session start.
    var elapsed: Double

    // MARK: Atmosphere

    /// Relative altitude change reported by CMAltimeter since session start, metres.
    var baro: Double?
    /// Ambient pressure, kPa. In a pressurised cabin this reads cabin altitude,
    /// not outside air — which is exactly what makes it a great climb/descent cue.
    var pressure: Double?

    // MARK: Motion

    /// Gyro magnitude, rad/s — turbulence and turn detection.
    var gyro: Double?
    /// Accelerometer RMS over the window, g.
    var rms: Double?
    /// Peak accelerometer magnitude over the window, g.
    var peak: Double?
    /// Motion samples folded into this tick.
    var n: Int?

    // MARK: Body & device

    /// Heart rate, bpm (paired watch).
    var hr: Int?
    /// R-R interval, ms.
    var rrMs: Double?
    /// Device battery, percent. RRCC calls it `tank`.
    var tank: Int?

    // MARK: Fix quality

    /// True when GPS has dropped out and position/speed/altitude are estimates
    /// (dead reckoning from the last good fix). Omitted from the JSON when nil,
    /// so RRCC-format files stay byte-compatible; RRCC readers ignore it.
    var est: Bool?

    var isEstimated: Bool { est == true }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Signed vertical rate in m/s, reassembled from the split asc/dsc fields.
    var verticalRate: Double {
        if dsc > 0 { return -dsc }
        return asc
    }

    static func == (a: FlightSample, b: FlightSample) -> Bool { a.t == b.t }
}

/// Session-level rollup. Mirrors the RRCC `meta` block.
struct SessionMeta: Codable {
    var schema: Int = 3
    var start: Date
    var duration: TimeInterval = 0
    var distance: Double = 0
    var totalAscent: Double = 0
    var totalDescent: Double = 0
    var deviceModel: String = ""
    /// RRCC uses this for activity type ("On Bike"). Flight Facts writes "In Flight".
    var mode: String = "In Flight"

    var motionRateHz: Double?
    var nominalRateHz: Double?
    var altitudeOffset: Double?
    var capturePath: String?
    var startingTank: Int?
    var endingTank: Int?
    var rmssdMs: Double?
    var rawMotionFile: String?
}

/// The on-disk shape of a recording — `{ "samples": [...], "meta": {...} }`,
/// identical to a RRCC TrackSession file.
struct TrackSessionFile: Codable {
    var samples: [FlightSample]
    var meta: SessionMeta
}

extension JSONDecoder {
    /// Decoder configured for the RRCC / Flight Facts wire format.
    static var trackSession: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var trackSession: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }
}
