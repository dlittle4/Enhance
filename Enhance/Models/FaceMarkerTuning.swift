import CoreGraphics
import Foundation

/// Every numeric knob on the face-marker experiments, in one value.
///
/// It exists for the same reason `GradientTuning` does: a bracket length, a dim opacity and a
/// hide delay cannot be specified, only recognised. Hardcoding them means a rebuild per guess,
/// which is how the current overlay ended up with an infinite pulse nobody re-examined.
///
/// **Scaffolding.** When a variant graduates, `swiftSnippet` becomes the new constants at the top
/// of `FaceMarkerView` / `FaceSpotlightLayer` and this file, `FaceMarkerTuningStore` and
/// `FaceMarkerLabView` all go. That is why it is one struct behind one `UserDefaults` key rather
/// than a scattering of properties — graduation is one `removeObject`.
struct FaceMarkerTuning: Codable, Equatable {

    // MARK: Calm

    /// Seconds a marker stays up after the last canvas touch before fading to `restingOpacity`.
    /// 0 disables the fade, which is the honest way to compare against today's always-on chrome.
    var autoHideDelay: Double

    /// What it fades *to*. 0 hides it completely; the marker stays tappable either way, because the
    /// hit region is not the drawing.
    var restingOpacity: Double

    /// Seconds of the one-shot flash when the target changes — what replaces the infinite pulse.
    var flashDuration: Double

    /// Minimum tap target in points, honoured regardless of how small the face is on screen.
    /// Apple's floor is 44; the current overlay has none at all, so a face in a group photo can be
    /// a sub-20pt target.
    var minimumTapTarget: Double

    /// Stroke for the quiet outline CALM and SPOTLIGHT draw, in points on screen.
    ///
    /// Deliberately thinner than DEFAULT's 2–3pt and with no fill behind it, because **each variant
    /// has to be recognisable at a glance or the comparison is not a comparison** — CALM and
    /// SPOTLIGHT originally reused the legacy box and were indistinguishable from DEFAULT in a
    /// still *(user-reported)*.
    var quietStroke: Double

    // MARK: Reticle

    /// Corner bracket arm length, as a fraction of the marker's shorter side.
    ///
    /// Past ~0.5 the four brackets meet and it is a rectangle again, which is the look this variant
    /// exists to get away from.
    var bracketLength: Double

    /// Bracket stroke in points, measured on screen — counter-scaled against the zoom, so this
    /// stays honest at 3× where the current 3pt border renders 9.
    var bracketThickness: Double

    /// Inflation of Vision's bounding box before drawing.
    ///
    /// The box is tight to the face, and a reticle that clips the hairline reads as a mistake
    /// rather than as framing. 1.0 draws exactly what Vision returned.
    var markerScale: Double

    /// Scale the brackets start from when they lock on, and how long that takes. This is the whole
    /// of the animation vocabulary — one shot, on appearance.
    var lockOnScale: Double
    var lockOnDuration: Double

    /// Whether the `FACE 01` chip draws under each marker.
    var showsIndexLabel: Bool

    /// Chip type size in points, on screen. Silkscreen is a bitmap face, so non-integer sizes
    /// blur — the lab slider steps in whole points for that reason.
    var labelSize: Double

    /// How far a marker that is *not* the target fades, when one face is soloed. 1 draws unselected
    /// faces as brightly as the chosen one, which makes the choice invisible.
    var unselectedOpacity: Double

    // MARK: Scanline

    /// Seconds for one full sweep of the band from the top of the marker to the bottom. It
    /// bounces rather than wrapping, so a round trip is twice this.
    var scanlineDuration: Double

    /// Peak alpha at the centre of the band. The whole point is that it should be noticed on the
    /// second look rather than the first, so this wants to stay low.
    var scanlineOpacity: Double

    /// Band height as a fraction of the marker's height. Small values read as a hard line sweeping;
    /// large ones as light washing over the face.
    var scanlineHeight: Double

    // MARK: Spotlight

    /// Peak darkness applied outside the chosen face.
    var spotlightDimming: Double

    /// Radius of the clear region, as a multiple of the (already inflated) marker box. Around 1.3
    /// clears the head; below 1.0 it cuts into the face.
    var spotlightRadiusScale: Double

    /// Width of the falloff, as a fraction of that radius. 0 is a hard-edged hole — a cutout, and
    /// it looks like one. The falloff is what makes it read as light rather than as a mask.
    var spotlightFeather: Double

    // MARK: - Defaults

    /// Chosen to be *defensible starting points*, not answers — finding the answers is what the lab
    /// is for. Two are deliberately conservative: `autoHideDelay` at 2s is long enough to notice
    /// the markers before they go, and `spotlightDimming` at 0.45 is well short of a blackout.
    static let `default` = FaceMarkerTuning(
        autoHideDelay: 2.0,
        restingOpacity: 0.0,
        flashDuration: 0.28,
        minimumTapTarget: 44,
        quietStroke: 1,
        bracketLength: 0.28,
        bracketThickness: 2,
        markerScale: 1.08,
        lockOnScale: 1.12,
        lockOnDuration: 0.22,
        showsIndexLabel: true,
        labelSize: 10,
        unselectedOpacity: 0.35,
        scanlineDuration: 1.6,
        scanlineOpacity: 0.35,
        scanlineHeight: 0.18,
        spotlightDimming: 0.45,
        spotlightRadiusScale: 1.3,
        spotlightFeather: 0.55
    )

