import SwiftUI

/// North indicator for a heading-up map.
///
/// The map rotates with the aircraft, so "up" is wherever you're pointed. This
/// needle stays locked on true north, which is the only way to keep your bearings
/// when the whole world is spinning under you. Tapping it snaps the map back to
/// north-up.
struct CompassRose: View {
    /// Live map camera heading. Read here, inside this view's own body, so a
    /// heading change redraws the compass alone — not the map that owns it.
    var heading: MapHeading
    var onTap: (() -> Void)?

    private var mapHeading: Double { heading.degrees }

    var body: some View {
        Button { onTap?() } label: {
            ZStack {
                Circle()
                    .fill(Theme.panel)
                    .frame(width: 46, height: 46)
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))

                // Tick marks every 45°, so rotation is readable at a glance.
                ForEach(0..<8) { i in
                    Capsule()
                        .fill(Color.white.opacity(i % 2 == 0 ? 0.30 : 0.15))
                        .frame(width: 1, height: i % 2 == 0 ? 5 : 3)
                        .offset(y: -18)
                        .rotationEffect(.degrees(Double(i) * 45))
                }

                // The needle. Red half points north, per every compass ever made.
                ZStack {
                    Triangle()
                        .fill(Theme.coral)
                        .frame(width: 9, height: 13)
                        .offset(y: -6.5)
                    Triangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 9, height: 13)
                        .rotationEffect(.degrees(180))
                        .offset(y: 6.5)
                }
                // Counter-rotate against the map so the needle holds true north.
                .rotationEffect(.degrees(-mapHeading))

                Text("N")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    .offset(y: -15)
                    .rotationEffect(.degrees(-mapHeading))
            }
            .animation(.easeOut(duration: 0.4), value: mapHeading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compass. Map heading \(Int(mapHeading)) degrees. Tap to face north.")
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
