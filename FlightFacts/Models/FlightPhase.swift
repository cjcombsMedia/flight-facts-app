import Foundation
import SwiftUI

/// Where we are in the arc of a flight. Ordered roughly by progression, but the
/// detector is free to jump straight to `.cruise` when the app is opened at
/// 38,000 ft — that's the whole point of "detect no matter when you start".
enum FlightPhase: String, Codable, CaseIterable {
    case unknown
    case atGate
    case taxi
    case takeoffRoll
    case climb
    case cruise
    case descent
    case approach
    case landed

    var title: String {
        switch self {
        case .unknown:     return "Looking around"
        case .atGate:      return "At the gate"
        case .taxi:        return "Taxiing"
        case .takeoffRoll: return "Takeoff roll"
        case .climb:       return "Climbing"
        case .cruise:      return "Cruising"
        case .descent:     return "Descending"
        case .approach:    return "On approach"
        case .landed:      return "Landed"
        }
    }

    var glyph: String {
        switch self {
        case .unknown:     return "🛰️"
        case .atGate:      return "🛄"
        case .taxi:        return "🛫"
        case .takeoffRoll: return "🚀"
        case .climb:       return "📈"
        case .cruise:      return "✈️"
        case .descent:     return "📉"
        case .approach:    return "🛬"
        case .landed:      return "🧳"
        }
    }

    var tint: Color {
        switch self {
        case .unknown:     return Theme.slate
        case .atGate:      return Theme.slate
        case .taxi:        return Theme.amber
        case .takeoffRoll: return Theme.coral
        case .climb:       return Theme.mint
        case .cruise:      return Theme.cyan
        case .descent:     return Theme.amber
        case .approach:    return Theme.coral
        case .landed:      return Theme.mint
        }
    }

    /// True once we believe the wheels have left the ground.
    var isAirborne: Bool {
        switch self {
        case .climb, .cruise, .descent, .approach: return true
        default: return false
        }
    }

    /// True for anything that counts as an active flight session worth logging.
    var isActiveFlight: Bool {
        switch self {
        case .unknown, .atGate: return false
        default: return true
        }
    }
}
