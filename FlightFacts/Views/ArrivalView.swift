import SwiftUI

/// Post-flight summary. Shows up automatically on landing, or when you stop a
/// flight and save it.
struct ArrivalView: View {
    @Environment(FlightEngine.self) private var engine
    @Binding var showLog: Bool

    private var log: FlightLog? { engine.lastSavedLog }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("🛬").font(.system(size: 54))
                    Text("Wheels down")
                        .font(Theme.display(30))
                        .foregroundStyle(.white)
                    if let log {
                        Text(log.displayTitle)
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.slate)
                    }
                }
                .padding(.top, 44)

                if let log { stats(log) }

                if !engine.sightings.isEmpty { poiRecap }

                VStack(spacing: 10) {
                    Button { showLog = true } label: {
                        Text("Open flight log")
                            .font(Theme.title(15))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.cyan))
                    }
                    .buttonStyle(.plain)

                    Button { engine.stop(save: false) } label: {
                        Text("Back to start")
                            .font(Theme.title(15))
                            .foregroundStyle(Theme.slate)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .glass(radius: 16, strokeOpacity: 0.1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func stats(_ log: FlightLog) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            SummaryTile(glyph: "📍", label: "Points of interest",
                        value: "\(engine.sightings.count)", tint: Theme.cyan)
            SummaryTile(glyph: "▲", label: "Max altitude",
                        value: Units.feet(log.maxAltitudeM), tint: Theme.sky)
            SummaryTile(glyph: "↔", label: "Distance",
                        value: Units.miles(log.distanceM), tint: Theme.violet)
            SummaryTile(glyph: "⏱", label: "Duration",
                        value: formatted(log.duration), tint: Theme.mint)
            SummaryTile(glyph: "▶", label: "Top speed",
                        value: Units.mph(log.maxSpeedMps), tint: Theme.amber)
            SummaryTile(glyph: "💬", label: "Facts served",
                        value: "\(log.entries.count)", tint: Theme.coral)
        }
    }

    private var poiRecap: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("WHAT YOU FLEW OVER")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.7)
                .foregroundStyle(Theme.slate)

            ForEach(engine.sightings) { sighting in
                HStack(spacing: 10) {
                    Text(sighting.poi.kind.glyph).font(.system(size: 17))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sighting.poi.name)
                            .font(Theme.title(13.5))
                            .foregroundStyle(.white)
                        Text("\(sighting.at, format: .dateTime.hour().minute()) · \(sighting.side.label) · \(Int(sighting.distanceKm)) km")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.slate)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9).padding(.horizontal, 12)
                .glass(radius: 14, strokeOpacity: 0.1)
            }
        }
    }

    private func formatted(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

struct SummaryTile: View {
    var glyph: String
    var label: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(glyph).font(.system(size: 15))
            Text(value)
                .font(Theme.display(20))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(Theme.slate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .glass(tint: tint, radius: 16, strokeOpacity: 0.16)
    }
}
