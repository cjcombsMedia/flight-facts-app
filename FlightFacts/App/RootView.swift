import SwiftUI

struct RootView: View {
    @Environment(FlightEngine.self) private var engine

    @State private var showLog = false
    @State private var showSettings = false
    @State private var showPlanner = false

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()

            switch engine.state {
            case .idle:
                PreflightView(showLog: $showLog, showSettings: $showSettings)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))

            case .scanning:
                ScannerView()
                    .transition(.opacity)

            case .flying:
                FlightView(showSettings: $showSettings)
                    .transition(.opacity)

            case .finished:
                ArrivalView(showLog: $showLog)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: engine.state)
        .sheet(isPresented: $showLog) { LogView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear(perform: autostartIfRequested)
        .sheet(isPresented: $showPlanner) { FlightPlanView() }
    }

    /// Dev hook: launch with `-autodemo <routeID>` (optionally `-demoSpeed <n>`)
    /// to jump straight into a demo flight. Used for screenshots and for
    /// iterating on the in-flight UI without waiting at the gate.
    ///
    ///     xcrun simctl launch booted com.cjcombs.flightfacts -autodemo lax-jfk -demoSpeed 400
    private func autostartIfRequested() {
        let args = UserDefaults.standard

        // `-openPlanner 1` jumps straight to the flight planner.
        if args.bool(forKey: "openPlanner") { showPlanner = true }

        // `-planRoute PHX-MEX -planSeat left` seeds a plan without typing one.
        if let route = args.string(forKey: "planRoute") {
            let parts = route.split(separator: "-").map(String.init)
            if parts.count == 2,
               let from = AirportStore.shared.airport(parts[0]),
               let to = AirportStore.shared.airport(parts[1]) {
                let seat = SeatSide(rawValue: args.string(forKey: "planSeat") ?? "") ?? .centre
                engine.setPlan(FlightPlan(origin: from, destination: to, seat: seat))
            }
        }

        guard let target = args.string(forKey: "autodemo"), engine.state == .idle else { return }

        let speed = args.double(forKey: "demoSpeed")
        if speed > 0 { AppSettings.shared.demoSpeed = speed }

        if let route = DemoRoute.all.first(where: { $0.id == target }) {
            engine.startScanning(mode: .demo(route))
        } else {
            // Anything else is treated as the name of a bundled recording.
            engine.startScanning(mode: .replay(target))
        }
    }
}
