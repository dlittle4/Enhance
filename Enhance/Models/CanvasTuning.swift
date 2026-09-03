import CoreGraphics
import Foundation

/// Every numeric knob on the touch experiments — scrubbing the preview, slider overdrive — in one
/// value. Same premise as `FaceMarkerTuning`: how far a finger drags per loop and how far past
/// 100% a slider may go cannot be specified, only recognised, and hardcoding them is a rebuild
/// per guess.
///
/// **Scaffolding.** When an experiment graduates, `swiftSnippet` becomes constants at the top of
/// the component that reads it, and this file, `CanvasTuningStore` and `CanvasLabView` go.
struct CanvasTuning: Codable, Equatable {

    // MARK: Scrub

    /// Points of horizontal drag that scrub one full loop of the GIF. Smaller is twitchier.
    var scrubSpan: Double

    /// A haptic tick every this many frames crossed while scrubbing. 1 ticks on every frame,
    /// which at 25fps is a buzz rather than a series of detents.
    var scrubTickEvery: Double

    // MARK: Overdrive

    /// How far a slider may be dragged past its end, as a multiple of full scale. 1.5 reads as
    /// "30" on the 20-dot knob. Effects are handed the raw value; how much of it each one honours
    /// is that effect's own business, which is the point.
    var overdriveMax: Double

    /// How much faster the value climbs once the finger is past the track's end. The track's own
    /// lattice is ~15pt per step and the screen ends 30-odd points past the last dot, so at gain
    /// 1 a phone can only reach ~110%; at 4 the same reach is ~140%.
    var overdriveGain: Double

    /// Probability, per 90ms tick, that the overdriven knob's readout scrambles a character.
    /// 0 is a steady red number.
    var overdriveGlitchRate: Double

    static let `default` = CanvasTuning(
        scrubSpan: 300,
        scrubTickEvery: 4,
        overdriveMax: 1.5,
        overdriveGain: 4,
        overdriveGlitchRate: 0.5
    )

    // MARK: - Scrub arithmetic

    /// Which frame a drag lands on. Pure so the wrap and the direction are testable without a
    /// touch: a drag to the right advances, and past either end it wraps rather than pinning,
    /// so a long drag keeps the loop under the finger.
    static func scrubbedFrame(from start: Int, dragX: CGFloat, span: Double, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        let perFrame = max(1, span) / Double(frameCount)
        let delta = Int((Double(dragX) / perFrame).rounded())
        let raw = (start + delta) % frameCount
        return raw < 0 ? raw + frameCount : raw
    }

    // MARK: - Snippet

    var swiftSnippet: String {
        """
        // Copied from CANVAS LAB.
        static let tuned = CanvasTuning(
            scrubSpan: \(Self.number(scrubSpan)),
            scrubTickEvery: \(Self.number(scrubTickEvery)),
            overdriveMax: \(Self.number(overdriveMax)),
            overdriveGain: \(Self.number(overdriveGain)),
            overdriveGlitchRate: \(Self.number(overdriveGlitchRate))
        )
        """
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.1f", value) : String(format: "%.3f", value)
    }
}
