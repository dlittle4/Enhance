import Testing
import CoreGraphics
@testable import Enhance

/// Placement, size and rotation limits. Pure value maths, so these run instantly and are the
/// first thing to go green — if anything here fails the rest is not worth debugging yet.
struct TextGeometryTests {

    // MARK: - Centre

    @Test func settledCentre_isAlwaysInsideTheRestInset() {
        let inset = TextLayoutLimits.centreRestInset
        for x in stride(from: -1.0 as CGFloat, through: 2.0, by: 0.13) {
            for y in stride(from: -1.0 as CGFloat, through: 2.0, by: 0.29) {
                let c = TextLayoutLimits.clampCentre(CGPoint(x: x, y: y), phase: .settled)
                #expect(c.x >= inset - 1e-9 && c.x <= 1 - inset + 1e-9)
                #expect(c.y >= inset - 1e-9 && c.y <= 1 - inset + 1e-9)
            }
        }
    }

    @Test func centreInsideTheRestInset_isUntouchedInBothPhases() {
        let point = CGPoint(x: 0.42, y: 0.61)
        #expect(TextLayoutLimits.clampCentre(point, phase: .settled) == point)
        #expect(TextLayoutLimits.clampCentre(point, phase: .tracking) == point)
    }

    /// The band must never let go — a centre outside the hard inset would put the middle of the
    /// message off frame, which is the one guarantee clamping the centre exists to give.
    @Test func trackingCentre_rubberBands_monotonicallyAndStaysInsideTheHardInset() {
        let hard = TextLayoutLimits.centreHardInset
        var previous = CGFloat.greatestFiniteMagnitude

        for step in 0...200 {
            let raw = -CGFloat(step) * 0.02
            let clamped = TextLayoutLimits.clampCentre(CGPoint(x: raw, y: 0.5),
                                                       phase: .tracking).x
            #expect(clamped >= hard - 1e-9, "rubber band escaped the hard inset")
            #expect(clamped <= previous + 1e-9, "band reversed direction under the finger")
            previous = clamped
        }
    }

    @Test func rubberBand_isBoundedByItsRange() {
        let range = TextLayoutLimits.rubberBandRange
        for overshoot in stride(from: 0.0 as CGFloat, through: 50.0, by: 0.5) {
            let banded = TextLayoutLimits.rubberBand(overshoot, range: range)
            #expect(banded >= 0 && banded < range + 1e-9)
        }
    }

    // MARK: - Size

    /// Three lines at the absolute cap would need 1.125 of the frame, which is why the ceiling is
    /// derived from the line count rather than being a constant.
    @Test func maxFontSize_keepsLinesInsideTheVerticalBudget() {
        for lines in 1...5 {
            let size = TextLayoutLimits.maxFontSize(lineCount: lines)
            let occupied = size * CGFloat(lines) * TextLayoutLimits.lineHeightMultiple
            #expect(occupied <= TextLayoutLimits.verticalBudget + 1e-9)
            #expect(size <= TextLayoutLimits.maxFontSizeAbsolute + 1e-9)
        }
    }

    @Test func clampFontSize_honoursTheFloorInBothPhases() {
        for phase in [GesturePhase.tracking, .settled] {
            let clamped = TextLayoutLimits.clampFontSize(0.0001, lineCount: 1, phase: phase)
            #expect(clamped == TextLayoutLimits.minFontSize)
        }
    }

    /// Tracking gets headroom above the cap so the pinch does not feel walled; settling does not.
    @Test func clampFontSize_allowsOvershootOnlyWhileTracking() {
        let ceiling = TextLayoutLimits.maxFontSize(lineCount: 1)
        let huge: CGFloat = 5
        let tracking = TextLayoutLimits.clampFontSize(huge, lineCount: 1, phase: .tracking)
        let settled = TextLayoutLimits.clampFontSize(huge, lineCount: 1, phase: .settled)

        #expect(settled == ceiling)
        #expect(tracking > ceiling)
        #expect(tracking == ceiling * TextLayoutLimits.pinchOvershoot)
    }

    // MARK: - Rotation

    @Test func normalizedAngle_mapsIntoTheHalfOpenRange() {
        for step in -20...20 {
            let raw = CGFloat(step) * 0.7
            let normalized = TextLayoutLimits.normalizedAngle(raw)
            #expect(normalized > -CGFloat.pi - 1e-9)
            #expect(normalized <= CGFloat.pi + 1e-9)
        }
        // −π has a single representation, at the closed end.
        #expect(abs(TextLayoutLimits.normalizedAngle(-CGFloat.pi) - CGFloat.pi) < 1e-9)
    }

    @Test func snapAngle_latchesOntoEveryRightAngle() {
        for index in TextLayoutLimits.detentIndices {
            let exact = TextLayoutLimits.detentAngle(index)
            let result = TextLayoutLimits.snapAngle(exact + 0.01, current: nil)
            #expect(result.detent == index)
            #expect(abs(result.angle - exact) < 1e-9)
        }
    }

    @Test func snapAngle_wellAwayFromADetent_doesNotSnap() {
        let free = CGFloat.pi / 4
        let result = TextLayoutLimits.snapAngle(free, current: nil)
        #expect(result.detent == nil)
        #expect(abs(result.angle - free) < 1e-9)
    }

    /// Hysteresis is the whole point of having two thresholds: the caller fires a haptic whenever
    /// the returned detent changes, so a single threshold would machine-gun on the boundary.
    /// Asserting that the latch point and the release point *differ* is asserting exactly that.
    @Test func snapAngle_latchesLaterThanItReleases() throws {
        var latchAngle: CGFloat?
        var releaseAngle: CGFloat?

        // Approaching from outside: where does it first latch?
        for step in stride(from: 0.30 as CGFloat, through: 0.0, by: -0.001) {
            if TextLayoutLimits.snapAngle(step, current: nil).detent != nil {
                latchAngle = step
                break
            }
        }
        // Already latched, moving away: where does it let go?
        for step in stride(from: 0.0 as CGFloat, through: 0.30, by: 0.001) {
            if TextLayoutLimits.snapAngle(step, current: 0).detent == nil {
                releaseAngle = step
                break
            }
        }

        let latch = try #require(latchAngle)
        let release = try #require(releaseAngle)
        #expect(release > latch, "release threshold must be wider than the latch threshold")
        #expect(abs(latch - TextLayoutLimits.snapEnter) < 0.005)
        #expect(abs(release - TextLayoutLimits.snapRelease) < 0.005)
    }

    /// A latched detent must not trap the rotation: the caller keeps feeding the raw angle, and
    /// pushing past the release band has to escape cleanly.
    @Test func snapAngle_escapesALatchedDetent() {
        let escaped = TextLayoutLimits.snapAngle(TextLayoutLimits.snapRelease + 0.02, current: 0)
        #expect(escaped.detent == nil)
    }
}
