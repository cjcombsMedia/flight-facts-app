import SwiftUI

/// Colours for the Live Activity. Duplicated from the app's `Theme` on purpose:
/// the widget extension is a separate binary and can't see app types.
enum ActivityPalette {
    static let ink    = Color(red: 0.03, green: 0.06, blue: 0.12)
    static let cyan   = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let mint   = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let amber  = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let coral  = Color(red: 0.98, green: 0.44, blue: 0.52)
    static let violet = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let slate  = Color(red: 0.62, green: 0.68, blue: 0.76)

    static func phase(_ raw: String) -> Color {
        switch raw {
        case "climb", "landed":               return mint
        case "cruise":                        return cyan
        case "descent", "taxi":               return amber
        case "approach", "takeoffRoll":       return coral
        default:                              return slate
        }
    }
}

/// The Lock Screen banner: phase and numbers across the top, the latest fact
/// in the middle, route progress along the bottom.
struct FlightLockScreenView: View {
    let attributes: FlightActivityAttributes
    let state: FlightActivityAttributes.ContentState

    private var tint: Color { ActivityPalette.phase(state.phaseRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            fact
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(state.phaseGlyph).font(.system(size: 14))
            Text(state.phaseTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text("·").foregroundStyle(ActivityPalette.slate)
            Text(attributes.routeTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(state.altitudeText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    private var fact: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.2)).frame(width: 34, height: 34)
                Text(state.factGlyph).font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.factTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.factBody)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let progress = state.progress {
                ProgressView(value: min(1, max(0, progress)))
                    .tint(tint)
                    .frame(maxWidth: .infinity)
            } else {
                Text(state.speedText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ActivityPalette.slate)
                Spacer(minLength: 0)
            }
            if state.gpsEstimated {
                Label("GPS est.", systemImage: "location.slash")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ActivityPalette.amber)
            } else if let remaining = state.remainingText {
                Text(remaining)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(ActivityPalette.slate)
                    .lineLimit(1)
            }
            Text("📍\(state.poiCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(ActivityPalette.slate)
        }
    }
}
