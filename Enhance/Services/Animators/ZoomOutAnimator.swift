import CoreGraphics

public struct ZoomOutAnimator: Animator {
    public init() {}
    
    public func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters {
        interpolate(from: context.userZoomParams, to: context.fullViewParams, progress: easeInOut(progress))
    }
}
