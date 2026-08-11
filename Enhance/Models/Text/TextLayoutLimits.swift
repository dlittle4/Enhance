import CoreGraphics

/// Whether a value is currently under the user's finger or has come to rest.
///
/// The two phases exist because a limit that is correct on release is wrong mid-gesture.
/// Clamping hard while tracking makes the text fight the finger — it stops following, or
/// worse, slides sideways as a rotation grows its bounding box. Tracking therefore
/// rubber-bands and only settling clamps, which is the same bounce idiom `ImageCanvasView`'s
/// scroll view already uses (`bounces`, `bouncesZoom`), so the two feel like one surface.
enum GesturePhase {
    case tracking
    case settled
}

/// Placement, size and rotation limits for a text overlay.
///
/// Pure value maths on normalized quantities — no UIKit, no graphics context, no view state —
/// so the whole of it is directly testable and both the live canvas and the GIF renderer can
/// apply identical limits without sharing anything but this file.
///
/// **Everything here is normalized against the output frame** (`0…1` of its side), never points
/// or pixels. The canvas is 325pt and the export is 600px; a limit expressed in either would be
/// wrong in the other, and the resulting drift is exactly the preview/export mismatch class that
/// LEARNINGS 2026-08-07 and 2026-08-09 both record.
enum TextLayoutLimits {

    // MARK: - Centre

    /// Where a released overlay settles: its centre always ends inside this inset.
    ///
    /// The *centre* is clamped, not the measured bounds. With free rotation the axis-aligned
    /// bounding box grows as the text turns — up to √2× for a wide block at 45° — so clamping
    /// bounds would shove legally placed text sideways while the user is rotating it. A centre
    /// inside the safe rect is the guarantee that actually matters: the middle of the message is
    /// always on frame. Oversized text running off the edge is a legitimate design, not a bug.
    static let centreRestInset: CGFloat = 0.10

    /// Absolute floor, enforced even mid-gesture. The rubber band saturates before this.
    static let centreHardInset: CGFloat = 0.05

    /// How far past `centreRestInset` the band can stretch before saturating.
    static let rubberBandRange: CGFloat = 0.15

    // MARK: - Size

    /// Legibility floor. Silkscreen is a pixel font and stops reading below roughly this.
    static let minFontSize: CGFloat = 0.035

    /// Ceiling before the line-count budget is applied.
    static let maxFontSizeAbsolute: CGFloat = 0.30

    static let lineHeightMultiple: CGFloat = 1.25

    /// Fraction of the frame height a laid-out block may occupy.
    static let verticalBudget: CGFloat = 0.92

    /// Headroom above the cap while pinching, so the gesture does not feel walled.
    /// Applies above the ceiling only — the legibility floor is hard in both phases.
    static let pinchOvershoot: CGFloat = 1.15

    /// Wrap width, in the text's own local space.
    ///
    /// Local rather than output space is the point: wrapping in output space would re-flow the
    /// text as it rotates, so a title would silently gain a line on its way through 45°.
    static let layoutWidth: CGFloat = 0.86

    // MARK: - Rotation

    /// Angular distance within which a free rotation latches onto a detent. 4°.
    static let snapEnter: CGFloat = 0.0698

    /// Angular distance at which a latched detent lets go. 8°.
    ///
    /// Deliberately wider than `snapEnter`. With a single threshold, a finger resting on the
    /// boundary latches and unlatches every frame, and each transition fires a haptic — the
    /// detent machine-guns. The gap between the two is the hysteresis that prevents it.
    static let snapRelease: CGFloat = 0.1396

    /// Detent indices, as multiples of a right angle over the normalized range `(−π, π]`.
    /// `2` is π; `−1` is −π/2. There is no `−2`, because −π normalizes to π.
    static let detentIndices: [Int] = [-1, 0, 1, 2]

    // MARK: - Derived limits