    // MARK: - Derived

    /// The marker box for a face, in the same space as the input: Vision's rect inflated by
    /// `markerScale` about its own centre.
    ///
    /// Clamping is deliberately *not* done here. A face at the edge of the frame legitimately has a
    /// marker that runs off it, and clamping would slide the reticle off the face to keep a corner
    /// visible — which looks like a tracking failure.
    func markerRect(for rect: CGRect) -> CGRect {
        let scale = max(0.5, markerScale)
        let dx = rect.width * (scale - 1) / 2
        let dy = rect.height * (scale - 1) / 2
        return rect.insetBy(dx: -dx, dy: -dy)
    }

    /// Bracket arm length in points for a marker of this size on screen, floored so a small face
    /// still shows a corner rather than a dot.
    func bracketArm(forSide side: CGFloat) -> CGFloat {
        max(4, side * CGFloat(max(0.05, min(0.5, bracketLength))))
    }

    // MARK: - Export

    /// A paste-ready Swift block, for when a variant graduates and these stop being live knobs.
    var swiftSnippet: String {
        """
        // Copied from FACE MARKER LAB.
        static let tuned = FaceMarkerTuning(
            autoHideDelay: \(Self.number(autoHideDelay)),
            restingOpacity: \(Self.number(restingOpacity)),
            flashDuration: \(Self.number(flashDuration)),
            minimumTapTarget: \(Self.number(minimumTapTarget)),
            quietStroke: \(Self.number(quietStroke)),
            bracketLength: \(Self.number(bracketLength)),
            bracketThickness: \(Self.number(bracketThickness)),
            markerScale: \(Self.number(markerScale)),
            lockOnScale: \(Self.number(lockOnScale)),
            lockOnDuration: \(Self.number(lockOnDuration)),
            showsIndexLabel: \(showsIndexLabel),
            labelSize: \(Self.number(labelSize)),
            unselectedOpacity: \(Self.number(unselectedOpacity)),
            scanlineDuration: \(Self.number(scanlineDuration)),
            scanlineOpacity: \(Self.number(scanlineOpacity)),
            scanlineHeight: \(Self.number(scanlineHeight)),
            spotlightDimming: \(Self.number(spotlightDimming)),
            spotlightRadiusScale: \(Self.number(spotlightRadiusScale)),
            spotlightFeather: \(Self.number(spotlightFeather))
        )
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

// MARK: - Tolerant decoding

/// Decoding that fills in whatever the stored blob is missing.
///
/// Synthesised `Codable` throws on an absent key, so every knob added to the lab would otherwise
/// discard the tuning already in `UserDefaults` on the next launch. A lab exists *to* grow its
/// fields, so that is the expected path rather than an edge case. *(Learned the expensive way in
/// the gradient-lab session — see `GradientTuning` for the same extension.)*
///
/// In an extension rather than the main declaration, so the memberwise initialiser survives:
/// `FaceMarkerTuning.default` is built with it.
extension FaceMarkerTuning {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = FaceMarkerTuning.default

        func number(_ key: CodingKeys, _ or: Double) -> Double {
            ((try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? or
        }
        func flag(_ key: CodingKeys, _ or: Bool) -> Bool {
            ((try? container.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? or
        }

        self.init(
            autoHideDelay: number(.autoHideDelay, fallback.autoHideDelay),
            restingOpacity: number(.restingOpacity, fallback.restingOpacity),
            flashDuration: number(.flashDuration, fallback.flashDuration),
            minimumTapTarget: number(.minimumTapTarget, fallback.minimumTapTarget),
            quietStroke: number(.quietStroke, fallback.quietStroke),
            bracketLength: number(.bracketLength, fallback.bracketLength),
            bracketThickness: number(.bracketThickness, fallback.bracketThickness),
            markerScale: number(.markerScale, fallback.markerScale),
            lockOnScale: number(.lockOnScale, fallback.lockOnScale),
            lockOnDuration: number(.lockOnDuration, fallback.lockOnDuration),
            showsIndexLabel: flag(.showsIndexLabel, fallback.showsIndexLabel),
            labelSize: number(.labelSize, fallback.labelSize),
            unselectedOpacity: number(.unselectedOpacity, fallback.unselectedOpacity),
            scanlineDuration: number(.scanlineDuration, fallback.scanlineDuration),
            scanlineOpacity: number(.scanlineOpacity, fallback.scanlineOpacity),
            scanlineHeight: number(.scanlineHeight, fallback.scanlineHeight),
            spotlightDimming: number(.spotlightDimming, fallback.spotlightDimming),
            spotlightRadiusScale: number(.spotlightRadiusScale, fallback.spotlightRadiusScale),
            spotlightFeather: number(.spotlightFeather, fallback.spotlightFeather)
        )
    }
}
