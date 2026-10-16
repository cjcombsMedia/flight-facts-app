import Foundation
import SwiftUI
import CoreLocation
import UIKit

/// The single object the UI talks to.
///
/// Owns the sample source, the detector and every content producer, and turns
/// the sample stream into the bubble feed. Deliberately source-agnostic: a demo
/// flight, a replayed RRCC file and a real aircraft all arrive here as
/// `FlightSample`s and take exactly the same path through the app.
@Observable
@MainActor
final class FlightEngine {

    enum State: Equatable {
        case idle
        /// Sensors running, detector looking for a flight.
        case scanning
        /// Flight confirmed — the full experience is live.
        case flying
        case finished
    }

    enum Mode: Equatable {
        case live
        case demo(DemoRoute)
        case replay(String)

        var isSimulated: Bool { if case .live = self { return false }; return true }
        var label: String {
            switch self {
            case .live:            return "Live sensors"
            case .demo(let r):     return "Demo · \(r.name)"
            case .replay(let n):   return "Replay · \(n)"
            }
        }
    }

    enum GPSStatus: Equatable {
        case searching, good, weak, estimated

        var label: String {
            switch self {
            case .searching: return "Finding GPS"
            case .good:      return "GPS"
            case .weak:      return "Weak GPS"
            case .estimated: return "GPS lost · estimating"
            }
        }
    }

    // MARK: Published state

    private(set) var state: State = .idle {
        // Single choke point, so the idle timer can never be left disabled by a
        // path that forgot to re-enable it.
        didSet { syncIdleTimer() }
    }
    private(set) var mode: Mode = .live
    private(set) var phase: FlightPhase = .unknown
    private(set) var signals = DetectionSignals()
    private(set) var latest: FlightSample?
    private(set) var bubbles: [Bubble] = []
    private(set) var sightings: [POISighting] = []
    /// Flown route for the map. Thinned as it grows so the polyline stays cheap.
    private(set) var track: [CLLocationCoordinate2D] = []
    private(set) var flightStartedAt: Date?
    private(set) var lastSavedLog: FlightLog?

    /// Course for the map camera: smoothed, and frozen when slow. The raw GPS
    /// course swings wildly when stationary, which is what spun the map.
    /// Nil until we've actually moved — the map stays north-up until then.
    private(set) var displayCourse: Double?

    /// Set when a notification tap should scroll the feed to a specific bubble.
    var focusBubbleID: UUID?

    /// Route entered before departure, if any.
    private(set) var plan: FlightPlan?
    /// The plan's great-circle path, computed once rather than on every redraw.
    private(set) var planPath: [CLLocationCoordinate2D] = []
    var showPlannedRoute = true

    let prefetcher = TilePrefetcher()
    let connectivity = Connectivity()

    var region: String? { scout.currentRegion }
    var country: String? { scout.currentCountry }
    var isOnline: Bool { connectivity.isOnline }
    var locationAuthorization: CLAuthorizationStatus { liveSource.authorization }
    var liveActivityRunning: Bool { liveActivity.isRunning }

    var gpsStatus: GPSStatus {
        guard let s = latest else { return .searching }
        if s.isEstimated { return .estimated }
        return s.hAcc > 65 ? .weak : .good
    }

    /// Ground phases only count as a flight at an airport — otherwise starting
    /// the scanner in the car on the way there "detected" a takeoff roll on the
    /// highway.
    var isNearAirport: Bool {
        if mode.isSimulated { return true }
        guard let s = latest else { return false }
        if let origin = plan?.origin, Geo.distance(origin.coordinate, s.coordinate) < 8_000 { return true }
        return AirportStore.shared.nearest(to: s.coordinate, within: 8_000) != nil
    }

    // MARK: Collaborators

    private let detector = FlightDetector()
    private let recorder = FlightRecorder()
    private let scout = POIScout()
    private let advisor = CabinAdvisor()
    private let milestones = MilestoneWatcher()
    private let sky = SkyFacts()
    private let claude = ClaudeFactService()
    private let liveSource = LiveSensorSource()
    private let liveActivity = LiveActivityController()
    private let settings = AppSettings.shared

