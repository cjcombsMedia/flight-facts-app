import SwiftUI
import MapKit

/// Saved flights, newest first.
struct LogView: View {
    @Environment(FlightEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var logs: [FlightLog] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backdrop.ignoresSafeArea()

                if logs.isEmpty {
                    empty
                } else {
                    ScrollView {
                        LazyVStack(spacing: 11) {
                            ForEach(logs) { log in
                                NavigationLink { FlightDetailView(log: log) } label: {
                                    LogRow(log: log)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        engine.delete(log)
                                        logs.removeAll { $0.id == log.id }
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Flight log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(Theme.cyan)
                }
            }
            .onAppear { logs = engine.savedFlights() }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("🧳").font(.system(size: 46))
            Text("No flights yet")
                .font(Theme.title(18)).foregroundStyle(.white)
            Text("Run a demo route or start a real flight and it'll show up here, POIs and all.")
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.slate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
    }
}

struct LogRow: View {
    let log: FlightLog

    var body: some View {
        HStack(spacing: 13) {
            VStack(spacing: 1) {
                Text(log.startedAt, format: .dateTime.day())
                    .font(Theme.display(19)).foregroundStyle(.white)
                Text(log.startedAt, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.displayTitle)
                        .font(Theme.title(15)).foregroundStyle(.white)
                        .lineLimit(1)
                    if log.isSimulated {
                        Text("DEMO")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.violet.opacity(0.18)))
                    }
                }
                HStack(spacing: 9) {
                    Label("\(log.sightings.count)", systemImage: "mappin.circle.fill")
                    Label(Units.feet(log.maxAltitudeM), systemImage: "arrow.up")
                    Label(Units.miles(log.distanceM), systemImage: "arrow.left.and.right")
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.slate)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.slate)
        }
        .padding(13)
        .glass(radius: 17, strokeOpacity: 0.11)
    }
}

// MARK: - Detail

struct FlightDetailView: View {
    let log: FlightLog

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    routeMap
                    stats
                    if !log.sightings.isEmpty { sightingsSection }
                    if !log.entries.isEmpty { transcript }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(log.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fitCamera() }
    }

    private var routeMap: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if log.track.count > 1 {
                MapPolyline(coordinates: log.track.map(\.coordinate))
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(log.sightings) { s in
                Annotation(s.poi.name, coordinate: s.poi.coordinate) {
                    Text(s.poi.kind.glyph)
                        .font(.system(size: 13))
                        .padding(5)
                        .background(Circle().fill(Theme.panel))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.hybrid)
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                  spacing: 9) {
            SummaryTile(glyph: "▲", label: "Max alt",
                        value: Units.feet(log.maxAltitudeM), tint: Theme.sky)
            SummaryTile(glyph: "↔", label: "Distance",
                        value: Units.miles(log.distanceM), tint: Theme.violet)
            SummaryTile(glyph: "⏱", label: "Duration",
                        value: duration, tint: Theme.mint)
        }
    }

    private var duration: String {
        let t = log.duration
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var sightingsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("POINTS OF INTEREST (\(log.sightings.count))")
            ForEach(log.sightings) { s in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(s.poi.kind.glyph).font(.system(size: 16))
                        Text(s.poi.name).font(Theme.title(14)).foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Text(s.at, format: .dateTime.hour().minute())
                            .font(Theme.mono(10)).foregroundStyle(Theme.slate)
                    }
                    if let fact = s.poi.facts.first {
                        Text(fact)
                            .font(Theme.body(12))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(s.side.label.capitalized) · \(s.clock) o'clock · \(Int(s.distanceKm)) km · \(Units.feet(s.altitudeM))")
                        .font(Theme.body(10.5))
                        .foregroundStyle(Theme.amber.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glass(radius: 15, strokeOpacity: 0.1)
            }
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("FULL TRANSCRIPT (\(log.entries.count))")
            ForEach(log.entries) { entry in
                HStack(alignment: .top, spacing: 9) {
                    Text(entry.glyph).font(.system(size: 13)).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(Theme.title(12.5)).foregroundStyle(.white)
                        Text(entry.body)
                            .font(Theme.body(11.5))
                            .foregroundStyle(Theme.slate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(entry.at, format: .dateTime.hour().minute())
                        .font(Theme.mono(9.5)).foregroundStyle(Theme.slate.opacity(0.7))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(13)
        .glass(radius: 17, strokeOpacity: 0.1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Theme.slate)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fitCamera() {
        let coords = log.track.map(\.coordinate)
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.4, (maxLat - minLat) * 1.35),
                                    longitudeDelta: max(0.4, (maxLon - minLon) * 1.35))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}
