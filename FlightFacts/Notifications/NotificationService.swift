import Foundation
import UserNotifications

/// Local notifications only — no server, no network, works at 38,000 ft in
/// airplane mode. Everything is scheduled with a ~1 second trigger so it fires
/// immediately whether the app is foreground or background.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false

    /// Fired when the user taps a notification, so the UI can scroll to it.
    var onTapped: ((UUID) -> Void)?

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.isAuthorized = granted }
        }
        registerCategories()
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
        }
    }

    private func registerCategories() {
        let poi = UNNotificationCategory(identifier: "POI", actions: [],
                                         intentIdentifiers: [], options: [])
        let advice = UNNotificationCategory(identifier: "ADVICE", actions: [],
                                            intentIdentifiers: [], options: [])
        center.setNotificationCategories([poi, advice])
    }

    /// Posts a bubble as a notification. High-priority bubbles get a sound.
    func post(_ bubble: Bubble) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(bubble.kind.glyph) \(bubble.title)"
        content.body = bubble.body
        content.sound = bubble.priority == .high ? .default : nil
        content.interruptionLevel = bubble.priority == .high ? .timeSensitive : .active
        content.categoryIdentifier = bubble.kind == .advice ? "ADVICE" : "POI"
        content.threadIdentifier = bubble.kind.rawValue     // groups by speaker
        content.userInfo = ["bubbleID": bubble.id.uuidString]

        let request = UNNotificationRequest(
            identifier: bubble.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even when the app is open — the user is usually looking at
    /// the map, not the feed, and a banner is how they notice a new bubble.
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["bubbleID"] as? String,
           let id = UUID(uuidString: raw) {
            DispatchQueue.main.async { self.onTapped?(id) }
        }
        completion()
    }
}
