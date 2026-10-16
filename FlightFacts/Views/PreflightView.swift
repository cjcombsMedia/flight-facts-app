import SwiftUI
import CoreLocation

struct PreflightView: View {
    @Environment(FlightEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    @Binding var showLog: Bool
    @Binding var showSettings: Bool

    @State private var showDemoPicker = false
    @State private var showPlanner = false

    private var needsLocation: Bool {
        engine.locationAuthorization == .notDetermined
            || engine.locationAuthorization == .denied
            || engine.locationAuthorization == .restricted
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header

                RadarButton(
                    isArmed: false,
                    confidence: 0,
                    tint: Theme.cyan,
                    glyph: "✈️",
                    caption: "START FLIGHT\nDETECT",
                    action: startLive
                )
                .padding(.top, 4)

                if needsLocation { permissionNudge }

                planSection

                capabilities

                demoSection

                footerButtons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showDemoPicker) { DemoPickerView() }
        .sheet(isPresented: $showPlanner) { FlightPlanView() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Text("FLIGHT FACTS")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(4.5)
                .foregroundStyle(
                    LinearGradient(colors: [Theme.cyan, Theme.violet],
                                   startPoint: .leading, endPoint: .trailing)
                )

            Text("What are you\nflying over?")
                .font(Theme.display(34))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)

            Text("Every sensor your phone has, pointed at the ground.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.slate)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 34)
    }

    private var permissionNudge: some View {
        Button(action: engine.requestPermissions) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.locationAuthorization == .denied
                         ? "Location is off"
                         : "Grant location & notifications")
                        .font(Theme.title(14))
                        .foregroundStyle(.white)
                    Text(engine.locationAuthorization == .denied
                         ? "Enable it in Settings › Flight Facts"
                         : "Needed to know what's below you and to alert you before a descent.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.slate)
            }
            .padding(14)
            .glass(tint: Theme.amber, radius: 18, strokeOpacity: 0.3)
        }
        .buttonStyle(.plain)
    }

    /// Entry point for route + seat + tile preload. Shows the saved plan once
    /// there is one, since that's the state people will come back to at the gate.
    private var planSection: some View {
        Button { showPlanner = true } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.mint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: engine.plan == nil ? "map" : "checkmark.seal.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.mint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.plan.map { "\($0.title) · \($0.seat.label)" } ?? "Plan your flight")
                        .font(Theme.title(15))
                        .foregroundStyle(.white)
                    Text(engine.plan == nil
                         ? "Enter your route and seat to preload maps and aim facts at your window."
                         : "Tap to change route, seat, or preload maps again.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.slate)
            }
            .padding(13)
            .glass(tint: Theme.mint, radius: 18, strokeOpacity: engine.plan == nil ? 0.14 : 0.3)
        }
        .buttonStyle(.plain)
    }

    private var capabilities: some View {
        VStack(spacing: 10) {
            CapabilityRow(glyph: "🛰️", tint: Theme.cyan,
                          title: "Catches you mid-flight",
                          text: "At the gate, on the taxiway, or already at 38,000 ft — it works out where you are and picks up from there.")
            CapabilityRow(glyph: "💬", tint: Theme.violet,
                          title: "Facts as you pass them",
                          text: "Landmarks, geology, oddities and aviation history bubble up over a live map, with which window to look out of.")
            CapabilityRow(glyph: "🛬", tint: Theme.amber,
                          title: "Descent warning that's early",
                          text: "Top of descent is picked up from the barometer about 25 minutes before landing — well before the PA.")
            CapabilityRow(glyph: "📴", tint: Theme.mint,
                          title: "Works in airplane mode",
                          text: "The landmark and history corpus is bundled. No signal needed at cruise.")
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOT FLYING RIGHT NOW?")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(Theme.slate)

            Button { showDemoPicker = true } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.violet.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Text("🎬").font(.system(size: 21))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fly a demo route")
                            .font(Theme.title(15))
                            .foregroundStyle(.white)
                        Text("A full synthetic flight at \(Int(settings.demoSpeed))× — gate to gate.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.slate)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.slate)
                }
                .padding(13)
                .glass(tint: Theme.violet, radius: 18)
            }
            .buttonStyle(.plain)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            SecondaryButton(glyph: "book.closed.fill", label: "Flight log") { showLog = true }
            SecondaryButton(glyph: "slider.horizontal.3", label: "Settings") { showSettings = true }
        }
    }

    private func startLive() {
        engine.requestPermissions()
        engine.startScanning(mode: .live)
    }
}

// MARK: - Small pieces

struct CapabilityRow: View {
    var glyph: String
    var tint: Color
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Text(glyph).font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.title(14))
                    .foregroundStyle(.white)
                Text(text)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .glass(tint: tint, radius: 18, strokeOpacity: 0.12)
    }
}

struct SecondaryButton: View {
    var glyph: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: glyph).font(.system(size: 13, weight: .semibold))
                Text(label).font(Theme.title(14))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glass(radius: 15, strokeOpacity: 0.12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Demo picker

struct DemoPickerView: View {
    @Environment(FlightEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        Text("Every demo runs through the same detector, POI scout and notification path a real flight does. Nothing is faked downstream of the sensors.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.slate)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)

                        ForEach(DemoRoute.all) { route in
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    engine.startScanning(mode: .demo(route))
                                }
                            } label: {
                                HStack(spacing: 13) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(route.name)
                                            .font(Theme.title(16))
                                            .foregroundStyle(.white)
                                        Text(route.subtitle)
                                            .font(Theme.body(12))
                                            .foregroundStyle(Theme.slate)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(Theme.violet)
                                }
                                .padding(14)
                                .glass(tint: Theme.violet, radius: 18)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("REPLAY A RECORDING")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.7)
                            .foregroundStyle(Theme.slate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                engine.startScanning(mode: .replay("rrcc-sample"))
                            }
                        } label: {
                            HStack(spacing: 13) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("RRCC sample session")
                                        .font(Theme.title(16))
                                        .foregroundStyle(.white)
                                    Text("Your real TrackSession export — 28 s at FL405 over Guanajuato. Decoded straight from the RRCC schema.")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.slate)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.mint)
                            }
                            .padding(14)
                            .glass(tint: Theme.mint, radius: 18)
                        }
                        .buttonStyle(.plain)

                        @Bindable var s = settings
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Playback speed")
                                    .font(Theme.title(14)).foregroundStyle(.white)
                                Spacer()
                                Text("\(Int(s.demoSpeed))×")
                                    .font(Theme.mono(14)).foregroundStyle(Theme.cyan)
                            }
                            Slider(value: $s.demoSpeed, in: 10...240, step: 10)
                                .tint(Theme.cyan)
                            Text("At 60× a five-hour flight plays in about five minutes.")
                                .font(Theme.body(11.5))
                                .foregroundStyle(Theme.slate)
                        }
                        .padding(14)
                        .glass(radius: 18)
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Demo flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.tint(Theme.cyan)
                }
            }
        }
    }
}
