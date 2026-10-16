import SwiftUI

/// The "start flight detect" control.
///
/// Idle it breathes; armed it sweeps like a radar scope and fills a confidence
/// ring as the sensors agree with each other. The point is that detection is
/// visibly *doing something* rather than being a spinner with a hidden verdict.
struct RadarButton: View {

    var isArmed: Bool
    /// 0–1 detection confidence, drives the ring.
    var confidence: Double
    var tint: Color
    var glyph: String
    var caption: String
    var action: () -> Void

    @State private var sweep: Double = 0
    @State private var pulse: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Breathing halo
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.28), .clear],
                                         center: .center, startRadius: 10, endRadius: 150))
                    .scaleEffect(pulse ? 1.12 : 0.94)
                    .opacity(pulse ? 0.9 : 0.5)

                // Concentric range rings
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(tint.opacity(0.16 - Double(i) * 0.04), lineWidth: 1)
                        .frame(width: 118 + CGFloat(i) * 42, height: 118 + CGFloat(i) * 42)
                }

                // Radar sweep — only while armed
                if isArmed {
                    Circle()
                        .fill(AngularGradient(
                            gradient: Gradient(colors: [
                                tint.opacity(0.0), tint.opacity(0.0), tint.opacity(0.42)
                            ]),
                            center: .center
                        ))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(sweep))
                        .mask(Circle().frame(width: 200, height: 200))
                        .blur(radius: 1)
                }

                // Confidence ring
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 158, height: 158)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, confidence)))
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.6), tint, Theme.mint],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 158, height: 158)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: confidence)

                // Core
                Circle()
                    .fill(Theme.panel)
                    .frame(width: 136, height: 136)
                    .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))

                VStack(spacing: 5) {
                    Text(glyph)
                        .font(.system(size: 40))
                        .rotationEffect(.degrees(isArmed ? 0 : -8))
                        .scaleEffect(pulse && !isArmed ? 1.06 : 1.0)
                    Text(caption)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.center)
                        .frame(width: 112)
                }
            }
            .frame(width: 230, height: 230)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            if isArmed { startSweep() }
        }
        .onChange(of: isArmed) { _, armed in
            if armed { startSweep() }
        }
    }

    private func startSweep() {
        sweep = 0
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            sweep = 360
        }
    }
}
