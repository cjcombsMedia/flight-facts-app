import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FlightFactsWidgets: WidgetBundle {
    var body: some Widget {
        FlightLiveActivity()
    }
}

/// Lock Screen banner plus Dynamic Island presentations for an active flight.
struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            FlightLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(ActivityPalette.ink.opacity(0.92))
                .activitySystemActionForegroundColor(ActivityPalette.cyan)
        } dynamicIsland: { context in
            let state = context.state
            let tint = ActivityPalette.phase(state.phaseRaw)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Text(state.phaseGlyph)
                        Text(state.phaseTitle)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.altitudeText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(state.factGlyph) \(state.factTitle)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text(state.factBody)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                        if let progress = state.progress {
                            ProgressView(value: min(1, max(0, progress)))
                                .tint(tint)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(state.phaseGlyph)
            } compactTrailing: {
                Text(state.altitudeShort)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            } minimal: {
                Text(state.phaseGlyph)
            }
            .keylineTint(tint)
        }
    }
}
