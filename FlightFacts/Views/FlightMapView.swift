import SwiftUI
import MapKit

/// The map camera's live heading, isolated in its own observable.
///
/// MapKit reports camera changes every frame while it animates. Holding that in
/// `@State` on the map view invalidated the whole map body each frame — the
/// polylines, every annotation — and was a major cause of stutter. Here only the
/// two views that actually read `degrees` (the compass and the aircraft marker)
/// redraw.
@Observable
final class MapHeading {
    var degrees: Double = 0
}

/// The moving map the bubbles sit on top of.
///
/// Camera is heading-up so the view matches what's out of the window. That means
/// the map itself is rotated, so the aircraft glyph is drawn relative to the
/// *camera* heading, not true north — otherwise it double-rotates.
struct FlightMapView: View {
    @Environment(FlightEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    @Binding var isFollowing: Bool
    @Binding var selected: POISighting?

    @State private var camera: MapCameraPosition = .automatic
    @State private var heading = MapHeading()
    @State private var lastCameraUpdate: Date?
    /// What the camera was last pointed at, for the stationary dead-band.
    @State private var lastCamera: (coord: CLLocationCoordinate2D, heading: Double, distance: Double)?

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {

            if engine.showPlannedRoute, engine.planPath.count > 1 {
                MapPolyline(coordinates: engine.planPath)
                    .stroke(Theme.violet.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 7]))
            }

            if engine.track.count > 1 {
                MapPolyline(coordinates: engine.track)
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            ForEach(engine.sightings) { sighting in
                Annotation(sighting.poi.name, coordinate: sighting.poi.coordinate, anchor: .center) {
                    POIPin(sighting: sighting, isSelected: selected?.id == sighting.id) {
                        selected = selected?.id == sighting.id ? nil : sighting
                    }
                }
                .annotationTitles(.hidden)
            }

            if let s = engine.latest {
                Annotation("You", coordinate: s.coordinate, anchor: .center) {
                    AircraftMarker(heading: heading, course: engine.displayCourse ?? s.course,
                                   phase: engine.phase, estimated: s.isEstimated)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            // Write-only from here; ignore sub-degree jitter.
            let h = context.camera.heading
            if abs(Geo.angleDelta(heading.degrees, h)) > 0.5 { heading.degrees = h }
        }
        .onChange(of: engine.latest) { _, sample in
            guard isFollowing, let sample else { return }
            follow(sample)
        }
        .simultaneousGesture(
            // Simultaneous, so MapKit still gets the pan — a plain `.gesture`
            // competed with the map's own recognisers.
            DragGesture(minimumDistance: 12).onChanged { _ in
                if isFollowing { isFollowing = false }
            }
        )
        .onAppear {
            if let s = engine.latest { camera = followCamera(for: s) }
        }
        .onChange(of: isFollowing) { _, following in
            guard following, let s = engine.latest else { return }
            lastCamera = nil
            withAnimation(.easeInOut(duration: 0.6)) { camera = followCamera(for: s) }
        }
        .overlay(alignment: .topTrailing) {
            // Sits clear of the phase chip and HUD row. The map ignores the safe
            // area, so this offset is measured from the screen edge.
            CompassRose(heading: heading) { faceNorth() }
                .padding(.trailing, 14)
                .padding(.top, 204)
        }
    }

    private func follow(_ s: FlightSample) {
        let target = cameraParameters(for: s)

        // Dead-band: when nothing has meaningfully changed — sitting at the gate,
        // GPS jittering a few metres — leave the camera alone instead of
        // nudging it every second.
        if let last = lastCamera,
           Geo.distance(last.coord, target.coord) < 25,
           abs(Geo.angleDelta(last.heading, target.heading)) < 2,
           abs(last.distance - target.distance) / max(1, last.distance) < 0.05 {
            return
        }
        lastCamera = target

        // Animate over roughly the real gap between samples, so successive moves
        // join into continuous motion instead of stacking up.
        let now = Date()
        let gap = lastCameraUpdate.map { now.timeIntervalSince($0) } ?? 1
        lastCameraUpdate = now
        withAnimation(.linear(duration: min(1.0, max(0.12, gap)))) {
            camera = followCamera(for: s)
        }
    }

    /// Snap the map to north-up without losing the current centre.
    private func faceNorth() {
        isFollowing = false
        guard let s = engine.latest else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .camera(MapCamera(centerCoordinate: s.coordinate,
                                       distance: cameraDistance(for: s),
                                       heading: 0, pitch: 0))
        }
    }

    private func cameraDistance(for s: FlightSample) -> Double {
        // Quantised so small altitude wobble doesn't pump the zoom.
        let raw = max(2_500, min(260_000, 9_000 + s.alt * 11))
        return (raw / 2_000).rounded() * 2_000
    }

    private func cameraParameters(for s: FlightSample) -> (coord: CLLocationCoordinate2D, heading: Double, distance: Double) {
        (s.coordinate, engine.displayCourse ?? 0, cameraDistance(for: s))
    }

    /// Heading-up, following the *smoothed* course; north-up until we've moved.
    private func followCamera(for s: FlightSample) -> MapCameraPosition {
        let p = cameraParameters(for: s)
        return .camera(MapCamera(
            centerCoordinate: p.coord,
            distance: p.distance,
            heading: p.heading,
            pitch: settings.use3DTerrain ? (s.alt > 3_000 ? 58 : 42) : 0
        ))
    }

    /// Elevation defaults to flat — `.realistic` downloads a 3D terrain mesh on
    /// top of the imagery, and at cruise the relief is invisible anyway.
    private var mapStyle: MapStyle {
        let elevation: MapStyle.Elevation = settings.use3DTerrain ? .realistic : .flat
        switch settings.mapStyle {
        case .hybrid:   return .hybrid(elevation: elevation)
        case .imagery:  return .imagery(elevation: elevation)
        case .standard: return .standard(elevation: elevation, pointsOfInterest: .excludingAll)
        }
    }
}

// MARK: - Markers

struct AircraftMarker: View {
    var heading: MapHeading
    /// Direction of travel, degrees true.
    var course: Double
    var phase: FlightPhase
    var estimated: Bool

    var body: some View {
        // Nose direction on screen = course relative to the rotated map.
        let screenHeading = Geo.angleDelta(heading.degrees, course)
        let tint = estimated ? Theme.amber : phase.tint

        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.45), .clear],
                                     center: .center, startRadius: 2, endRadius: 34))
                .frame(width: 68, height: 68)

            Circle()
                .fill(Theme.panel)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: estimated ? [3, 3] : [])))

            Image(systemName: "airplane")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                // SF Symbol `airplane` is drawn nose-right, so subtract 90° to
                // bring the nose to screen-up before applying the heading.
                .rotationEffect(.degrees(screenHeading - 90))
                .animation(.easeOut(duration: 0.5), value: screenHeading)
        }
    }
}

struct POIPin: View {
    var sighting: POISighting
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Theme.panel)
                        .frame(width: isSelected ? 38 : 30, height: isSelected ? 38 : 30)
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? Theme.amber : Theme.cyan.opacity(0.7),
                                lineWidth: isSelected ? 2 : 1)
                        )
                    Text(sighting.poi.kind.glyph)
                        .font(.system(size: isSelected ? 18 : 14))
                }
                if isSelected {
                    Text(sighting.poi.name)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.panel))
                        .fixedSize()
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
