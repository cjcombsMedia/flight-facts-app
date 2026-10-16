import Foundation
import CoreLocation

/// Which side of the cabin the user is sitting on. Drives which window we point
/// them at, and biases POI ranking toward things they can actually see.
enum SeatSide: String, Codable, CaseIterable, Identifiable {
    case left, right, centre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left:   return "Left"
        case .right:  return "Right"
        case .centre: return "Middle / aisle"
        }
    }

    var glyph: String {
        switch self {
        case .left:   return "arrow.left"
        case .right:  return "arrow.right"
        case .centre: return "arrow.up.and.down"
        }
    }

    var blurb: String {
        switch self {
        case .left:   return "Port side — facts favour things off your left wing."
        case .right:  return "Starboard side — facts favour things off your right wing."
        case .centre: return "No window bias. You'll get everything either side."
        }
    }

    /// Best guess from a seat like "12A" or "34K".
    ///
    /// Works for the common layouts: on a 3-3 narrowbody A is the left window
    /// and F the right; on a 3-4-3 widebody A is left and K is right. Letters in
    /// the middle block are genuinely ambiguous, so they map to `.centre` and the
    /// user can override.
    static func infer(fromSeat seat: String) -> SeatSide? {
        guard let letter = seat.uppercased().last(where: { $0.isLetter }) else { return nil }
        switch letter {
        case "A", "B", "C":                return .left
        case "D", "E":                     return .centre
        case "F", "G", "H", "J", "K":      return .right
        default:                           return nil
        }
    }
}

/// A planned route, entered before departure. Used for three things: prefetching
/// map tiles, previewing what you'll fly over, and biasing POIs to your window.
struct FlightPlan: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var origin: Airport
    var destination: Airport
    var seat: SeatSide = .centre
    /// Optional, cosmetic — we don't look it up.
    var flightNumber: String?

    /// Great-circle path, sampled roughly every 50 km.
    var waypoints: [CLLocationCoordinate2D] {
        let d = Geo.distance(origin.coordinate, destination.coordinate)
        let steps = max(2, min(400, Int(d / 50_000)))
        return (0...steps).map {
            Geo.interpolate(origin.coordinate, destination.coordinate,
                            Double($0) / Double(steps))
        }
    }

    var distanceM: Double {
        Geo.distance(origin.coordinate, destination.coordinate)
    }

    /// Rough block time: cruise at ~460 kt plus 40 minutes of taxi, climb and descent.
    var estimatedDuration: TimeInterval {
        distanceM / 237.0 + 2_400
    }

    var title: String { "\(origin.id) → \(destination.id)" }

    // Coordinates aren't Codable, so persist the airports and recompute the path.
    enum CodingKeys: String, CodingKey {
        case id, origin, destination, seat, flightNumber
    }

    /// POIs the route will pass within reach of, in order — the pre-flight preview.
    func anticipatedPOIs() -> [(poi: POI, side: SeatSide)] {
        let path = waypoints
        guard path.count > 1 else { return [] }

        var seen = Set<String>()
        var out: [(POI, SeatSide)] = []

        for (i, point) in path.enumerated() {
            let next = path[min(i + 1, path.count - 1)]
            let course = Geo.bearing(from: point, to: next)

            for poi in LandmarkStore.shared.all {
                guard !seen.contains(poi.id) else { continue }
                let d = Geo.distance(point, poi.coordinate)
                guard d <= poi.reach * 1_000 else { continue }
                seen.insert(poi.id)

                let bearing = Geo.bearing(from: point, to: poi.coordinate)
                let rel = Geo.relativePosition(course: course, bearingToTarget: bearing)
                let side: SeatSide = rel.side == .left ? .left
                                   : rel.side == .right ? .right : .centre
                out.append((poi, side))
            }
        }
        return out
    }
}

/// Persists the active plan across launches — you enter it at the gate, and it
/// still has to be there after the phone locks for twenty minutes.
enum FlightPlanStore {
    private static let key = "activeFlightPlan"

    static var active: FlightPlan? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(FlightPlan.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
