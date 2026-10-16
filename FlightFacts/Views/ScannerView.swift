import SwiftUI

/// The armed state. Shows exactly what the detector is looking at and why it
/// has or hasn't called it a flight yet — the reasoning is the entertainment.
struct ScannerView: View {
    @Environment(FlightEngine.self) private var engine

    private var s: DetectionSignals { engine.signals }

    var body: some View {
        VStack(spacing: 0) {
            header

            RadarButton(
                isArmed: true,
                confidence: s.confidence,
                tint: tint,
                glyph: engine.phase.glyph,
                caption: statusCaption,
                action: {}
            )
            .allowsHitTesting(false)
            .padding(.top, 6)

            confidenceLine
                .padding(.top, 2)

            ScrollView {
                VStack(spacing: 14) {
                    signalPanel
                    evidencePanel
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            cancelButton
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    // MARK: Pieces

    private var tint: Color {
        s.confidence > 0.6 ? Theme.mint : (s.confidence > 0.25 ? Theme.amber : Theme.cyan)
    }

    private var statusCaption: String {
        switch engine.phase {
        case .unknown: return s.hasFix ? "SCANNING" : "GETTING FIX"
        case .atGate:  return "AT GATE"
        default:       return engine.phase.title.uppercased()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(engine.mode.isSimulated ? engine.mode.label.uppercased() : "LISTENING")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(tint)
            Text(headline)
                .font(Theme.display(25))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .contentTransition(.opacity)
            if let hint {
                Text(hint)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.slate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 26)
    }

    private var headline: String {
        if engine.latest == nil { return "Waiting for a GPS fix" }
        if s.estimated { return "GPS dropped — holding" }
        switch engine.phase {
        case .atGate: return "Parked. Standing by."
        case .taxi, .takeoffRoll:
            return engine.isNearAirport ? "You're rolling" : "Moving — not at an airport yet"
        default: return "Looking for a flight"
        }
    }

    private var hint: String? {
        if engine.latest == nil {
            return "GPS works in airplane mode, but without cell assistance the first fix can take a few minutes. A window seat helps."
        }
        if s.estimated {
            return "Common inside a cabin. Position is estimated from the last fix until the signal returns."
        }
        if (engine.phase == .taxi || engine.phase == .takeoffRoll), !engine.isNearAirport {
            return "Ground movement only counts at an airport. Takeoff is detected wherever you are."
        }
        return nil
    }

    private var confidenceLine: some View {
        Text("\(Int(s.confidence * 100))% confident this is a flight")
            .font(Theme.body(12.5))
            .foregroundStyle(Theme.slate)
            .contentTransition(.numericText())
    }

    private var signalPanel: some View {
        VStack(spacing: 14) {
            HStack {
                Text("LIVE SENSORS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.slate)
                Spacer()
                Circle()
                    .fill(s.hasFix ? Theme.mint : Theme.coral)
                    .frame(width: 6, height: 6)
                Text(s.hasFix ? "±\(Int(s.gpsAccuracy)) m" : "no fix")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.slate)
            }

            SignalBar(label: "Ground speed", value: Units.knots(s.speed),
                      fraction: s.speed / 260, tint: Theme.cyan)
            SignalBar(label: "Altitude", value: Units.feet(s.altitude),
                      fraction: s.altitude / 12_500, tint: Theme.sky)
            SignalBar(label: "Vertical rate", value: Units.fpm(s.verticalRate),
                      fraction: abs(s.verticalRate) / 15,
                      tint: s.verticalRate < -0.5 ? Theme.amber : Theme.mint)
            SignalBar(label: "Airframe vibration", value: String(format: "%.3f g", s.vibration),
                      fraction: s.vibration / 0.3, tint: Theme.violet)

            if let p = s.cabinPressure {
                SignalBar(label: "Cabin pressure",
                          value: String(format: "%.1f kPa", p),
                          fraction: (101.3 - p) / 26, tint: Theme.coral)
                if let cabin = s.cabinAltitude, cabin > 300 {
                    Text("Cabin altitude ≈ \(Units.feet(cabin)) — the aircraft is pressurised.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.slate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No barometer reading yet. GPS and motion still voting.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .glass(radius: 20)
    }

    @ViewBuilder
    private var evidencePanel: some View {
        if !s.evidence.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("EVIDENCE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.slate)

                ForEach(Array(s.evidence.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mint)
                            .padding(.top, 1)
                        Text(line)
                            .font(Theme.body(12.5))
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glass(tint: Theme.mint, radius: 20, strokeOpacity: 0.18)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var cancelButton: some View {
        Button { engine.stop(save: false) } label: {
            Text("Stop scanning")
                .font(Theme.title(15))
                .foregroundStyle(Theme.slate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glass(radius: 15, strokeOpacity: 0.1)
        }
        .buttonStyle(.plain)
    }
}
