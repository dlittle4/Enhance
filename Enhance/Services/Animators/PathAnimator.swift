import CoreGraphics

/// PATH — the camera travels a route the user drew, Ken Burns style.
///
/// The other zooms move between two framings; this one moves the *centre* through the stops of
/// a `ZoomPath` at the pinched magnification, so the framing the user set is how tight the shot
/// is and the path is where it goes. With no stops it degrades to ZOOM IN, so a PATH card with
/// nothing drawn still produces a GIF rather than a still.
public struct PathAnimator: Animator {
    let path: ZoomPath
    /// 0 is constant speed; 1 eases the whole journey in and out.
    let ease: CGFloat
    /// Fraction of the duration parked at each interior stop.
    let dwell: CGFloat
    /// How much the route rounds its corners: 0 straight legs, 1 fully curved (the CURVE slider).
    let curve: CGFloat
    /// Fraction of the journey spent zooming from the whole photo in to the first stop, before
    /// the route begins — so the zoom-in is finished by the first stop rather than smeared over
    /// the whole path *(user's call, 2026-09-03)*. 0 starts at the pinched magnification.
    let leadIn: CGFloat

    init(path: ZoomPath, ease: CGFloat = 0.6, dwell: CGFloat = 0.1, smoothing: Bool = true, leadIn: CGFloat = 0) {
        self.init(path: path, ease: ease, dwell: dwell, curve: smoothing ? 1 : 0, leadIn: leadIn)
    }

    init(path: ZoomPath, ease: CGFloat, dwell: CGFloat, curve: CGFloat, leadIn: CGFloat) {
        self.path = path
        self.ease = max(0, min(1, ease))
        // Up to 0.9 of the journey may be parked in total; `ZoomPath.point` caps the sum.
        self.dwell = max(0, min(0.9, dwell))
        self.curve = max(0, min(1, curve))
        self.leadIn = max(0, min(0.9, leadIn))
    }

    public func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters {
        guard !path.isEmpty else {
            return interpolate(from: context.fullViewParams, to: context.userZoomParams, progress: easeInOut(progress))
        }
        let clamped = max(0, min(1, progress))
        let target = max(1, context.userZoomParams.scale)
        let rect = context.drawRect

        func params(at stop: CGPoint, scale: CGFloat) -> GIFGenerator.AnimationParameters {
            let centre = Self.clampedCenter(stop, scale: scale, drawRect: rect, outputSize: context.outputSize)
            return GIFGenerator.AnimationParameters(
                scale: scale,
                centerX: rect.origin.x + centre.x * rect.width,
                centerY: rect.origin.y + centre.y * rect.height
            )
        }

        // The lead-in: the whole photo zooming in to the first stop — ZOOM IN's own move —
        // done before the route starts. `interpolate` runs the scale in log space, so it reads
        // as uniform zoom speed.
        if leadIn > 0, clamped < leadIn, let first = path.stops.first {
            let u = easeInOut(clamped / leadIn)
            return interpolate(from: context.fullViewParams, to: params(at: first, scale: target), progress: u)
        }
        let travelled = leadIn > 0 ? (clamped - leadIn) / (1 - leadIn) : clamped
        let t = easeInOut(travelled) * ease + travelled * (1 - ease)
        let stop = path.point(at: t, dwell: dwell, curve: curve) ?? CGPoint(x: 0.5, y: 0.5)
        return params(at: stop, scale: target)
    }

    /// Keeps the frame inside the photo. A stop near an edge is where the *finger* went, but a
    /// viewport centred there at 3× would show the void past the picture — the pinch can never
    /// reach that state, so the route should not either. Each axis is clamped to the half-width
    /// of the viewport in the photo's normalized units; an axis the viewport already covers
    /// entirely centres.
    static func clampedCenter(_ stop: CGPoint, scale: CGFloat, drawRect: CGRect, outputSize: CGSize) -> CGPoint {
        guard drawRect.width > 0, drawRect.height > 0, scale > 0 else { return stop }
        let halfX = (outputSize.width / 2) / (scale * drawRect.width)
        let halfY = (outputSize.height / 2) / (scale * drawRect.height)
        let x = halfX >= 0.5 ? 0.5 : max(halfX, min(1 - halfX, stop.x))
        let y = halfY >= 0.5 ? 0.5 : max(halfY, min(1 - halfY, stop.y))
        return CGPoint(x: x, y: y)
    }
}
