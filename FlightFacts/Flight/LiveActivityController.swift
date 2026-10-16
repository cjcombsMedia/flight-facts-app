import Foundation
import ActivityKit

/// Owns the Lock Screen / Dynamic Island Live Activity for the current flight.
///
/// Updates are local — the app pushes them while it's running, which it is for
/// the whole flight thanks to background location. No server, no push token,
/// so it works in airplane mode.
///
/// iOS rate-limits how often a Live Activity redraws, and a fast demo can emit
/// several facts a second, so updates are coalesced: within `minInterval` of the
/// last push, only the most recent state is kept and sent when the window opens.
@MainActor
final class LiveActivityController {

    typealias State = FlightActivityAttributes.ContentState

    private var activity: Activity<FlightActivityAttributes>?
    private var lastPush: Date?
    private var pending: State?
    private var flushTask: Task<Void, Never>?

    private let minInterval: TimeInterval = 4
    /// If the app dies mid-flight the banner greys out instead of lying.
    private let staleAfter: TimeInterval = 15 * 60

    var isRunning: Bool { activity != nil }

    /// Whether the user allows Live Activities for this app (Settings › Flight Facts).
    var isPermitted: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(routeTitle: String, seatLabel: String?, state: State) {
        guard isPermitted, activity == nil else { return }

        // Clear any banner orphaned by a previous run that crashed or was killed.
        for stale in Activity<FlightActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = FlightActivityAttributes(routeTitle: routeTitle, seatLabel: seatLabel)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter)),
                pushType: nil
            )
            lastPush = Date()
        } catch {
            // Disabled by the user or system budget exhausted — the app works fine
            // without it, so there's nothing to surface.
            activity = nil
        }
    }

    /// Queue a new state. `urgent` skips the coalescing window — used for the
    /// cabin-crew alerts, where a four-second delay would be a real cost.
    func update(_ state: State, urgent: Bool = false) {
        guard activity != nil else { return }
        let now = Date()
        if urgent || lastPush.map({ now.timeIntervalSince($0) >= minInterval }) ?? true {
            push(state)
            return
        }
        pending = state
        guard flushTask == nil else { return }
        let wait = minInterval - now.timeIntervalSince(lastPush ?? now)
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, wait) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            if let next = self.pending { self.push(next) }
        }
    }

    func end(final state: State?) {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        guard let activity else { return }
        self.activity = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        // Leave the arrival summary on the Lock Screen for a while after landing.
        Task { await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))) }
    }

    private func push(_ state: State) {
        guard let activity else { return }
        pending = nil
        lastPush = Date()
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
        Task { await activity.update(content) }
    }
}