    /// Largest font size at which `lineCount` lines still fit the vertical budget.
    ///
    /// Derived rather than a constant, because the absolute cap is only honest for one or two
    /// lines: three lines at 0.30 would need 1.125 of the frame height.
    static func maxFontSize(lineCount: Int) -> CGFloat {
        min(maxFontSizeAbsolute,
            verticalBudget / (CGFloat(max(1, lineCount)) * lineHeightMultiple))
    }

    // MARK: - Clamping

    /// Standard rubber band: asymptotic, so travel is bounded by `range` however hard the user
    /// pulls, and monotonic, so the text never reverses direction under the finger.
    static func rubberBand(_ overshoot: CGFloat, range: CGFloat) -> CGFloat {
        guard overshoot > 0, range > 0 else { return 0 }
        return (1 - 1 / (overshoot / range + 1)) * range
    }

    /// Clamps a normalized centre. Rubber-bands while tracking, settles inside the rest inset.
    static func clampCentre(_ centre: CGPoint, phase: GesturePhase) -> CGPoint {
        CGPoint(x: clampAxis(centre.x, phase: phase),
                y: clampAxis(centre.y, phase: phase))
    }

    private static func clampAxis(_ value: CGFloat, phase: GesturePhase) -> CGFloat {
        let low = centreRestInset
        let high = 1 - centreRestInset
        if value >= low && value <= high { return value }

        switch phase {
        case .settled:
            return min(high, max(low, value))
        case .tracking:
            let overshoot = value < low ? low - value : value - high
            let banded = rubberBand(overshoot, range: rubberBandRange)
            let pulled = value < low ? low - banded : high + banded
            return min(1 - centreHardInset, max(centreHardInset, pulled))
        }
    }

    /// Clamps a normalized font size against the floor and the line-count budget.
    static func clampFontSize(_ size: CGFloat, lineCount: Int, phase: GesturePhase) -> CGFloat {
        let ceiling = maxFontSize(lineCount: lineCount)
        let allowed = phase == .tracking ? ceiling * pinchOvershoot : ceiling
        return min(allowed, max(minFontSize, size))
    }

    // MARK: - Rotation

    /// Normalizes any angle into `(−π, π]`, so a detent has exactly one representation.
    static func normalizedAngle(_ radians: CGFloat) -> CGFloat {
        let twoPi = 2 * CGFloat.pi
        var angle = radians.truncatingRemainder(dividingBy: twoPi)
        if angle <= -CGFloat.pi { angle += twoPi }
        if angle > CGFloat.pi { angle -= twoPi }
        return angle
    }

    /// Shortest angular distance between two normalized angles, across the ±π seam.
    static func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let raw = abs(normalizedAngle(a) - normalizedAngle(b))
        return raw > CGFloat.pi ? 2 * CGFloat.pi - raw : raw
    }

    static func detentAngle(_ index: Int) -> CGFloat {
        normalizedAngle(CGFloat(index) * CGFloat.pi / 2)
    }

    /// Resolves a raw rotation into a possibly-snapped angle and the detent it latched to.
    ///
    /// Pass the previously latched detent as `current`; the caller fires a haptic only when the
    /// returned detent differs from what it passed in, which makes the detent sequence *be* the
    /// haptic schedule and therefore directly assertable.
    ///
    /// The caller must keep accumulating the **raw** angle and pass that in, not the snapped
    /// value it got back. Feeding the snapped angle in would pin the input at the detent and the
    /// rotation could never escape it.
    static func snapAngle(_ radians: CGFloat, current: Int?) -> (angle: CGFloat, detent: Int?) {
        let angle = normalizedAngle(radians)

        // Hold the current detent across the wider release band before considering any other.
        if let current, detentIndices.contains(current) {
            let held = detentAngle(current)
            if angularDistance(angle, held) <= snapRelease {
                return (held, current)
            }
        }

        for index in detentIndices {
            let candidate = detentAngle(index)
            if angularDistance(angle, candidate) <= snapEnter {
                return (candidate, index)
            }
        }

        return (angle, nil)
    }
}
