import Foundation
import CoreLocation

/// The offline landmark corpus.
///
/// This is deliberately bundled rather than fetched: at 38,000 ft you usually
/// have no usable connectivity, and an app about what you are flying over is
/// worthless if it needs Wi-Fi to say anything.
final class LandmarkStore {

    static let shared = LandmarkStore()

    private(set) var all: [POI] = []

    private init() { load() }

    private func load() {
        guard let url = Bundle.main.url(forResource: "landmarks", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("landmarks.json missing from bundle")
            return
        }
        do {
            all = try JSONDecoder().decode([POI].self, from: data)
        } catch {
            assertionFailure("landmarks.json failed to decode: \(error)")
        }
    }

    /// A POI that is currently worth talking about, with the geometry worked out.
    struct Candidate {
        let poi: POI
        let distanceM: Double
        let bearing: Double
        let clock: Int
        let side: POISighting.Side
        /// Mutable so callers can apply their own weighting — seat bias, mainly.
        var score: Double
    }

    /// Everything in range of the aircraft right now, best first.
    ///
    /// "In range" combines three things: the POI's own `reach` (the Grand Canyon
    /// is worth mentioning from further away than a museum), the geometric
    /// horizon at the current altitude, and whether the thing is actually ahead
    /// of us — there is no point telling someone to look at something they
    /// passed four minutes ago.
    func candidates(at coord: CLLocationCoordinate2D,
                    course: Double,
                    altitudeM: Double,
                    excluding seen: Set<String>) -> [Candidate] {

        let horizonM = max(40_000, Geo.horizonDistance(altitudeM: altitudeM))

        return all.compactMap { poi -> Candidate? in
            guard !seen.contains(poi.id) else { return nil }

            let d = Geo.distance(coord, poi.coordinate)
            let reachM = poi.reach * 1_000
            guard d <= min(reachM, horizonM) else { return nil }

            let bearing = Geo.bearing(from: coord, to: poi.coordinate)
            let off = abs(Geo.angleDelta(course, bearing))
            // Anything more than ~110° off the nose is behind the wing line.
            guard off < 110 else { return nil }

            // Prefer high-wow, close, and ahead.
            let proximity = 1 - (d / reachM)                 // 0...1
            let ahead = 1 - (off / 110)                      // 0...1
            let score = Double(poi.wow) + proximity * 25 + ahead * 20

            let rel = Geo.relativePosition(course: course, bearingToTarget: bearing)
            return Candidate(
                poi: poi,
                distanceM: d,
                bearing: bearing,
                clock: rel.clock,
                side: rel.side,
                score: score
            )
        }
        .sorted { $0.score > $1.score }
    }
}
