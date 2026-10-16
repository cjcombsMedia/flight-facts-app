import Foundation
import CoreMotion

/// Barometer + IMU.
///
/// The barometer is the single most useful non-GPS sensor on a plane: it reads
/// *cabin* pressure, which tracks the pressurisation schedule. Cabin altitude
/// climbs on departure and descends on arrival even when GPS has dropped out,
/// so it gives the detector an independent vote on climb vs. descent.
///
/// The IMU gives turbulence (accel RMS) and turn rate (gyro magnitude).
///
/// Sensor callbacks land on a background queue and the sampler reads on the
/// main thread, so all shared state sits behind a lock and is handed out as a
/// `MotionSnapshot` copy.
final class MotionService {

    private let altimeter = CMAltimeter()
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()

    private var state = MotionSnapshot(hasBarometer: CMAltimeter.isRelativeAltitudeAvailable())
    private var window: [Double] = []      // touched only on `queue`
    private let windowCapacity = 128

    init() {
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
    }

    func snapshot() -> MotionSnapshot {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    func start() {
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
                guard let self, let data else { return }
                self.lock.lock()
                self.state.relativeAltitude = data.relativeAltitude.doubleValue
                self.state.pressure = data.pressure.doubleValue   // kPa
                self.lock.unlock()
            }
        }

        guard motion.isDeviceMotionAvailable else { return }
        // 20 Hz is plenty for turbulence energy and far cheaper than the 100 Hz
        // the RRCC capture used.
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] dm, _ in
            guard let self, let dm else { return }

            let a = dm.userAcceleration
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let r = dm.rotationRate
            let gyro = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)

            self.window.append(mag)
            if self.window.count > self.windowCapacity { self.window.removeFirst() }
            let sumSq = self.window.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumSq / Double(self.window.count))
            let peak = self.window.max() ?? 0

            self.lock.lock()
            self.state.gyro = gyro
            self.state.accelRMS = rms
            self.state.accelPeak = peak
            self.state.count = self.window.count
            self.lock.unlock()
        }
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        motion.stopDeviceMotionUpdates()
        queue.addOperation { [weak self] in self?.window.removeAll() }
    }
}
