import CoreGraphics

/// Combines a base `Animator` with a `MotionModifier`.
/// Conforms to `Animator` so it plugs directly into `GIFGenerator` with zero changes.
public struct CompositeAnimator: Animator {
    let base: Animator
    let modifier: MotionModifier

    public func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters {
        let baseParams = base.animationParameters(for: progress, in: context)
        return modifier.modifyParameters(baseParams, for: progress, in: context)
    }
}