    private var source: SampleSource?
    private var seenPOIs = Set<String>()
    private var discoveredPOIs: [POI] = []
    private var takeoffAt: Date?
    /// Most recent bubble worth putting on the Lock Screen.
    private var headline: Bubble?

    // Cadence, all in *sample* time so it scales correctly under replay.
    private var lastPOIScan: Date?
    private var lastHangarTalk: Date?
    private var lastAIFact: Date?
    // These two are wall-clock: they pace things the user perceives in real time.
    private var lastNotificationWall: Date?
    private var lastActivityStatsWall: Date?

    private let aiFactInterval: TimeInterval = 600
    /// Real-time floor between notifications, so a 60× demo doesn't machine-gun them.
    private let notificationFloor: TimeInterval = 6

    private var density: AppSettings.FactDensity { settings.factDensity }

    init() {
        if let saved = FlightPlanStore.active { applyPlan(saved) }
        scout.onRegionChange = { [weak self] region, country, isNewCountry in
            self?.handleRegionChange(region, country, isNewCountry)
        }
        scout.onDiscovered = { [weak self] pois in
            self?.discoveredPOIs.append(contentsOf: pois)
        }
        // Sources and the detector all fire on the main run loop, so handle
        // phase changes synchronously — an async hop let a sample race ahead of
        // the transition it caused.
        detector.onPhaseChange = { [weak self] from, to in
            MainActor.assumeIsolated { self?.handlePhaseChange(from: from, to: to) }
        }
        NotificationService.shared.onTapped = { [weak self] id in
            self?.focusBubbleID = id
        }
    }

    // MARK: Screen

