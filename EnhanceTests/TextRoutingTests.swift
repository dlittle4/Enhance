import Testing
import CoreGraphics
@testable import Enhance

/// First-touch gesture arbitration and the gesture-session counter — the two pieces of the text
/// gesture layer that can fail *silently*, extracted as pure value logic so they are tested without
/// a touch harness. See FEATURE-TEXT-EFFECTS.md §12.6 and §12.7.
struct TextRoutingTests {

    // MARK: - Hit region (§12.6)

    private func region(center: CGPoint = CGPoint(x: 160, y: 160),
                        size: CGSize = CGSize(width: 80, height: 40),
                        angle: CGFloat = 0,
                        selected: Bool = false) -> TextHitRegion {
        TextHitRegion(center: center, renderedSize: size, angle: angle, selected: selected)
    }

    @Test func hitRegion_containsPointsInsideTheUprightBox() {
        let r = region()
        #expect(r.contains(CGPoint(x: 160, y: 160)))   // dead centre
        #expect(r.contains(CGPoint(x: 195, y: 175)))   // inside 80×40
        #expect(!r.contains(CGPoint(x: 210, y: 160)))  // past the right edge
    }

    /// A rotated overlay must hit-test against its *rotated* rectangle, not its axis-aligned
    /// bounding box — a corner of the AABB that the tilted glyphs do not cover must miss.
    @Test func hitRegion_honoursRotation() {
        let upright = region(size: CGSize(width: 120, height: 40), angle: 0)
        let turned = region(size: CGSize(width: 120, height: 40), angle: .pi / 2)

        // A point 55pt above centre: inside the 120-wide upright box only after a 90° turn makes
        // the long axis vertical.
        let p = CGPoint(x: 160, y: 160 - 55)
        #expect(!upright.contains(p))
        #expect(turned.contains(p))
    }

    /// Small text still presents at least a 44pt target on each side, so it is never hard to grab.
    @Test func hitRegion_enforcesTheMinimumTouchTarget() {
        let tiny = region(size: CGSize(width: 6, height: 6))
        #expect(tiny.size.width >= TextHitRegion.minimumTouchTarget)
        #expect(tiny.size.height >= TextHitRegion.minimumTouchTarget)
        // 20pt off-centre would miss a 6pt box but lands inside the inflated 44pt one.
        #expect(tiny.contains(CGPoint(x: 160 + 20, y: 160)))
    }

    /// Selection may widen the grab a little, but routing must not *depend* on it — an unselected
    /// overlay is draggable directly, which is what makes selection a visual state, not a mode.
    @Test func hitRegion_doesNotDependOnSelectionForRouting() {
        let unselected = region(size: CGSize(width: 80, height: 40), selected: false)
        let selected = region(size: CGSize(width: 80, height: 40), selected: true)
        let p = CGPoint(x: 195, y: 175)
        #expect(unselected.contains(p))
        #expect(selected.contains(p))
    }

    // MARK: - First-touch routing (§12.6)

    @Test func route_onText_versus_onPhoto() {
        var router = TextTouchRouter()
        #expect(router.route(firstTouchAt: CGPoint(x: 160, y: 160), region: region()) == .text)

        var other = TextTouchRouter()
        #expect(other.route(firstTouchAt: CGPoint(x: 10, y: 10), region: region()) == .photo)
    }

    @Test func route_withNoOverlay_isAlwaysPhoto() {
        var router = TextTouchRouter()
        #expect(router.route(firstTouchAt: CGPoint(x: 160, y: 160), region: nil) == .photo)
    }

    /// The straddling-pinch case, and the one bug in this feature that only reproduces near an
    /// invisible boundary: a sequence that starts on the text stays `.text` even when a later touch
    /// lands outside it, and vice versa.
    @Test func route_isDecidedByTheFirstTouchOnly() {
        var onText = TextTouchRouter()
        #expect(onText.route(firstTouchAt: CGPoint(x: 160, y: 160), region: region()) == .text)
        // Second finger lands off the text — must still route to text.
        #expect(onText.route(firstTouchAt: CGPoint(x: 5, y: 5), region: region()) == .text)

        var onPhoto = TextTouchRouter()
        #expect(onPhoto.route(firstTouchAt: CGPoint(x: 5, y: 5), region: region()) == .photo)
        // Second finger lands on the text — must still route to photo.
        #expect(onPhoto.route(firstTouchAt: CGPoint(x: 160, y: 160), region: region()) == .photo)
    }

    /// The lock releases only when *every* touch lifts. Lifting one of two must not re-arm the
    /// decision, or a second finger could hijack a gesture mid-flight.
    @Test func route_isReleasedOnlyWhenEveryTouchLifts() {
        var router = TextTouchRouter()
        _ = router.route(firstTouchAt: CGPoint(x: 160, y: 160), region: region())
        #expect(router.lockedRoute == .text)

        router.releaseIfAllLifted(activeTouchCount: 1) // one finger still down
        #expect(router.lockedRoute == .text)

        router.releaseIfAllLifted(activeTouchCount: 0) // all lifted
        #expect(router.lockedRoute == nil)

        // A fresh sequence starting on the photo now routes independently.
        #expect(router.route(firstTouchAt: CGPoint(x: 5, y: 5), region: region()) == .photo)
    }

    // MARK: - Gesture session counter (§12.7)

    @Test func session_simultaneousBegins_captureOnce_endsCommitOnce() {
        let session = TextGestureSession()
        var captures = 0
        var commits = 0

        session.begin { captures += 1 } // pinch.began
        session.begin { captures += 1 } // rotate.began
        session.begin { captures += 1 } // pan.began
        #expect(session.isActive)

        session.end { commits += 1 }     // pinch.ended
        session.end { commits += 1 }     // rotate.ended
        #expect(session.isActive)        // pan still down
        session.end { commits += 1 }     // pan.ended

        #expect(captures == 1, "one capture for the whole burst")
        #expect(commits == 1, "one commit, on the final lift")
        #expect(!session.isActive)
    }

    /// Ends may arrive in any order relative to begins; the commit lands on whichever recognizer
    /// lifts last.
    @Test func session_endsInReverseOrder_commitOnFinalLift() {
        let session = TextGestureSession()
        var commits = 0
        session.begin {}
        session.begin {}
        session.end { commits += 1 }
        #expect(commits == 0)
        session.end { commits += 1 }
        #expect(commits == 1)
    }

    @Test func session_abort_commitsOnce_andIsIdempotent() {
        let session = TextGestureSession()
        var commits = 0
        session.begin {}
        session.begin {}

        session.abort { commits += 1 }
        #expect(commits == 1)
        #expect(!session.isActive)

        session.abort { commits += 1 } // second drain does nothing
        #expect(commits == 1)
    }

    /// A stray end with nothing active must not commit or drive the count negative.
    @Test func session_endWithNothingActive_isANoOp() {
        let session = TextGestureSession()
        var commits = 0
        session.end { commits += 1 }
        #expect(commits == 0)
        #expect(session.activeCount == 0)
    }
}
