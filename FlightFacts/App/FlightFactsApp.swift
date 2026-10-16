import SwiftUI

@main
struct FlightFactsApp: App {
    @State private var engine = FlightEngine()
    @State private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(settings)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        engine.refreshPermissionStatus()
                        // iOS drops the idle-timer override on backgrounding,
                        // so re-assert it when we come back.
                        engine.refreshScreenAwakePreference()
                    }
                }
        }
    }
}
