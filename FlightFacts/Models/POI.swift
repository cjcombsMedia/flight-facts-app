import Foundation
import CoreLocation

/// A point of interest we can fly over and say something about.
struct POI: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var kind: Kind
    /// Roughly "how far away is this still worth mentioning", in km.
    /// The Grand Canyon is visible from a long way up; a small museum is not.
    var reach: Double
    /// 0–100. Drives ranking when several POIs are in range at once.
    var wow: Int
    /// The payload. First entry is the headline fact.
    var facts: [String]
    var region: String?
    /// Optional aviation-history tie-in, surfaced as its own bubble.
    var aviation: String?

    enum Kind: String, Codable, CaseIterable {
        case city, natural, landmark, water, mountain, desert, volcano
        case airport, aviation, science, ancient, oddity, border

        var glyph: String {
            switch self {
            case .city:     return "🏙️"
            case .natural:  return "🌲"
            case .landmark: return "🗿"
            case .water:    return "🌊"
            case .mountain: return "🏔️"
            case .desert:   return "🏜️"
            case .volcano:  return "🌋"
            case .airport:  return "🛫"
            case .aviation: return "✈️"
            case .science:  return "🔭"
            case .ancient:  return "🏛️"
            case .oddity:   return "👽"
            case .border:   return "🗺️"
            }
        }

        var label: String {
            switch self {
            case .city:     return "City"
            case .natural:  return "Nature"
            case .landmark: return "Landmark"
            case .water:    return "Water"
            case .mountain: return "Mountain"
            case .desert:   return "Desert"
            case .volcano:  return "Volcano"
            case .airport:  return "Airport"
            case .aviation: return "Aviation"
            case .science:  return "Science"
            case .ancient:  return "Ancient"
            case .oddity:   return "Oddity"
            case .border:   return "Border"
            }
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// A POI that actually got surfaced during a flight, with the flight context
/// attached. This is what ends up in the flight log.
struct POISighting: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var poi: POI
    /// When we called it out.
    var at: Date
    /// Slant distance from the aircraft when called out, km.
    var distanceKm: Double
    /// Clock-face bearing relative to the nose: 12 = dead ahead, 3 = right wing.
    var clock: Int
    /// Which side of the aircraft to look out of.
    var side: Side
    var altitudeM: Double

    enum Side: String, Codable {
        case left, right, ahead, behind

        var label: String {
            switch self {
            case .left:   return "left window"
            case .right:  return "right window"
            case .ahead:  return "straight ahead"
            case .behind: return "behind us"
            }
        }
    }
}
