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
    /// Whether the route rounds its corners.
    let smoothing: Bool
    /// 0 holds the pinched magnification throughout; 1 ramps from the whole photo up to it over
    /// the journey.
    let scaleRamp: CGFloat

    init(path: ZoomPath, ease: CGFloat = 0.6, dwell: CGFloat = 0.1, smoothing: Bool = true, scaleRamp: CGFloat = 0) {
        self.path = path
        self.ease = max(0, min(1, ease))
        self.dwell = max(0, min(0.3, dwell))
        self.smoothing = smoothing
        self.scaleRamp = max(0, min(1, scaleRamp))
    }

    public func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters {
        guard !path.isEmpty else {
            return interpolate(from: context.fullViewParams, to: context.userZoomParams, progress: easeInOut(progress))
        }
        let clamped = max(0, min(1, progress))
        let t = easeInOut(clamped) * ease + clamped * (1 - ease)
        let stop = path.point(at: t, dwell: dwell, smoothing: smoothing) ?? CGPoint(x: 0.5, y: 0.5)

        // Log-scale ramp, like `interpolate`, so a ramp reads as uniform zoom speed.
        let target = max(1, context.userZoomParams.scale)
        let scale = scaleRamp > 0 ? pow(target, 1 - scaleRamp + scaleRamp * t) : target

        let rect = context.drawRect
        let centre = Self.clampedCenter(stop, scale: scale, drawRect: rect, outputSize: context.outputSize)
        let centerX = rect.origin.x + centre.x * rect.width
        let centerY = rect.origin.y + centre.y * rect.height
        return GIFGenerator.AnimationParameters(scale: scale, centerX: centerX, centerY: centerY)
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
