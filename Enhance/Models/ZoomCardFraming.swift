import CoreGraphics
import Foundation

/// How each ZOOM browse card frames the photo.
///
/// All three animators travel between the *same* two framings — the whole photo and the
/// user's zoom rect — and differ only in the path they take. So each card shows the
/// framing that type ends on, which is the one still that distinguishes it: ZOOM IN
/// lands tight, ZOOM OUT lands wide, and PULSE sits between the two.
///
/// Deliberately free of SwiftUI so the mapping can be tested without a view, and built
/// from the same log-scale interpolation the real animators use, so a card cannot drift
/// from the framing the GIF actually reaches.
enum ZoomCardFraming {

    /// How far toward the user's zoom the card sits: 0 is the whole photo, 1 is the zoom
    /// rect.
    ///
    /// PULSE genuinely *ends* wide — `sin(π)` returns it to where it started — so its
    /// value here is chosen to be legible rather than literal. A card showing its true
    /// last frame would be identical to ZOOM OUT's, which tells the user nothing.
    static func fraction(for type: AnimatorType) -> Double {
        switch type {
        case .zoomIn:  return 1
        case .zoomOut: return 0
        case .pulse:   return 0.5
        }
    }

    /// Scale and offset to place a `.fill`-scaled photo inside a square card.
    ///
    /// Matches `GIFGenerator.calculateAnimationParameters` and `interpolate`: the scale
    /// moves **logarithmically** (so 1→2 covers the same visual distance as 2→4) while
    /// the centre moves **linearly**, which is what couples the pan to the perceived
    /// zoom rather than letting it slide ahead.
    ///
    /// Apply as `.scaleEffect(scale).offset(offset)` — offset is in the card's unscaled
    /// coordinate space, so it must come second.
    static func transform(
        fraction: Double,
        zoomScale: CGFloat,
        zoomCenter: CGPoint,
        imageSize: CGSize,
        cardSize: CGFloat
    ) -> (scale: CGFloat, offset: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0, cardSize > 0 else {
            return (1, .zero)
        }

        let f = CGFloat(max(0, min(1, fraction)))
        let scale = pow(max(zoomScale, 1), f)

        // The card shows the photo aspect-filled, so one axis overflows and is clipped.
        // The centre has to be resolved against that filled rect, not the card.
        let fill = max(cardSize / imageSize.width, cardSize / imageSize.height)
        let contentWidth = imageSize.width * fill
        let contentHeight = imageSize.height * fill

        let u = 0.5 + f * (zoomCenter.x - 0.5)
        let v = 0.5 + f * (zoomCenter.y - 0.5)

        let pointX = (cardSize - contentWidth) / 2 + u * contentWidth
        let pointY = (cardSize - contentHeight) / 2 + v * contentHeight

        // Translate so the interpolated centre lands in the middle of the card. At
        // fraction 0 the centre is the image centre and this is exactly zero.
        return (
            scale: scale,
            offset: CGSize(
                width: -scale * (pointX - cardSize / 2),
                height: -scale * (pointY - cardSize / 2)
            )
        )
    }
}

/// The framing a zoom travels to: how far in, and where.
///
/// A value type so it can be *snapshotted*. The zoom cards deliberately do not read
/// `currentScale` / `visibleRect` live — those are rewritten on every scroll-delegate
/// callback, so live cards would re-crop continuously under the user's fingers while they
/// are trying to look at the photo.
struct ZoomFraming: Equatable {
    var scale: CGFloat
    var center: CGPoint

    /// Stand-in used until the user picks a zoom. Without it the two endpoint framings
    /// are identical and all three cards show the same untouched photo.
    static let fallback = ZoomFraming(scale: 2.5, center: CGPoint(x: 0.5, y: 0.5))

    /// The normalized rect this framing implies, in the shape the editor's `visibleRect`
    /// carries, so a framing can be handed straight to the generator.
    ///
    /// Only the rect's **centre** reaches the output — `GIFGenerator.calculateAnimationParameters`
    /// reads its midpoint and takes the magnification from `currentScale` — but the size is
    /// derived honestly anyway rather than left at the full frame, so the value still describes
    /// the region it names if anything else ever reads it.
    var rect: CGRect {
        let side = 1 / max(scale, 1)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }
}
