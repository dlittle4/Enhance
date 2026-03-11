import CoreGraphics

public struct ZoomInAnimator: Animator {
    public init() {}
    
    public func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters {
        interpolate(from: context.fullViewParams, to: context.userZoomParams, progress: easeInOut(progress))
    }
}
