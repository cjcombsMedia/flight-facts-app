import Foundation
import CoreLocation

/// A bundled airport, enough to plan a great-circle route offline.
struct Airport: Codable, Identifiable, Hashable {
    /// IATA code, e.g. "PHX".
    var id: String
    var name: String
    var city: String
    var country: String
    var lat: Double
    var lon: Double
    /// Field elevation, metres.
    var elev: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var label: String { "\(id) · \(city)" }
}

final class AirportStore {

    static let shared = AirportStore()

    private(set) var all: [Airport] = []
    private var byCode: [String: Airport] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("airports.json missing from bundle")
            return
        }
        do {
            all = try JSONDecoder().decode([Airport].self, from: data)
            byCode = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        } catch {
            assertionFailure("airports.json failed to decode: \(error)")
        }
    }

    /// Closest bundled airport within `radius` metres, if any.
    func nearest(to coord: CLLocationCoordinate2D, within radius: Double) -> Airport? {
        all.lazy
            .map { ($0, Geo.distance($0.coordinate, coord)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?
            .0
    }

    func airport(_ code: String) -> Airport? {
        byCode[code.uppercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Fuzzy search over code, city and name. Exact code match always wins.
    func search(_ query: String, limit: Int = 8) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }

        var scored: [(Airport, Int)] = []
        for a in all {
            let code = a.id.lowercased()
            let city = a.city.lowercased()
            let name = a.name.lowercased()

            let score: Int
            if code == q                     { score = 0 }
            else if code.hasPrefix(q)        { score = 1 }
            else if city.hasPrefix(q)        { score = 2 }
            else if city.contains(q)         { score = 3 }
            else if name.contains(q)         { score = 4 }
            else                             { continue }
            scored.append((a, score))
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }
            .prefix(limit)
            .map(\.0)
    }
}
