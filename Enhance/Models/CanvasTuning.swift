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

    // MARK: Path

    /// 0 travels at constant speed; 1 eases the whole journey in and out.
    var pathEase: Double
    /// Fraction of the GIF spent parked at each interior stop.
    var pathDwell: Double
    /// Whether the route rounds its corners (Catmull-Rom through the stops).
    var pathSmoothing: Bool
    /// 0 holds the pinched magnification; 1 ramps from the whole photo up to it over the route.
    var pathScaleRamp: Double
    /// Minimum distance between stops laid down by a drag, in canvas points.
    var pathSampleSpacing: Double

    // MARK: Video

    /// How many times the GIF's loop plays in an exported MP4.
    var videoLoops: Double
    /// H.264 average bitrate, in megabits per second.
    var videoBitrateMbps: Double

    // MARK: Burst

    /// Longest a held shutter records, in seconds. The GIF's own duration is SPEED's business;
    /// this is how much real motion there is to play.
    var burstDuration: Double
    /// Frames kept per second while recording. The tap runs at the camera's rate; this thins.
    var burstFPS: Double
    /// Side of the square each frame is normalized to. Memory is `side² × 4 × frames`; 720 at
    /// 18 frames is ~37MB, which a device handles and the generator's 600px output never sees
    /// past.
    var burstFrameSide: Double

    static let `default` = CanvasTuning(
        scrubSpan: 300,
        scrubTickEvery: 4,
        overdriveMax: 1.5,
        overdriveGain: 4,
        overdriveGlitchRate: 0.5,
        pathEase: 0.6,
        pathDwell: 0.1,
        pathSmoothing: true,
        pathScaleRamp: 0,
        pathSampleSpacing: 28,
        videoLoops: 3,
        videoBitrateMbps: 6,
        burstDuration: 1.5,
        burstFPS: 12,
        burstFrameSide: 720
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
            overdriveGlitchRate: \(Self.number(overdriveGlitchRate)),
            pathEase: \(Self.number(pathEase)),
            pathDwell: \(Self.number(pathDwell)),
            pathSmoothing: \(pathSmoothing),
            pathScaleRamp: \(Self.number(pathScaleRamp)),
            pathSampleSpacing: \(Self.number(pathSampleSpacing)),
            videoLoops: \(Self.number(videoLoops)),
            videoBitrateMbps: \(Self.number(videoBitrateMbps)),
            burstDuration: \(Self.number(burstDuration)),
            burstFPS: \(Self.number(burstFPS)),
            burstFrameSide: \(Self.number(burstFrameSide))
        )
        """
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.1f", value) : String(format: "%.3f", value)
    }
}
