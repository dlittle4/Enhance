import CoreGraphics
import Foundation

struct CameraZoomOption: Equatable {
    /// Silkscreen-ready: "0.5X", "1X", "3X".
    let label: String
    /// The raw `videoZoomFactor` to apply — on a virtual device this is in ultra-wide units,
    /// so "1X" may well carry a factor of 2.
    let videoZoomFactor: CGFloat
}

/// The zoom stops the pill cycles through, derived from a device's capabilities.
///
/// Pure math, kept apart from `AVCameraService` because the mapping is the subtle part of the
/// camera: on a virtual device (`builtInTripleCamera` etc.) `videoZoomFactor == 1` is the
/// **ultra-wide** module, and `virtualDeviceSwitchOverVideoZoomFactors` marks where the wide
/// and telephoto modules take over. What users know as "1X" is the *first switchover*, which
/// is why display labels divide by it. A single-module device (front camera, older rear) has
/// no switchovers and its factor 1 really is 1X.
enum CameraZoomLadder {

    /// - Parameters:
    ///   - switchOverFactors: `virtualDeviceSwitchOverVideoZoomFactors`; empty on
    ///     single-module devices.
    ///   - maxZoomFactor: the device's usable ceiling; switchovers beyond it are dropped.
    static func make(switchOverFactors: [CGFloat], maxZoomFactor: CGFloat) -> [CameraZoomOption] {
        let switchOvers = switchOverFactors.filter { $0 > 1 && $0 <= maxZoomFactor }.sorted()

        guard let wide = switchOvers.first else {
            // Single module: the sensor is 1X, and a digital 2X is offered when the format
            // allows it — matching what the system camera gives these devices.
            var options = [CameraZoomOption(label: label(forDisplayFactor: 1), videoZoomFactor: 1)]
            if maxZoomFactor >= 2 {
                options.append(CameraZoomOption(label: label(forDisplayFactor: 2), videoZoomFactor: 2))
            }
            return options
        }

        // Virtual device: one optical stop per module — ultra-wide (factor 1), then each
        // switchover. All optical, so every stop is a real lens rather than a digital crop.
        let factors = [1.0] + switchOvers
        return factors.map {
            CameraZoomOption(label: label(forDisplayFactor: $0 / wide), videoZoomFactor: $0)
        }
    }

    /// Where the pill starts: the "1X" stop, whatever raw factor it carries.
    static func defaultIndex(in options: [CameraZoomOption]) -> Int {
        options.firstIndex { $0.label == "1X" } ?? 0
    }

    static func label(forDisplayFactor factor: CGFloat) -> String {
        // One decimal at most, trailing zeros stripped: 0.5X, 1X, 3X.
        let rounded = (factor * 10).rounded() / 10
        return String(format: "%gX", Double(rounded))
    }
}
