import Foundation

/// Conversion between the 0…1 slider position the UI works in and the real units the
/// GIF generator consumes — playback speed in multiples, pause in seconds.
///
/// Deliberately free of UIKit and SwiftUI: this is where every unit decision lives, so
/// it can be reasoned about and tested without a view. Speed and pause were discrete
/// cycling buttons before (four speeds, five whole-second pauses) and never reached the
/// range `GIFGenerator` already clamps to.
enum ZoomPlayback {

    // MARK: - Range

    /// Matches `GIFGenerator.prepareDrawingContext`'s clamp exactly. If one changes, the
    /// other must — `speed_unitEndpointsMatchGeneratorClamps` fails if they drift.
    static let minSpeed: Double = 0.25
    static let maxSpeed: Double = 4.0
    static let maxPause: Double = 5.0

    static let defaultSpeed: Double = 0.5
    static let defaultPause: Double = 1.0

    // MARK: - Slider position → real units

    /// Speed is **geometric**, not linear: `0.25 · 16^u`.
    ///
    /// Doubling is what the eye notices, so equal travel should mean equal *ratio* —
    /// the same reason zoom interpolation is done in log space (LEARNINGS 2026-03-08).
    /// It also puts 1× exactly at the track midpoint, and lands both defaults on the
    /// slider's 20-step lattice: 0.5× at step 5, so the default does not jump the first
    /// time the knob is touched. A linear map does neither.
    static func speed(unit: Double) -> Double {
        let u = max(0, min(1, unit))
        return minSpeed * pow(maxSpeed / minSpeed, u)
    }

    static func unit(speed: Double) -> Double {
        let s = max(minSpeed, min(maxSpeed, speed))
        return log(s / minSpeed) / log(maxSpeed / minSpeed)
    }

    /// Pause is **linear** — seconds are seconds, and 0…5 over 20 steps gives quarter
    /// seconds, which is finer than anyone needs but costs nothing. Step 4 is exactly 1s.
    static func pause(unit: Double) -> Double {
        max(0, min(1, unit)) * maxPause
    }

    static func unit(pause: Double) -> Double {
        max(0, min(maxPause, pause)) / maxPause
    }

    // MARK: - Display

    /// `0.25X`, `1X`, `1.5X`, `4X` — trailing zeros dropped. Replaces a formatter that
    /// did `Int(playbackSpeed)` and rendered 1.5 as "1X"; harmless when only four exact
    /// values were reachable, wrong the moment the slider is continuous.
    static func speedText(_ speed: Double) -> String {
        "\(trimmed(speed))X"
    }

    /// `0S`, `1S`, `2.5S`. Short because it lives inside a 34pt slider knob — the old
    /// "1 SECOND" / "3 SECONDS" wording was sized for a full-width button.
    static func pauseText(_ pause: Double) -> String {
        "\(trimmed(pause))S"
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%g", rounded)
    }

    // MARK: - Default comparison

    /// Tolerant on purpose. The geometric round-trip is not bit-exact — returning the
    /// slider to its default position yields 0.5000000000000001 — so an `==` here would
    /// leave RESET visible forever once the knob had been touched and put back.
    private static let epsilon = 1e-6

    static func isDefaultSpeed(_ speed: Double) -> Bool {
        abs(speed - defaultSpeed) < epsilon
    }

    static func isDefaultPause(_ pause: Double) -> Bool {
        abs(pause - defaultPause) < epsilon
    }
}
