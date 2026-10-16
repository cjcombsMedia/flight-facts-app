import Foundation
import CoreLocation

/// A single point on the saved route.
struct TrackPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var alt: Double
    var t: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// A bubble as persisted in the log — trimmed of anything view-only.
struct LoggedEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: String
    var title: String
    var body: String
    var detail: [String]
    var at: Date

    init(_ b: Bubble) {
        id = b.id
        kind = b.kind.rawValue
        title = b.title
        body = b.body
        detail = b.detail
        at = b.at
    }

    var glyph: String { Bubble.Kind(rawValue: kind)?.glyph ?? "•" }
    var speaker: String { Bubble.Kind(rawValue: kind)?.speaker ?? "" }
}

/// The saved record of one flight.
struct FlightLog: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date?
    var title: String = "Flight"
    /// Whether this came from real sensors or a demo/replay run.
    var isSimulated: Bool = false

    var sightings: [POISighting] = []
    var entries: [LoggedEntry] = []
    var track: [TrackPoint] = []

    var maxAltitudeM: Double = 0
    var maxSpeedMps: Double = 0
    var distanceM: Double = 0
    var startRegion: String?
    var endRegion: String?

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var displayTitle: String {
        if let s = startRegion, let e = endRegion, s != e { return "\(s) → \(e)" }
        if let s = startRegion { return s }
        return title
    }
}

/// Owns the in-flight buffer and writes finished flights to disk.
///
/// Two artefacts come out of a flight: the `FlightLog` (what the log screen
/// shows) and a full `TrackSessionFile` in the RRCC wire format (what you would
/// hand to another tool, or replay later).
final class FlightRecorder {

    private(set) var current: FlightLog?
    /// Full-rate samples, kept for the session export.
    private var samples: [FlightSample] = []
    private var lastTrackPoint: TrackPoint?

    private let fm = FileManager.default

    private var directory: URL {
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flights", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    // MARK: Lifecycle

    func begin(at date: Date, simulated: Bool) {
        current = FlightLog(startedAt: date, isSimulated: simulated)
        samples.removeAll()
        lastTrackPoint = nil
    }

    func ingest(_ s: FlightSample) {
        guard var log = current else { return }
        samples.append(s)

        log.maxAltitudeM = max(log.maxAltitudeM, s.alt)
        log.maxSpeedMps = max(log.maxSpeedMps, s.spd)
        log.distanceM = s.odo

        // Downsample the drawn route: a point every 10 s, or sooner on a turn.
        let point = TrackPoint(lat: s.lat, lon: s.lon, alt: s.alt, t: s.t)
        let keepPoint: Bool
        if let last = lastTrackPoint {
            keepPoint = s.t.timeIntervalSince(last.t) >= 10
                || Geo.distance(last.coordinate, point.coordinate) > 8_000
        } else {
            keepPoint = true
        }
        if keepPoint {
            lastTrackPoint = point
            log.track.append(point)
        }

        current = log
    }

    func record(_ bubble: Bubble) {
        current?.entries.append(LoggedEntry(bubble))
        if let sighting = bubble.sighting {
            current?.sightings.append(sighting)
        }
    }

    func noteRegion(_ region: String?) {
        guard let region else { return }
        if current?.startRegion == nil { current?.startRegion = region }
        current?.endRegion = region
    }

    /// Closes out the flight and writes both artefacts. Returns the saved log.
    @discardableResult
    func end(at date: Date) -> FlightLog? {
        guard var log = current else { return nil }
        log.endedAt = date
        current = nil

        save(log)
        if !samples.isEmpty { exportSession(for: log) }
        samples.removeAll()
        return log
    }

    /// Throws away the in-progress flight without writing anything.
    func discard() {
        current = nil
        samples.removeAll()
        lastTrackPoint = nil
    }

    // MARK: Disk

    private func save(_ log: FlightLog) {
        let url = directory.appendingPathComponent("\(log.id.uuidString).json")
        guard let data = try? JSONEncoder.trackSession.encode(log) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Writes an RRCC-shaped `TrackSession-*.json` alongside the log.
    private func exportSession(for log: FlightLog) {
        // Thin to 5-second resolution — plenty for analysis, a fraction of the size.
        var thinned: [FlightSample] = []
        var lastT: Date?
        for s in samples {
            if let lt = lastT, s.t.timeIntervalSince(lt) < 5 { continue }
            lastT = s.t
            thinned.append(s)
        }

        let meta = SessionMeta(
            start: log.startedAt,
            duration: log.duration,
            distance: log.distanceM,
            totalAscent: totalAscent(),
            totalDescent: totalDescent(),
            deviceModel: DeviceInfo.model,
            mode: "In Flight",
            nominalRateHz: 1,
            capturePath: log.isSimulated ? "simulated" : "live-sensors",
            startingTank: samples.first?.tank,
            endingTank: samples.last?.tank
        )

        let file = TrackSessionFile(samples: thinned, meta: meta)
        let stamp = Self.stampFormatter.string(from: log.startedAt)
        let url = directory.appendingPathComponent("TrackSession-\(stamp).json")
        guard let data = try? JSONEncoder.trackSession.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func totalAscent() -> Double {
        zip(samples, samples.dropFirst())
            .reduce(0) { $0 + max(0, $1.1.alt - $1.0.alt) }
    }

    private func totalDescent() -> Double {
        zip(samples, samples.dropFirst())
            .reduce(0) { $0 + max(0, $1.0.alt - $1.1.alt) }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    // MARK: Reading

    func loadAll() -> [FlightLog] {
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("TrackSession-") }
            .compactMap { url -> FlightLog? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.trackSession.decode(FlightLog.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func delete(_ log: FlightLog) {
        let url = directory.appendingPathComponent("\(log.id.uuidString).json")
        try? fm.removeItem(at: url)
    }

    /// Exported session files, newest first — used by the share/replay UI.
    func exportedSessions() -> [URL] {
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return files
            .filter { $0.lastPathComponent.hasPrefix("TrackSession-") }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da > db
            }
    }
}

enum DeviceInfo {
    /// Hardware identifier, e.g. "iPhone17,1" — matches what RRCC records.
    static var model: String {
        // On the simulator `uname` reports the *host* architecture, which would
        // put "arm64" in the export. The simulated device is in the environment.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var sysinfo = utsname()
        uname(&sysinfo)
        let raw = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) }
        }
        return raw ?? "unknown"
    }
}
