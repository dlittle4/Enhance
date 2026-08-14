import Combine
import CoreMotion
import SwiftUI

/// Device tilt, smoothed into something a view can be offset by.
///
/// Naming follows the app's other small services — `HapticService`, `PhotoManager`,
/// `PermissionManager`. Deliberately **not** a singleton: the gallery is the only screen that
/// wants tilt, and a shared instance would outlive it and keep the accelerometer running behind
/// the editor. One owner, one lifetime.
///
/// `CMMotionManager` needs no `Info.plist` entry for accelerometer or device-motion updates —
/// that requirement belongs to `CMMotionActivityManager`'s pedometer data, which this does not
/// touch.
final class DeviceMotionService: ObservableObject {

    /// Smoothed tilt in roughly -1…1 per axis, ready to be multiplied by a magnitude in points.
    @Published private(set) var tilt: CGSize = .zero

    private let manager = CMMotionManager()

    /// Weight kept from the previous sample. Raw accelerometer output is noisy enough that
    /// feeding it straight to a transform makes the grid twitch rather than drift; this is the
    /// difference between "considered" and "broken".
    private var smoothing: Double = 0.9

    /// 30Hz rather than display rate. The parallax is a slow drift of a few points — sampling
    /// faster costs battery to compute a number that rounds to the same offset.
    private let updateInterval: TimeInterval = 1.0 / 30.0

    var isRunning: Bool { manager.isDeviceMotionActive }

    /// Starts updates, or does nothing if the device has no motion hardware or is already running.
    ///
    /// `smoothing` is passed per-start rather than stored once so MOTION LAB can retune it live.
    func start(smoothing: Double) {
        self.smoothing = max(0, min(0.99, smoothing))

        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }

        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Attitude rather than raw acceleration: roll and pitch describe how the device is
            // *held*, which is what a parallax should follow. Raw acceleration also carries every
            // bump of walking, which would read as the grid being jostled.
            let targetX = motion.attitude.roll
            let targetY = motion.attitude.pitch

            // Clamped before smoothing, so tipping the device right over cannot slew the grid far
            // off and then take seconds to crawl back.
            let clampedX = max(-1, min(1, targetX))
            let clampedY = max(-1, min(1, targetY))

            let weight = self.smoothing
            self.tilt = CGSize(
                width: self.tilt.width * weight + clampedX * (1 - weight),
                height: self.tilt.height * weight + clampedY * (1 - weight)
            )
        }
    }

    /// Stops updates and settles the grid back to centre.
    ///
    /// Called whenever the gallery is not the thing on screen — the editor opening, the app
    /// backgrounding, the view disappearing. `CMMotionManager` runs continuously once started, so
    /// leaving it on behind another screen is a battery cost for motion nobody can see.
    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        tilt = .zero
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
