import SwiftUI

/// Night-cockpit palette. Dark by default because most of the time you are
/// using this in a dim cabin, often at night, and a white screen is antisocial.
enum Theme {

    // Accents
    static let cyan   = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let sky    = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let mint   = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let amber  = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let coral  = Color(red: 0.98, green: 0.44, blue: 0.52)
    static let violet = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let slate  = Color(red: 0.58, green: 0.64, blue: 0.72)

    // Surfaces
    static let ink     = Color(red: 0.02, green: 0.04, blue: 0.09)
    static let inkSoft = Color(red: 0.04, green: 0.08, blue: 0.16)
    static let card    = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.10)
    /// Translucent panel fill. Deliberately *not* a blur material: over a moving
    /// map every blurred layer is re-rendered every frame, and with a dozen
    /// panels and bubbles on screen that was the main cause of dropped frames.
    static let panel   = Color(red: 0.05, green: 0.08, blue: 0.15).opacity(0.86)

    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [ink, inkSoft, Color(red: 0.06, green: 0.10, blue: 0.20)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // Type — SF Rounded everywhere. It reads friendly without being childish.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func title(_ size: CGFloat)   -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat)    -> Font { .system(size: size, weight: .regular, design: .rounded) }
    static func mono(_ size: CGFloat)    -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

// MARK: - Reusable chrome

/// Frosted card used for HUD chips, bubbles and list rows.
struct GlassCard: ViewModifier {
    var tint: Color = .white
    var radius: CGFloat = 20
    var strokeOpacity: Double = 0.14

    func body(content: Content) -> some View {
        content
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

extension View {
    func glass(tint: Color = .white, radius: CGFloat = 20, strokeOpacity: Double = 0.14) -> some View {
        modifier(GlassCard(tint: tint, radius: radius, strokeOpacity: strokeOpacity))
    }
}

/// Small pill used for HUD readouts.
struct StatChip: View {
    var label: String
    var value: String
    var tint: Color = Theme.cyan
    var glyph: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                if let glyph { Text(glyph).font(.system(size: 9)) }
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Theme.slate)
            }
            Text(value)
                .font(Theme.mono(15))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .glass(tint: tint, radius: 13, strokeOpacity: 0.16)
    }
}

/// Horizontal bar showing a normalised signal, used in the scanner.
struct SignalBar: View {
    var label: String
    var value: String
    var fraction: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.slate)
                Spacer()
                Text(value)
                    .font(Theme.mono(12))
                    .foregroundStyle(.white.opacity(0.9))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.55), tint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                        .animation(.easeOut(duration: 0.45), value: fraction)
                }
            }
            .frame(height: 5)
        }
    }
}
