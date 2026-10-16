import Foundation
import SwiftUI

/// One message in the chat feed floating over the map.
struct Bubble: Identifiable, Hashable {
    var id = UUID()
    var kind: Kind
    var title: String
    var body: String
    /// Extra lines revealed when the bubble is tapped.
    var detail: [String] = []
    var at: Date = Date()
    /// Set when the bubble is anchored to somewhere on the map.
    var sighting: POISighting?
    /// Nudges the feed to bounce and, if enabled, fires a notification.
    var priority: Priority = .normal

    enum Kind: String {
        case poi, aviation, advice, milestone, system, stat, ai

        var glyph: String {
            switch self {
            case .poi:       return "📍"
            case .aviation:  return "✈️"
            case .advice:    return "🎯"
            case .milestone: return "🎉"
            case .system:    return "📡"
            case .stat:      return "📊"
            case .ai:        return "✨"
            }
        }

        var tint: Color {
            switch self {
            case .poi:       return Theme.cyan
            case .aviation:  return Theme.sky
            case .advice:    return Theme.amber
            case .milestone: return Theme.mint
            case .system:    return Theme.slate
            case .stat:      return Theme.violet
            case .ai:        return Theme.coral
            }
        }

        var speaker: String {
            switch self {
            case .poi:       return "Down Below"
            case .aviation:  return "Hangar Talk"
            case .advice:    return "Cabin Crew"
            case .milestone: return "Milestone"
            case .system:    return "Flight Deck"
            case .stat:      return "By the Numbers"
            case .ai:        return "Flight Facts AI"
            }
        }
    }

    enum Priority: Int, Comparable {
        case low = 0, normal = 1, high = 2

        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    static func == (a: Bubble, b: Bubble) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