    /// Hold the screen on while a flight is live, so you can glance at the map
    /// without unlocking. iOS would otherwise dim after 30 seconds.
    private func syncIdleTimer() {
        let awake = settings.keepScreenAwake && (state == .flying || state == .scanning)
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    func refreshScreenAwakePreference() { syncIdleTimer() }

    // MARK: Plan

    func setPlan(_ plan: FlightPlan?) {
        applyPlan(plan)
        FlightPlanStore.active = plan
    }

    private func applyPlan(_ plan: FlightPlan?) {
        self.plan = plan
        planPath = plan?.waypoints ?? []
    }

    // MARK: Permissions

    func requestPermissions() {
        liveSource.requestPermissions()
        NotificationService.shared.requestAuthorization()
    }

    func refreshPermissionStatus() {
        NotificationService.shared.refreshAuthorizationStatus()
    }

    // MARK: Control

    func startScanning(mode: Mode = .live) {
        guard state == .idle || state == .finished else { return }

        self.mode = mode
        resetAll()

        switch mode {
        case .live:
            source = liveSource
            detector.destinationElevation = plan?.destination.elev
        case .demo(let route):
            source = SyntheticFlightSource(route: route, speed: settings.demoSpeed)
            detector.destinationElevation = route.destElevation
        case .replay(let name):
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let replay = ReplaySource(url: url, speed: settings.demoSpeed) else { return }
            source = replay
            detector.destinationElevation = plan?.destination.elev
        }
        state = .scanning

        source?.onSample = { [weak self] sample in
            MainActor.assumeIsolated { self?.ingest(sample) }
        }
        source?.start()

        emit(Bubble(
            kind: .system,
            title: "Sensors live",
            body: mode.isSimulated
                ? "Running \(mode.label). Same pipeline a real flight uses."
                : "GPS, barometer and motion are running. Watching for a flight.",
            detail: ["Open this at the gate, on the taxiway or at 38,000 feet — the detector works out where you already are.",
                     "Everything works in airplane mode. GPS stays on; only the map tiles need a connection, and preloading covers those."],
            priority: .low
        ), notify: false)
    }

    func stop(save: Bool = true) {
        source?.stop()
        source?.onSample = nil
        source = nil
        claude.cancel()
        liveActivity.end(final: save ? activityState() : nil)

        if save, recorder.current != nil {
            lastSavedLog = recorder.end(at: latest?.t ?? Date())
            state = .finished
        } else {
            recorder.discard()
            state = .idle
        }
    }

    private func resetAll() {
        detector.reset()
        advisor.reset()
        milestones.reset()
        sky.reset()
        scout.reset()
        AviationHistory.shared.resetRotation()
        bubbles.removeAll()
        sightings.removeAll()
        track.removeAll()
        seenPOIs.removeAll()
        discoveredPOIs.removeAll()
        latest = nil
        displayCourse = nil
        headline = nil
        phase = .unknown
        flightStartedAt = nil
        takeoffAt = nil
        lastSavedLog = nil
        lastPOIScan = nil
        lastHangarTalk = nil
        lastAIFact = nil
        lastActivityStatsWall = nil
        scout.isEnabled = settings.onlineEnrichment
        NotificationService.shared.clearDelivered()
    }

    // MARK: The pipeline

    private func ingest(_ s: FlightSample) {
        latest = s
        detector.ingest(s)          // may call handlePhaseChange synchronously
        signals = detector.signals
        phase = detector.phase

        updateDisplayCourse(s)
        appendTrack(s)
        recorder.ingest(s)

        // Online enrichment only when there's a network and a real fix — no
        // point geocoding a dead-reckoned guess, or retrying in airplane mode.
        if settings.onlineEnrichment, connectivity.isOnline, !s.isEstimated {
            scout.update(coordinate: s.coordinate, altitudeM: s.alt)
        }
        recorder.noteRegion(scout.currentRegion)

        guard state == .flying else { return }

        for bubble in milestones.check(s, phase: phase) { emit(bubble) }
        if let ambient = advisor.ambientAdvice(for: s, phase: phase) { emit(ambient) }

        scanForPOIs(s)
        maybeHangarTalk(s)
        maybeAIFact(s)
        refreshLiveActivityStats()
    }

    private func updateDisplayCourse(_ s: FlightSample) {
        // Only steer the map when genuinely moving on a real fix.
        guard !s.isEstimated, s.spd >= 6 else { return }
        guard let current = displayCourse else { displayCourse = s.course; return }
        // Exponential smoothing on the circle: settles a turn in a few seconds,
        // ignores single-fix wobble.
        let next = current + Geo.angleDelta(current, s.course) * 0.4
        displayCourse = (next + 360).truncatingRemainder(dividingBy: 360)
    }

    private func appendTrack(_ s: FlightSample) {
        // Space points by distance, not time: nothing accumulates at the gate,
        // and at cruise a point every few seconds is plenty for the map.
        let spacing = max(300, s.spd * 4)
        if let last = track.last, Geo.distance(last, s.coordinate) < spacing { return }
        track.append(s.coordinate)

        // Thin the older history when it gets long, keeping the recent tail sharp.
        if track.count > 1_500 {
            let tail = 200
            let head = track.dropLast(tail)
            track = stride(from: head.startIndex, to: head.endIndex, by: 2).map { head[$0] }
                + track.suffix(tail)
        }
    }

    // MARK: Phase transitions

    private func handlePhaseChange(from: FlightPhase, to: FlightPhase) {
        phase = to

        if state == .scanning {
            // Airborne is unambiguous. A ground phase only counts at an airport.
            let groundStart = (to == .taxi || to == .takeoffRoll) && isNearAirport
            if to.isAirborne || groundStart {
                beginFlight(at: latest?.t ?? Date())
            }
        }

        guard state == .flying, let s = latest else { return }

        if to.isAirborne, takeoffAt == nil {
            takeoffAt = s.t
            milestones.noteFlightStart(s.t)
        }

        if let advice = advisor.advice(entering: to, from: from, sample: s) {
            emit(advice)
        }

        if to == .landed {
            emitArrivalSummary()
            // Give the log a beat to catch the summary bubble, then close it.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.stop(save: true)
            }
        }
    }

