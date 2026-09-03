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

    /// Side of each thumb in the filmstrip that appears under a scrubbing finger, in points.
    var scrubStripThumb: Double
    /// The filmstrip's look, as sliders *(user's ask, 2026-09-03)* — see `ScrubStripStyle`.
    /// Shrink per step from the centre, the size floor, tilt per step (radians), fade per step,
    /// the gap between thumbs, and how far the strip rises on entrance.
    var scrubStripFalloff: Double
    var scrubStripMinScale: Double
    var scrubStripTilt: Double
    var scrubStripFade: Double
    var scrubStripGap: Double
    var scrubStripRise: Double

    var scrubStripStyle: ScrubStripStyle {
        ScrubStripStyle(
            thumb: scrubStripThumb, falloffPerStep: scrubStripFalloff, minimumScale: scrubStripMinScale,
            tiltPerStep: scrubStripTilt, fadePerStep: scrubStripFade, gap: scrubStripGap, entranceRise: scrubStripRise
        )
    }

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
        scrubStripThumb: 40,
        scrubStripFalloff: 0.05,
        scrubStripMinScale: 0.72,
        scrubStripTilt: 0.06,
        scrubStripFade: 0.05,
        scrubStripGap: 3,
        scrubStripRise: 18,
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

    // MARK: - Decoding

    /// Knobs added after a blob was saved decode to their defaults rather than failing the
    /// whole blob — otherwise every lab value would silently reset on the first launch after
    /// a new knob ships. Only the late additions are `decodeIfPresent`; the original set is
    /// required, as before.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CanvasTuning.default
        scrubSpan = try c.decode(Double.self, forKey: .scrubSpan)
        scrubTickEvery = try c.decode(Double.self, forKey: .scrubTickEvery)
        scrubStripThumb = try c.decodeIfPresent(Double.self, forKey: .scrubStripThumb) ?? d.scrubStripThumb
        scrubStripFalloff = try c.decodeIfPresent(Double.self, forKey: .scrubStripFalloff) ?? d.scrubStripFalloff
        scrubStripMinScale = try c.decodeIfPresent(Double.self, forKey: .scrubStripMinScale) ?? d.scrubStripMinScale
        scrubStripTilt = try c.decodeIfPresent(Double.self, forKey: .scrubStripTilt) ?? d.scrubStripTilt
        scrubStripFade = try c.decodeIfPresent(Double.self, forKey: .scrubStripFade) ?? d.scrubStripFade
        scrubStripGap = try c.decodeIfPresent(Double.self, forKey: .scrubStripGap) ?? d.scrubStripGap
        scrubStripRise = try c.decodeIfPresent(Double.self, forKey: .scrubStripRise) ?? d.scrubStripRise
        overdriveMax = try c.decode(Double.self, forKey: .overdriveMax)
        overdriveGain = try c.decodeIfPresent(Double.self, forKey: .overdriveGain) ?? d.overdriveGain
        overdriveGlitchRate = try c.decode(Double.self, forKey: .overdriveGlitchRate)
        pathEase = try c.decodeIfPresent(Double.self, forKey: .pathEase) ?? d.pathEase
        pathDwell = try c.decodeIfPresent(Double.self, forKey: .pathDwell) ?? d.pathDwell
        pathSmoothing = try c.decodeIfPresent(Bool.self, forKey: .pathSmoothing) ?? d.pathSmoothing
        pathScaleRamp = try c.decodeIfPresent(Double.self, forKey: .pathScaleRamp) ?? d.pathScaleRamp
        pathSampleSpacing = try c.decodeIfPresent(Double.self, forKey: .pathSampleSpacing) ?? d.pathSampleSpacing
        videoLoops = try c.decodeIfPresent(Double.self, forKey: .videoLoops) ?? d.videoLoops
        videoBitrateMbps = try c.decodeIfPresent(Double.self, forKey: .videoBitrateMbps) ?? d.videoBitrateMbps
        burstDuration = try c.decodeIfPresent(Double.self, forKey: .burstDuration) ?? d.burstDuration
        burstFPS = try c.decodeIfPresent(Double.self, forKey: .burstFPS) ?? d.burstFPS
        burstFrameSide = try c.decodeIfPresent(Double.self, forKey: .burstFrameSide) ?? d.burstFrameSide
    }

    init(scrubSpan: Double, scrubTickEvery: Double, scrubStripThumb: Double,
         scrubStripFalloff: Double, scrubStripMinScale: Double, scrubStripTilt: Double,
         scrubStripFade: Double, scrubStripGap: Double, scrubStripRise: Double, overdriveMax: Double, overdriveGain: Double, overdriveGlitchRate: Double, pathEase: Double, pathDwell: Double, pathSmoothing: Bool, pathScaleRamp: Double, pathSampleSpacing: Double, videoLoops: Double, videoBitrateMbps: Double, burstDuration: Double, burstFPS: Double, burstFrameSide: Double) {
        self.scrubSpan = scrubSpan; self.scrubTickEvery = scrubTickEvery; self.scrubStripThumb = scrubStripThumb
        self.scrubStripFalloff = scrubStripFalloff; self.scrubStripMinScale = scrubStripMinScale
        self.scrubStripTilt = scrubStripTilt; self.scrubStripFade = scrubStripFade
        self.scrubStripGap = scrubStripGap; self.scrubStripRise = scrubStripRise
        self.overdriveMax = overdriveMax; self.overdriveGain = overdriveGain; self.overdriveGlitchRate = overdriveGlitchRate
        self.pathEase = pathEase; self.pathDwell = pathDwell; self.pathSmoothing = pathSmoothing
        self.pathScaleRamp = pathScaleRamp; self.pathSampleSpacing = pathSampleSpacing
        self.videoLoops = videoLoops; self.videoBitrateMbps = videoBitrateMbps
        self.burstDuration = burstDuration; self.burstFPS = burstFPS; self.burstFrameSide = burstFrameSide
    }

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
            scrubStripThumb: \(Self.number(scrubStripThumb)),
            scrubStripFalloff: \(Self.number(scrubStripFalloff)),
            scrubStripMinScale: \(Self.number(scrubStripMinScale)),
            scrubStripTilt: \(Self.number(scrubStripTilt)),
            scrubStripFade: \(Self.number(scrubStripFade)),
            scrubStripGap: \(Self.number(scrubStripGap)),
            scrubStripRise: \(Self.number(scrubStripRise)),
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
