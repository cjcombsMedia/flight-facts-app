import SwiftUI
import MapKit

/// Pre-flight setup: where you're going, which window you're at, and warming the
/// map cache while you still have gate Wi-Fi.
struct FlightPlanView: View {
    @Environment(FlightEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var origin: Airport?
    @State private var destination: Airport?
    @State private var seat: SeatSide = .centre
    @State private var seatText = ""
    @State private var flightNumber = ""
    /// Route preview, keyed on the route so it's computed once per route rather
    /// than on every redraw — it's ~70k distance calculations, and the prefetch
    /// progress bar redraws this view continuously.
    @State private var anticipated: (key: String, items: [(poi: POI, side: SeatSide)])?

    /// Owned by the engine so preloading carries on after this sheet closes.
    private var prefetcher: TilePrefetcher { engine.prefetcher }

    private var plan: FlightPlan? {
        guard let origin, let destination, origin.id != destination.id else { return nil }
        return FlightPlan(origin: origin, destination: destination, seat: seat,
                          flightNumber: flightNumber.isEmpty ? nil : flightNumber)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        routeSection
                        if let plan { summary(plan); seatSection; prefetchSection(plan); previewSection(plan) }
                        else { hint }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Plan a flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Theme.slate)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let plan { engine.setPlan(plan) }
                        dismiss()
                    }
                    .tint(Theme.cyan)
                    .disabled(plan == nil)
                }
            }
            .onAppear(perform: loadExisting)
            .task(id: routeKey) {
                // Seat doesn't change which POIs the route passes, only which
                // side they're on relative to you — so key on the route alone.
                guard let key = routeKey, let plan else { return }
                anticipated = (key, plan.anticipatedPOIs())
            }
        }
    }

    private func loadExisting() {
        guard let existing = engine.plan else { return }
        origin = existing.origin
        destination = existing.destination
        seat = existing.seat
        flightNumber = existing.flightNumber ?? ""
    }

    // MARK: Route

    private var routeSection: some View {
        VStack(spacing: 10) {
            AirportField(label: "From", placeholder: "PHX, Phoenix…", selection: $origin)
            AirportField(label: "To", placeholder: "MEX, Mexico City…", selection: $destination)

            HStack(spacing: 8) {
                Text("Flight no.")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate)
                    .frame(width: 68, alignment: .leading)
                TextField("optional", text: $flightNumber)
                    .font(Theme.body(14))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .glass(radius: 14, strokeOpacity: 0.1)
        }
    }

    private var hint: some View {
        VStack(spacing: 9) {
            Text("✈️").font(.system(size: 34))
            Text("Pick two airports")
                .font(Theme.title(16)).foregroundStyle(.white)
            Text("Planning ahead lets the app cache map tiles before you lose signal, and tells it which window you're sitting at.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.slate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 28)
    }

    private func summary(_ plan: FlightPlan) -> some View {
        HStack(spacing: 0) {
            metric(plan.origin.id, "from")
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .frame(maxWidth: .infinity)
            metric(plan.destination.id, "to")
            Divider().frame(height: 30).overlay(Theme.hairline)
            metric(Units.miles(plan.distanceM), "distance")
            metric(duration(plan.estimatedDuration), "approx")
        }
        .padding(.vertical, 12).padding(.horizontal, 10)
        .glass(tint: Theme.cyan, radius: 16, strokeOpacity: 0.2)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.title(15)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Theme.slate)
        }
        .frame(maxWidth: .infinity)
    }

    private func duration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: Seat

    private var seatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("YOUR SEAT")

            HStack(spacing: 8) {
                TextField("12A", text: $seatText)
                    .font(Theme.mono(15))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 66)
                    .padding(.vertical, 9).padding(.horizontal, 11)
                    .glass(radius: 11, strokeOpacity: 0.12)
                    .onChange(of: seatText) { _, new in
                        if let inferred = SeatSide.infer(fromSeat: new) { seat = inferred }
                    }

                ForEach(SeatSide.allCases) { side in
                    Button { seat = side } label: {
                        HStack(spacing: 4) {
                            Image(systemName: side.glyph).font(.system(size: 10, weight: .bold))
                            Text(side.label).font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(seat == side ? Theme.ink : .white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(seat == side ? Theme.amber : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(seat.blurb)
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.slate)
        }
        .padding(14)
        .glass(radius: 17, strokeOpacity: 0.1)
    }

    // MARK: Prefetch

    private func prefetchSection(_ plan: FlightPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("PRELOAD MAPS")

            Text("Renders the route through MapKit's tile pipeline now, so the tiles are already cached when you're airborne. Do this on Wi-Fi at the gate.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.slate)
                .fixedSize(horizontal: false, vertical: true)

            switch prefetcher.state {
            case .idle:
                Button { prefetcher.prefetch(plan: plan, style: settings.mapStyle) } label: {
                    Label("Preload route", systemImage: "square.and.arrow.down.fill")
                        .font(Theme.title(14))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Theme.mint))
                }
                .buttonStyle(.plain)

            case .running(let done, let total):
                VStack(spacing: 7) {
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(Theme.mint)
                    HStack {
                        Text("Caching \(done) of \(total) sections…")
                            .font(Theme.body(12)).foregroundStyle(Theme.slate)
                        Spacer()
                        Button("Stop") { prefetcher.cancel() }
                            .font(Theme.title(12)).tint(Theme.coral)
                    }
                }

            case .finished(let tiles, _):
                Label("Cached \(tiles) map sections along the route",
                      systemImage: "checkmark.circle.fill")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.mint)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 7) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.amber)
                    Button("Try again") { prefetcher.prefetch(plan: plan, style: settings.mapStyle) }
                        .font(Theme.title(13)).tint(Theme.cyan)
                }
            }

            Text("iOS owns this cache and can evict it, so treat it as a warm start rather than true offline maps. Turning off 3D terrain in Settings makes the biggest difference to load speed.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.slate.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glass(tint: Theme.mint, radius: 17, strokeOpacity: 0.14)
    }

    // MARK: Preview

    private var routeKey: String? {
        guard let origin, let destination else { return nil }
        return "\(origin.id)-\(destination.id)"
    }

    private func previewSection(_ plan: FlightPlan) -> some View {
        let anticipated = self.anticipated?.key == routeKey ? self.anticipated?.items ?? [] : []
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("YOU'LL FLY PAST (\(anticipated.count))")

            if anticipated.isEmpty {
                Text("Nothing in the bundled corpus along this route yet — you'll still get aviation history, sky facts and live stats.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.slate)
            } else {
                ForEach(Array(anticipated.prefix(14).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 9) {
                        Text(item.poi.kind.glyph).font(.system(size: 15))
                        Text(item.poi.name)
                            .font(Theme.body(13)).foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if item.side != .centre {
                            Image(systemName: item.side.glyph)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(item.side == seat ? Theme.amber : Theme.slate.opacity(0.6))
                        }
                    }
                }
                if anticipated.count > 14 {
                    Text("+ \(anticipated.count - 14) more")
                        .font(Theme.body(11.5)).foregroundStyle(Theme.slate)
                }
            }
        }
        .padding(14)
        .glass(radius: 17, strokeOpacity: 0.1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Theme.slate)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Airport picker field

struct AirportField: View {
    var label: String
    var placeholder: String
    @Binding var selection: Airport?

    @State private var query = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    private var results: [Airport] {
        AirportStore.shared.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate)
                    .frame(width: 68, alignment: .leading)

                if let selection, !isEditing {
                    Button {
                        isEditing = true
                        query = ""
                        focused = true
                    } label: {
                        HStack(spacing: 7) {
                            Text(selection.id)
                                .font(Theme.mono(15)).foregroundStyle(Theme.cyan)
                            Text(selection.city)
                                .font(Theme.body(14)).foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "pencil")
                                .font(.system(size: 10)).foregroundStyle(Theme.slate)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    TextField(placeholder, text: $query)
                        .font(Theme.body(14))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(pickFirst)
                }
            }
            .padding(12)

            if isEditing || selection == nil, !results.isEmpty, !query.isEmpty {
                Divider().overlay(Theme.hairline)
                VStack(spacing: 0) {
                    ForEach(results) { airport in
                        Button { choose(airport) } label: {
                            HStack(spacing: 9) {
                                Text(airport.id)
                                    .font(Theme.mono(13)).foregroundStyle(Theme.cyan)
                                    .frame(width: 38, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(airport.city)
                                        .font(Theme.body(13)).foregroundStyle(.white)
                                    Text(airport.name)
                                        .font(Theme.body(10.5)).foregroundStyle(Theme.slate)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .glass(radius: 14, strokeOpacity: 0.1)
    }

    private func pickFirst() {
        if let first = results.first { choose(first) }
    }

    private func choose(_ airport: Airport) {
        selection = airport
        query = ""
        isEditing = false
        focused = false
    }
}
