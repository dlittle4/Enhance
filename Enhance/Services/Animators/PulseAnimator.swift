import CoreGraphics

public struct PulseAnimator: Animator {
    public init() {}
    
    public func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters {
        let t = sin(progress * .pi)
        return interpolate(from: context.fullViewParams, to: context.userZoomParams, progress: t)
    }
}
