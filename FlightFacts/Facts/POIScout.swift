import Foundation
import CoreLocation
import MapKit

/// Online enrichment on top of the bundled corpus.
///
/// Two jobs, both best-effort and both silently skipped when there is no
/// connectivity (the normal case in the air):
///
/// 1. **Region tracking** — reverse geocode occasionally so we can call out
///    "you just crossed into Utah". This is cheap, works from one fix, and is
///    the single highest-value online feature.
/// 2. **Local search** — ask MapKit what notable things are down there that our
///    bundled list does not know about.
final class POIScout {

    private let geocoder = CLGeocoder()

    private var lastGeocodeAt: Date?
    private var lastGeocodeCoord: CLLocationCoordinate2D?
    private(set) var currentRegion: String?
    private(set) var currentCountry: String?

    private var lastSearchAt: Date?
    private var discovered: [String: POI] = [:]

    /// Don't hammer the geocoder: Apple rate-limits it aggressively.
    private let geocodeInterval: TimeInterval = 90
    private let geocodeDistance: Double = 60_000
    private let searchInterval: TimeInterval = 240

    var isEnabled = true

    /// Called when the aircraft enters a new state/province or country.
    /// `(region, country, isNewCountry)`
    var onRegionChange: ((String?, String?, Bool) -> Void)?

    /// Called with POIs MapKit knew about that our bundle did not.
    var onDiscovered: (([POI]) -> Void)?

    func reset() {
        currentRegion = nil
        currentCountry = nil
        lastGeocodeAt = nil
        lastGeocodeCoord = nil
        lastSearchAt = nil
        discovered.removeAll()
    }

    func update(coordinate: CLLocationCoordinate2D, altitudeM: Double) {
        guard isEnabled else { return }
        maybeGeocode(coordinate)
        maybeSearch(coordinate, altitudeM: altitudeM)
    }

    // MARK: Region

    private func maybeGeocode(_ coord: CLLocationCoordinate2D) {
        let now = Date()
        if let last = lastGeocodeAt, now.timeIntervalSince(last) < geocodeInterval,
           let lastCoord = lastGeocodeCoord, Geo.distance(lastCoord, coord) < geocodeDistance {
            return
        }
        lastGeocodeAt = now
        lastGeocodeCoord = coord

        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.reverseGeocodeLocation(loc) { [weak self] places, _ in
            guard let self, let p = places?.first else { return }

            let region = p.administrativeArea ?? p.locality ?? p.ocean
            let country = p.country

            let changedCountry = country != nil && country != self.currentCountry && self.currentCountry != nil
            let changedRegion = region != nil && region != self.currentRegion

            if changedRegion || changedCountry {
                let firstFix = self.currentRegion == nil && self.currentCountry == nil
                self.currentRegion = region
                self.currentCountry = country
                if !firstFix {
                    DispatchQueue.main.async {
                        self.onRegionChange?(region, country, changedCountry)
                    }
                }
            } else {
                self.currentRegion = region ?? self.currentRegion
                self.currentCountry = country ?? self.currentCountry
            }
        }
    }

    // MARK: MapKit discovery

    private func maybeSearch(_ coord: CLLocationCoordinate2D, altitudeM: Double) {
        let now = Date()
        if let last = lastSearchAt, now.timeIntervalSince(last) < searchInterval { return }
        lastSearchAt = now

        // Look ahead ~4 minutes so we can announce before overflying.
        let span = min(180_000.0, max(40_000, Geo.horizonDistance(altitudeM: altitudeM) * 0.4))

        let request = MKLocalPointsOfInterestRequest(
            center: coord,
            radius: min(span, 50_000)   // MapKit caps POI radius at 50 km
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .nationalPark, .park, .beach, .museum, .stadium, .university, .airport, .marina
        ])

        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let self, let items = response?.mapItems, !items.isEmpty else { return }

            let fresh: [POI] = items.compactMap { item in
                guard let name = item.name,
                      let loc = item.placemark.location else { return nil }
                let id = "mk:" + name.lowercased().replacingOccurrences(of: " ", with: "-")
                guard self.discovered[id] == nil else { return nil }

                let poi = POI(
                    id: id,
                    name: name,
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    kind: Self.kind(for: item.pointOfInterestCategory),
                    reach: 45,
                    // Discovered POIs rank below curated ones — we have no
                    // hand-written fact for them, just a name and a category.
                    wow: 48,
                    facts: [Self.blurb(for: item)],
                    region: item.placemark.administrativeArea,
                    aviation: nil
                )
                self.discovered[id] = poi
                return poi
            }

            guard !fresh.isEmpty else { return }
            DispatchQueue.main.async { self.onDiscovered?(fresh) }
        }
    }

    private static func kind(for category: MKPointOfInterestCategory?) -> POI.Kind {
        switch category {
        case .some(.nationalPark), .some(.park): return .natural
        case .some(.beach), .some(.marina):      return .water
        case .some(.airport):                    return .airport
        case .some(.museum), .some(.university): return .science
        case .some(.stadium):                    return .landmark
        default:                                 return .landmark
        }
    }

    private static func blurb(for item: MKMapItem) -> String {
        let place = [item.placemark.locality, item.placemark.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty
            ? "Spotted on the map below you."
            : "Down there in \(place)."
    }
}