    private func beginFlight(at date: Date) {
        state = .flying
        flightStartedAt = date
        track.removeAll()           // drop the drive to the gate from the map
        recorder.begin(at: date, simulated: mode.isSimulated)

        haptic(.success)

        emit(Bubble(
            kind: .system,
            title: "Flight detected",
            body: detectionSummary(),
            detail: signals.evidence,
            priority: .high
        ))

        // Aviation history is date-driven, so it's a natural opener.
        for entry in AviationHistory.shared.nearbyAnniversaries(on: date).prefix(2) {
            let years = AviationHistory.shared.yearsAgo(entry)
            emit(Bubble(
                kind: .aviation,
                title: entry.title,
                body: entry.text,
                detail: ["\(years) years ago \(sameDay(entry, as: date) ? "today" : "this week"), in \(entry.year)."],
                priority: .normal
            ))
        }

        if settings.liveActivityEnabled {
            liveActivity.start(routeTitle: routeTitle, seatLabel: plan.map { "\($0.seat.label) seat" },
                               state: activityState())
        }
    }

    private func sameDay(_ entry: AviationHistory.OnThisDay, as date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return c.month == entry.month && c.day == entry.day
    }

    private func detectionSummary() -> String {
        switch phase {
        case .taxi:        return "You're on the ground and moving. Locked on — I'll track from here."
        case .takeoffRoll: return "Takeoff roll detected. Hold on."
        case .climb:       return "You're climbing out. Locked on."
        case .cruise:      return "You're already at cruise — \(Units.feet(signals.altitude)), \(Units.knots(signals.speed)). Picked it up mid-flight."
        case .descent:     return "You're already on the way down. Jumping in late but I'll keep up."
        case .approach:    return "You're on approach. Cutting it fine, but we're in."
        default:           return "Flight activity detected."
        }
    }

    private func emitArrivalSummary() {
        let poiCount = sightings.count
        let alt = recorder.current?.maxAltitudeM ?? 0
        let dist = recorder.current?.distanceM ?? 0

        emit(Bubble(
            kind: .milestone,
            title: "Wheels down",
            body: poiCount > 0
                ? "You flew over \(poiCount) point\(poiCount == 1 ? "" : "s") of interest, topped out at \(Units.feet(alt)) and covered \(Units.miles(dist))."
                : "Topped out at \(Units.feet(alt)) and covered \(Units.miles(dist)).",
            detail: ["The whole flight is saved to your log, including every POI.",
                     "The raw sensor track exported in TrackSession format too."],
            priority: .high
        ))
    }

    // MARK: POI scouting

    private func scanForPOIs(_ s: FlightSample) {
        if let last = lastPOIScan, s.t.timeIntervalSince(last) < density.poiInterval { return }
        lastPOIScan = s.t

        // Nothing useful to say about the ground while still on it.
        guard phase.isAirborne else { return }

        var candidates = LandmarkStore.shared.candidates(
            at: s.coordinate, course: s.course, altitudeM: s.alt, excluding: seenPOIs
        )

        // Fold in anything MapKit turned up, scored the same way.
        candidates += discoveredCandidates(at: s)

        // Seat bias: if we know which window they're at, favour things they can
        // actually see. It's a nudge, not a filter — a big landmark on the far
        // side is still worth crossing the aisle for.
        if let seat = plan?.seat, seat != .centre {
            candidates = candidates.map { c in
                var c = c
                let matches = (seat == .left && c.side == .left)
                           || (seat == .right && c.side == .right)
                           || c.side == .ahead
                c.score += matches ? 22 : -12
                return c
            }
        }
        candidates.sort { $0.score > $1.score }

        for candidate in candidates.prefix(density.poiBatch) {
            announce(candidate, at: s)
        }
    }

