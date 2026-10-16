import Foundation
import ActivityKit

/// The Live Activity's data contract. Compiled into both the app (which starts
/// and updates the activity) and the widget extension (which draws it).
///
/// Everything here is pre-formatted text and small numbers: the extension can't
/// see the app's models, and ActivityKit caps the encoded state at 4 KB.
struct FlightActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var phaseRaw: String
        var phaseTitle: String
        var phaseGlyph: String

        var altitudeText: String      // "38,120 ft"
        var altitudeShort: String     // "38.1k" — Dynamic Island compact slot
        var speedText: String         // "541 mph"

        var factGlyph: String
        var factSpeaker: String
        var factTitle: String
        var factBody: String

        /// 0–1 along the planned route, when there is one.
        var progress: Double?
        var remainingText: String?

        var gpsEstimated: Bool
        var poiCount: Int
        var updatedAt: Date
    }

    var routeTitle: String
    var seatLabel: String?
}

extension FlightActivityAttributes.ContentState {
    /// Placeholder used for previews and the first frame.
    static let preview = FlightActivityAttributes.ContentState(
        phaseRaw: "cruise", phaseTitle: "Cruising", phaseGlyph: "✈️",
        altitudeText: "38,120 ft", altitudeShort: "38.1k", speedText: "541 mph",
        factGlyph: "📍", factSpeaker: "Down Below",
        factTitle: "🏜️ Chihuahuan Desert",
        factBody: "Out the left window — 10 o'clock, 52 mi. The largest desert in North America. Most of it sits above 3,500 feet, which is why it gets snow.",
        progress: 0.42, remainingText: "712 mi to go",
        gpsEstimated: false, poiCount: 6, updatedAt: Date()
    )
}
