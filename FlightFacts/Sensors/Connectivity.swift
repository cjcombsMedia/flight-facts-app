import Foundation
import Network

/// Whether any network path is up. Used to show the "offline" pill — so you can
/// see the app is still working in airplane mode — and to skip online
/// enrichment entirely rather than fire requests that can only fail.
@MainActor
@Observable
final class Connectivity {

    private(set) var isOnline = true
    /// In-flight Wi-Fi is usually metered or captive; worth knowing.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "flightfacts.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isOnline = online
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
