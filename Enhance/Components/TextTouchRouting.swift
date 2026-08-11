import CoreGraphics
import Foundation

/// First-touch gesture arbitration for the text overlay, extracted from the view as pure value
/// logic so it is testable without a touch harness — the one bug in this feature that would only
/// reproduce near an invisible boundary (a two-finger pinch straddling the text edge) lives here.
/// See FEATURE-TEXT-EFFECTS.md §8.3 and §12.6.

/// Where a touch sequence is routed.
enum TextTouchRoute: Equatable {
    /// Drives the text overlay (move / scale / rotate).
    case text
    /// Drives the photo (pan / zoom / double-tap-zoom), exactly as under every other category.
    case photo
}

/// The text's touch target: a rotated rectangle in canvas-point space.
///
/// Routing tests the *rotated* rectangle, not its axis-aligned bounding box, so a 30°-tilted title
/// hit-tests against its real footprint. The box is inflated to a minimum on each side so small
/// text is never hard to grab, and that inflation does not depend on selection — an unselected
/// overlay is draggable directly, which is what makes selection a visual state rather than a mode.
struct TextHitRegion: Equatable {
    /// Centre of the text in canvas points.
    var center: CGPoint
    /// Unrotated box size in canvas points, already inflated to the minimum touch target.
    var size: CGSize
    /// Resting orientation in radians.
    var angle: CGFloat

    /// The smallest side a touch target may present, in points. Apple's minimum is 44.
    static let minimumTouchTarget: CGFloat = 44

    /// Builds a region from the overlay's raw rendered box, inflating each side to the 44pt floor.
    /// `selected` widens it slightly for a more forgiving grab once the outline is showing, but it
    /// never changes whether the overlay is routable — routing does not depend on selection.
    init(center: CGPoint, renderedSize: CGSize, angle: CGFloat, selected: Bool = false) {
        self.center = center
        self.angle = angle
        let pad: CGFloat = selected ? 8 : 0
        self.size = CGSize(
            width: max(renderedSize.width + pad * 2, Self.minimumTouchTarget),
            height: max(renderedSize.height + pad * 2, Self.minimumTouchTarget)
        )
    }

    /// Whether a canvas-space point falls inside the rotated rectangle. Inverse-rotates the point
    /// about the centre and tests it against the axis-aligned half-extents.
    func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let c = cos(-angle)
        let s = sin(-angle)
        let localX = dx * c - dy * s
        let localY = dx * s + dy * c
        return abs(localX) <= size.width / 2 && abs(localY) <= size.height / 2
    }
}

/// Decides and *holds* the route for a whole touch sequence.
///
/// The decision is made once, on the first touch, and held until every touch lifts. Holding it is
/// the whole point: without it UIKit hit-tests each touch independently, so a two-finger pinch with
/// one finger on the text and one off it would split — neither the text nor the photo would ever
/// see two touches, and the pinch would silently do nothing. Locking on first touch makes the
/// straddling case follow the finger the gesture *started* under.
struct TextTouchRouter {
    private(set) var lockedRoute: TextTouchRoute?

    /// Routes a touch. The first touch of a sequence decides; every later touch inherits that
    /// decision until the lock releases, so a second finger landing anywhere joins the same route.
    mutating func route(firstTouchAt point: CGPoint, region: TextHitRegion?) -> TextTouchRoute {
        if let lockedRoute { return lockedRoute }
        let decided: TextTouchRoute = (region?.contains(point) ?? false) ? .text : .photo
        lockedRoute = decided
        return decided
    }

    /// Releases the lock only when no touch remains down. Called with the number of touches still
    /// in `.began/.moved/.stationary`; lifting one of two must not re-arm the decision.
    mutating func releaseIfAllLifted(activeTouchCount: Int) {
        if activeTouchCount == 0 { lockedRoute = nil }
    }
}