    private func announce(_ best: LandmarkStore.Candidate, at s: FlightSample) {
        seenPOIs.insert(best.poi.id)

        let sighting = POISighting(
            poi: best.poi,
            at: s.t,
            distanceKm: best.distanceM / 1_000,
            clock: best.clock,
            side: best.side,
            altitudeM: s.alt
        )
        sightings.append(sighting)

        // While GPS is out the position is an estimate; say so rather than
        // quote a precise distance we don't actually have.
        let distance = s.isEstimated ? "roughly \(Units.miles(best.distanceM))" : Units.miles(best.distanceM)

        let where_: String
        if best.side == .ahead {
            where_ = "Dead ahead, \(distance) out."
        } else if let seat = plan?.seat, seat != .centre,
                  (seat == .left && best.side == .right) || (seat == .right && best.side == .left) {
            // Be straight with them: it's on the other side of the aisle.
            where_ = "Other side of the aircraft — \(best.side.label), \(distance)."
        } else {
            where_ = "Out the \(best.side.label) — \(best.clock) o'clock, \(distance)."
        }

        var detail = Array(best.poi.facts.dropFirst())
        if let region = best.poi.region { detail.append("📍 \(region)") }

        emit(Bubble(
            kind: .poi,
            title: "\(best.poi.kind.glyph) \(best.poi.name)",
            body: "\(where_) \(best.poi.facts.first ?? "")",
            detail: detail,
            sighting: sighting,
            priority: best.poi.wow >= 88 ? .high : .normal
        ))

        // A POI with an aviation tie-in gets a second, separate bubble so the
        // history reads as its own voice rather than a footnote.
        if let aviation = best.poi.aviation {
            emit(Bubble(
                kind: .aviation,
                title: "Hangar talk: \(best.poi.name)",
                body: aviation,
                priority: .low
            ))
        }
    }

    private func discoveredCandidates(at s: FlightSample) -> [LandmarkStore.Candidate] {
        discoveredPOIs.compactMap { poi in
            guard !seenPOIs.contains(poi.id) else { return nil }
            let d = Geo.distance(s.coordinate, poi.coordinate)
            guard d <= poi.reach * 1_000 else { return nil }
            let bearing = Geo.bearing(from: s.coordinate, to: poi.coordinate)
            let off = abs(Geo.angleDelta(s.course, bearing))
            guard off < 110 else { return nil }
            let rel = Geo.relativePosition(course: s.course, bearingToTarget: bearing)
            return LandmarkStore.Candidate(
                poi: poi, distanceM: d, bearing: bearing,
                clock: rel.clock, side: rel.side,
                score: Double(poi.wow) + (1 - d / (poi.reach * 1_000)) * 25
            )
        }
    }

    // MARK: Filler content

    /// Filler for the long quiet stretches — sky facts first (they're tied to
    /// where and when you actually are), then hangar talk from the pool.
    private func maybeHangarTalk(_ s: FlightSample) {
        guard phase.isAirborne else { return }
        if let last = lastHangarTalk, s.t.timeIntervalSince(last) < density.fillerInterval { return }
        // Don't talk over a POI that just landed in the feed.
        if let newest = bubbles.last, s.t.timeIntervalSince(newest.at) < 45 { return }
        lastHangarTalk = s.t

        if let skyFact = sky.check(s, phase: phase) {
            emit(skyFact)
            return
        }
        guard phase == .cruise, let talk = AviationHistory.shared.nextHangarTalk() else { return }
        emit(Bubble(kind: .aviation, title: talk.title, body: talk.text, priority: .low))
    }

    private func maybeAIFact(_ s: FlightSample) {
        guard settings.aiFactsEnabled, claude.isEnabled, connectivity.isOnline,
              phase.isAirborne, !s.isEstimated else { return }
        if let last = lastAIFact, s.t.timeIntervalSince(last) < aiFactInterval { return }
        lastAIFact = s.t

        let context = ClaudeFactService.Context(
            lat: s.lat, lon: s.lon, altitudeM: s.alt,
            region: scout.currentRegion, country: scout.currentCountry,
            nearby: sightings.suffix(6).map(\.poi.name),
            date: s.t
        )
        claude.fact(for: context) { [weak self] bubble in
            self?.emit(bubble)
        }
    }

    // MARK: Region crossings

    private func handleRegionChange(_ region: String?, _ country: String?, _ isNewCountry: Bool) {
        guard state == .flying, let region else { return }

        if isNewCountry, let country {
            emit(Bubble(
                kind: .milestone,
                title: "🗺️ Now over \(country)",
                body: "You've crossed a border at \(Units.feet(latest?.alt ?? 0)).",
                detail: region.isEmpty ? [] : ["Currently over \(region)."],
                priority: .high
            ))
        } else {
            emit(Bubble(
                kind: .milestone,
                title: "Now over \(region)",
                body: "Crossed in at \(Units.feet(latest?.alt ?? 0)), heading \(Units.compass(latest?.course ?? 0)).",
                priority: .low
            ))
        }
    }

