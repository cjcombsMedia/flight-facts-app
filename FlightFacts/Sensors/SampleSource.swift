import Foundation
import UIKit
import CoreLocation

/// Anything that can produce a stream of `FlightSample`s at roughly 1 Hz.
///
/// Two implementations ship in v1: real sensors, and a replay of a recorded
/// session. Everything downstream — detection, POI scouting, the whole UI —
/// only ever sees `FlightSample`, so the simulator demo exercises the exact
/// same code path a real flight does.
protocol SampleSource: AnyObject {
    var onSample: ((FlightSample) -> Void)? { get set }
    var isLive: Bool { get }
    func start()
    func stop()
}

/// Fuses GPS + barometer + IMU + battery into one RRCC-shaped sample per second.
/// The fusion rules themselves live in `SensorFusion`; this class only wires
/// the hardware to them on a 1 Hz clock.
final class LiveSensorSource: SampleSource {

    let location = LocationService()
    let motion = MotionService()

    var onSample: ((FlightSample) -> Void)?
    var isLive: Bool { true }

    private var timer: Timer?
    private var fusion = SensorFusion(startedAt: Date())

    var authorization: CLAuthorizationStatus { location.authorization }

    func requestPermissions() { location.requestAuthorization() }

    func start() {
        fusion = SensorFusion(startedAt: Date())
        UIDevice.current.isBatteryMonitoringEnabled = true
        location.start()
        motion.start()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.emit() }
        // .common so sampling keeps ticking while the map is being dragged.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        location.stop()
        motion.stop()
    }

    private func emit() {
        let level = UIDevice.current.batteryLevel
        let battery = level >= 0 ? Int((level * 100).rounded()) : nil
        guard let sample = fusion.sample(location: location.latest,
                                         motion: motion.snapshot(),
                                         battery: battery,
                                         now: Date()) else { return }
        onSample?(sample)
    }
}
