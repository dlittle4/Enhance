import CoreGraphics

/// A motion modifier transforms animation parameters produced by a base `Animator`.
/// Use to layer additional movement (shake, spiral, etc.) on top of any base effect.
public protocol MotionModifier {
    func modifyParameters(
        _ params: GIFGenerator.AnimationParameters,
        for progress: CGFloat,
        in context: GIFGenerator.DrawingContext
    ) -> GIFGenerator.AnimationParameters
}