    // MARK: Lock Screen

    private var routeTitle: String {
        if let plan { return plan.title }
        if case .demo(let route) = mode { return route.name }
        return scout.currentRegion ?? "Flight Facts"
    }

    /// Origin and destination for progress, from the plan or the demo route.
    private var routeEnds: (CLLocationCoordinate2D, CLLocationCoordinate2D)? {
        if let plan { return (plan.origin.coordinate, plan.destination.coordinate) }
        if case .demo(let route) = mode, let a = route.waypoints.first, let b = route.waypoints.last {
            return (a, b)
        }
        return nil
    }

    private func activityState() -> FlightActivityAttributes.ContentState {
        let s = latest
        let alt = s?.alt ?? 0
        let imperial = settings.useImperial
        let fact = headline

        var progress: Double?
        var remaining: String?
        if let s, let ends = routeEnds {
            let (a, b) = ends
            let total = Geo.distance(a, b)
            let left = Geo.distance(s.coordinate, b)
            if total > 0 {
                progress = min(1, max(0, 1 - left / total))
                remaining = left < 3_000 ? "Arriving" : "\(Units.miles(left)) to go"
            }
        }

        return .init(
            phaseRaw: phase.rawValue,
            phaseTitle: phase.title,
            phaseGlyph: phase.glyph,
            altitudeText: imperial ? Units.feet(alt) : "\(Int(alt)) m",
            altitudeShort: String(format: "%.1fk", (imperial ? alt * 3.280839895 : alt) / 1_000),
            speedText: s.map { imperial ? Units.mph($0.spd) : "\(Int($0.spd * 3.6)) km/h" } ?? "—",
            factGlyph: fact?.kind.glyph ?? "🛰️",
            factSpeaker: fact?.kind.speaker ?? "Flight Deck",
            factTitle: fact?.title ?? "Watching the ground",
            factBody: fact?.body ?? "The next landmark will show up here.",
            progress: progress,
            remainingText: remaining,
            gpsEstimated: s?.isEstimated ?? false,
            poiCount: sightings.count,
            updatedAt: s?.t ?? Date()
        )
    }

    /// Numbers drift between facts; refresh them on a slow wall-clock beat.
    private func refreshLiveActivityStats() {
        guard liveActivity.isRunning else { return }
        let now = Date()
        if let last = lastActivityStatsWall, now.timeIntervalSince(last) < 30 { return }
        lastActivityStatsWall = now
        liveActivity.update(activityState())
    }

    // MARK: Emission

    private func emit(_ bubble: Bubble, notify: Bool = true) {
        var b = bubble
        // Stamp in sample time so replays and demos read with a coherent clock.
        if let t = latest?.t { b.at = t }

        bubbles.append(b)
        if bubbles.count > 300 { bubbles.removeFirst(bubbles.count - 300) }
        recorder.record(b)

        if notify, shouldNotify(b) {
            lastNotificationWall = Date()
            NotificationService.shared.post(b)
        }
        if b.priority == .high { haptic(.warning) }

        // The Lock Screen shows the latest *fact*, not housekeeping.
        if b.kind != .system || b.priority == .high {
            headline = b
            liveActivity.update(activityState(), urgent: b.kind == .advice && b.priority == .high)
        }
    }

    private func shouldNotify(_ b: Bubble) -> Bool {
        guard settings.notificationsEnabled else { return false }
        switch b.kind {
        case .advice:   guard settings.notifyAdvice else { return false }
        case .poi:      guard settings.notifyPOI else { return false }
        case .system:   return b.priority == .high
        case .aviation, .stat, .ai: return false
        case .milestone: break
        }
        guard b.priority >= .normal else { return false }

        if let last = lastNotificationWall,
           Date().timeIntervalSince(last) < notificationFloor,
           b.priority != .high {
            return false
        }
        return true
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard settings.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: Log access

    func savedFlights() -> [FlightLog] { recorder.loadAll() }
    func delete(_ log: FlightLog) { recorder.delete(log) }
    func exportedSessionURLs() -> [URL] { recorder.exportedSessions() }
}
