import Foundation
import MapKit

/// Warms MapKit's tile cache along a planned route, on the ground, over Wi-Fi.
///
/// **What this actually is.** MapKit has no public tile-prefetch API and no
/// supported offline mode. What it does have is `MKMapSnapshotter`, which renders
/// a region through the same tile pipeline the live map uses — and those tiles
/// land in MapKit's shared on-disk cache. Rendering snapshots along the corridor
/// therefore pulls the tiles you're about to fly over into that cache.
///
/// **The honest caveat.** The cache is managed by the system, not by us. It has
/// no documented size, no eviction policy we can see, and no guarantee. This
/// reliably makes the map much faster; it does not make it work in a Faraday
/// cage. Treat it as a warm start, not offline maps.
@MainActor
@Observable
final class TilePrefetcher {

    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        case finished(tiles: Int, bytesHint: Int)
        case failed(String)

        var isRunning: Bool { if case .running = self { return true }; return false }

        var progress: Double {
            guard case .running(let done, let total) = self, total > 0 else { return 0 }
            return Double(done) / Double(total)
        }
    }

    private(set) var state: State = .idle

    private var tasks: [MKMapSnapshotter] = []
    private var cancelled = false

    /// Zoom bands to warm, as the ground width one snapshot should cover.
    ///
    /// The cruise band is what matters most — that's the camera distance the map
    /// sits at for hours. The terminal band covers the first and last 150 km,
    /// where you're low and the map is zoomed in.
    private let cruiseSpanM: Double = 260_000
    private let terminalSpanM: Double = 45_000

    func cancel() {
        cancelled = true
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        state = .idle
    }

    func prefetch(plan: FlightPlan, style: AppSettings.MapStyleChoice) {
        guard !state.isRunning else { return }
        cancelled = false

        let regions = plannedRegions(for: plan)
        guard !regions.isEmpty else { state = .failed("Route is too short to prefetch."); return }

        state = .running(done: 0, total: regions.count)

        Task { @MainActor in
            var done = 0
            var failures = 0

            // Serial with a small look-ahead. MapKit throttles aggressively and
            // hammering it in parallel gets requests dropped, not sped up.
            for region in regions {
                if cancelled { return }
                let ok = await snapshot(region: region, style: style)
                if !ok { failures += 1 }
                done += 1
                if cancelled { return }
                state = .running(done: done, total: regions.count)
            }

            if failures == regions.count {
                state = .failed("Couldn't reach the map servers. Try again on Wi-Fi.")
            } else {
                // Rough hint only — we can't see the cache, so this is derived
                // from regions covered, not measured bytes.
                state = .finished(tiles: regions.count, bytesHint: regions.count * 900_000)
            }
        }
    }

    // MARK: Region planning

    private func plannedRegions(for plan: FlightPlan) -> [MKCoordinateRegion] {
        let path = plan.waypoints
        guard path.count > 1 else { return [] }

        var regions: [MKCoordinateRegion] = []
        var lastCentre: CLLocationCoordinate2D?

        // Cruise band: step along the route at ~70% of a snapshot's width so
        // adjacent snapshots overlap and we don't leave unwarmed seams.
        let stride = cruiseSpanM * 0.7
        for point in path {
            if let last = lastCentre, Geo.distance(last, point) < stride { continue }
            lastCentre = point
            regions.append(MKCoordinateRegion(center: point,
                                              latitudinalMeters: cruiseSpanM,
                                              longitudinalMeters: cruiseSpanM))
        }

        // Terminal bands: closer zoom around each end.
        for end in [plan.origin.coordinate, plan.destination.coordinate] {
            for bearing in stride0(from: 0, to: 360, by: 90) {
                let c = Geo.destination(from: end, bearing: bearing, distance: 30_000)
                regions.append(MKCoordinateRegion(center: c,
                                                  latitudinalMeters: terminalSpanM,
                                                  longitudinalMeters: terminalSpanM))
            }
        }

        // A long-haul route would otherwise queue hundreds of snapshots.
        return Array(regions.prefix(140))
    }

    private func stride0(from: Double, to: Double, by: Double) -> [Double] {
        var out: [Double] = []
        var v = from
        while v < to { out.append(v); v += by }
        return out
    }

    // MARK: Snapshot

    private func snapshot(region: MKCoordinateRegion,
                          style: AppSettings.MapStyleChoice) async -> Bool {
        let options = MKMapSnapshotter.Options()
        options.region = region
        // Small output: we want the tile fetch, not the bitmap. A big image
        // costs memory and buys nothing.
        options.size = CGSize(width: 512, height: 512)
        // Match the live map's configuration exactly (flat elevation), so the
        // tiles warmed here are the same tiles the map will ask for in flight.
        // The old `.hybridFlyover` map type warmed a different tile set.
        switch style {
        case .hybrid:   options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        case .imagery:  options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        case .standard: options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        }

        let snapshotter = MKMapSnapshotter(options: options)
        tasks.append(snapshotter)
        defer { tasks.removeAll { $0 === snapshotter } }

        return await withCheckedContinuation { continuation in
            snapshotter.start(with: .global(qos: .utility)) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}
