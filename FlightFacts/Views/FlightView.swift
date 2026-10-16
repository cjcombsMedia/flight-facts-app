import SwiftUI

/// The main in-flight screen: moving map underneath, chat feed floating on top.
struct FlightView: View {
    @Environment(FlightEngine.self) private var engine

    @Binding var showSettings: Bool

    @State private var isFollowing = true
    @State private var selectedPOI: POISighting?
    /// Fraction of the screen the feed occupies.
    @State private var feedFraction: CGFloat = 0.46
    @State private var dragStart: CGFloat?
    @State private var showEndConfirm = false

    private let maxFraction: CGFloat = 0.86

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                FlightMapView(isFollowing: $isFollowing, selected: $selectedPOI)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    FlightTopBar(showSettings: $showSettings, showEndConfirm: $showEndConfirm)
                    FlightHUD()
                    FlightStatusRow()
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    feed(screenHeight: geo.size.height)
                }
                .ignoresSafeArea(edges: .bottom)

                if !isFollowing {
                    recenterButton
                        .padding(.bottom, geo.size.height * feedFraction + 14)
                }
            }
        }
        .confirmationDialog("End this flight?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("Save & end", role: .destructive) { engine.stop(save: true) }
            Button("Discard", role: .destructive) { engine.stop(save: false) }
            Button("Keep flying", role: .cancel) {}
        } message: {
            Text("Saving keeps the POI log and exports the sensor track.")
        }
    }

    private var recenterButton: some View {
        VStack {
            Spacer()
            Button { isFollowing = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 11, weight: .bold))
                    Text("Follow").font(Theme.title(13))
                }
                .foregroundStyle(Theme.cyan)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glass(tint: Theme.cyan, radius: 20, strokeOpacity: 0.35)
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }

    // MARK: Feed

    private func feed(screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            grabber(screenHeight: screenHeight)
            BubbleFeedView(collapsed: feedFraction < 0.12)
                .frame(height: max(0, screenHeight * feedFraction))
                .clipped()
        }
        .background(
            LinearGradient(
                colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func grabber(screenHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 38, height: 4)
            if feedFraction < 0.12, let latest = engine.bubbles.last {
                HStack(spacing: 6) {
                    Text(latest.kind.glyph).font(.system(size: 11))
                    Text(latest.title)
                        .font(Theme.title(12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Theme.panel))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStart == nil { dragStart = feedFraction }
                    let delta = -value.translation.height / max(1, screenHeight)
                    feedFraction = min(maxFraction, max(0, (dragStart ?? 0.46) + delta))
                }
                .onEnded { _ in
                    dragStart = nil
                    // Snap to the nearest of collapsed / half / tall.
                    let stops: [CGFloat] = [0.0, 0.46, maxFraction]
                    let nearest = stops.min { abs($0 - feedFraction) < abs($1 - feedFraction) } ?? 0.46
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                        feedFraction = nearest
                    }
                }
        )
    }
}

// MARK: - Top bar

private struct FlightTopBar: View {
    @Environment(FlightEngine.self) private var engine
    @Binding var showSettings: Bool
    @Binding var showEndConfirm: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Text(engine.phase.glyph).font(.system(size: 15))
                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.phase.title)
                        .font(Theme.title(13.5))
                        .foregroundStyle(.white)
                    if let region = engine.region {
                        Text(region)
                            .font(Theme.body(10.5))
                            .foregroundStyle(Theme.slate)
                            .lineLimit(1)
                    } else if engine.mode.isSimulated {
                        Text(engine.mode.label)
                            .font(Theme.body(10.5))
                            .foregroundStyle(Theme.violet)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass(tint: engine.phase.tint, radius: 15, strokeOpacity: 0.28)

            Spacer(minLength: 0)

            CircleIconButton(system: "slider.horizontal.3") { showSettings = true }
            CircleIconButton(system: "stop.fill", tint: Theme.coral) { showEndConfirm = true }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

// MARK: - HUD

/// Its own view so the once-a-second number changes redraw four chips, not the
/// whole screen.
private struct FlightHUD: View {
    @Environment(FlightEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let s = engine.latest
        let imperial = settings.useImperial
        let estimated = s?.isEstimated ?? false

        HStack(spacing: 7) {
            StatChip(label: estimated ? "Alt (est)" : "Alt",
                     value: s.map { imperial ? Units.feet($0.alt) : "\(Int($0.alt)) m" } ?? "—",
                     tint: Theme.sky, glyph: "▲")
            StatChip(label: "Speed",
                     value: s.map { imperial ? Units.mph($0.spd) : "\(Int($0.spd * 3.6)) km/h" } ?? "—",
                     tint: Theme.cyan, glyph: "▶")
            StatChip(label: "V/S",
                     value: s.map { estimated ? "—" : (imperial ? Units.fpm($0.verticalRate)
                                                              : String(format: "%+.1f m/s", $0.verticalRate)) } ?? "—",
                     tint: (s?.verticalRate ?? 0) < -0.5 ? Theme.amber : Theme.mint,
                     glyph: "↕")
            StatChip(label: "Track",
                     value: engine.displayCourse.map { "\(Units.compass($0)) \(Int($0))°" } ?? "—",
                     tint: Theme.violet, glyph: "◈")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

/// Small pills under the HUD that answer "is this thing actually working?" —
/// most of all when the phone is in airplane mode.
private struct FlightStatusRow: View {
    @Environment(FlightEngine.self) private var engine

    var body: some View {
        HStack(spacing: 6) {
            if !engine.mode.isSimulated {
                pill(gpsLabel, system: gpsIcon, tint: gpsTint)
            }
            if !engine.isOnline {
                pill("Offline · all facts still on", system: "airplane", tint: Theme.mint)
            }
            if engine.liveActivityRunning {
                pill("Lock Screen", system: "lock.iphone", tint: Theme.violet)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var gpsLabel: String { engine.gpsStatus.label }

    private var gpsIcon: String {
        switch engine.gpsStatus {
        case .good:      return "location.fill"
        case .weak:      return "location"
        case .estimated: return "location.slash"
        case .searching: return "location.magnifyingglass"
        }
    }

    private var gpsTint: Color {
        switch engine.gpsStatus {
        case .good:      return Theme.mint
        case .weak:      return Theme.amber
        case .estimated: return Theme.amber
        case .searching: return Theme.slate
        }
    }

    private func pill(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }
}

struct CircleIconButton: View {
    var system: String
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .glass(tint: tint, radius: 18, strokeOpacity: 0.24)
        }
        .buttonStyle(.plain)
    }
}
