import SwiftUI

/// One chat bubble. Collapsed it shows title + body; tapping reveals the detail
/// lines and, for a POI, which window to look out of.
struct BubbleView: View {
    let bubble: Bubble
    var isHighlighted: Bool = false

    @State private var expanded = false

    private var tint: Color { bubble.kind.tint }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                speakerLine
                content
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 5, bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18, topTrailingRadius: 18,
                    style: .continuous
                )
                .fill(Theme.panel)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 5, bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18, topTrailingRadius: 18,
                    style: .continuous
                )
                .strokeBorder(tint.opacity(isHighlighted ? 0.75 : 0.22),
                              lineWidth: isHighlighted ? 1.8 : 1)
            )

            Spacer(minLength: 22)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasMore else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { expanded.toggle() }
        }
    }

    private var hasMore: Bool { !bubble.detail.isEmpty || bubble.sighting != nil }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
            Text(bubble.kind.glyph).font(.system(size: 15))
        }
    }

    private var speakerLine: some View {
        HStack(spacing: 6) {
            Text(bubble.kind.speaker.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            Text(bubble.at, format: .dateTime.hour().minute())
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.slate.opacity(0.8))
            if hasMore {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Theme.slate.opacity(0.8))
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bubble.title)
                .font(Theme.title(15))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(bubble.body)
                .font(Theme.body(13.5))
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)

            if expanded {
                if let sighting = bubble.sighting { lookOut(sighting) }

                ForEach(Array(bubble.detail.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(tint.opacity(0.6))
                            .frame(width: 3.5, height: 3.5).padding(.top, 6)
                        Text(line)
                            .font(Theme.body(12.5))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func lookOut(_ sighting: POISighting) -> some View {
        HStack(spacing: 7) {
            Image(systemName: sighting.side == .left ? "arrow.left" :
                              sighting.side == .right ? "arrow.right" : "arrow.up")
                .font(.system(size: 10, weight: .black))
            Text(sighting.side == .ahead
                 ? "Dead ahead · \(Int(sighting.distanceKm)) km"
                 : "\(sighting.side.label.capitalized) · \(sighting.clock) o'clock · \(Int(sighting.distanceKm)) km")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Theme.amber.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.3), lineWidth: 1))
    }
}
