import CoreGraphics

/// Pass-through modifier that returns parameters unchanged.
/// This is the default "no modification" option.
public struct StraightModifier: MotionModifier {
    public init() {}

    public func modifyParameters(
        _ params: GIFGenerator.AnimationParameters,
        for progress: CGFloat,
        in context: GIFGenerator.DrawingContext
    ) -> GIFGenerator.AnimationParameters {
        params
    }
}
