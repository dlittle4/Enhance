import CoreGraphics

/// Adds circular displacement that spirals inward toward the focal point.
/// The radius shrinks as progress increases, creating a tightening spiral.
/// Scale is unchanged — the spiral is purely positional.
public struct SpiralModifier: MotionModifier {
    private let totalRotations: CGFloat = 2.5

    public init() {}

    public func modifyParameters(
        _ params: GIFGenerator.AnimationParameters,
        for progress: CGFloat,
        in context: GIFGenerator.DrawingContext
    ) -> GIFGenerator.AnimationParameters {
        let easedProgress = easeInOut(progress)
        let radius: CGFloat = 40.0 * (1.0 - easedProgress)
        let angle = progress * totalRotations * 2.0 * .pi

        let offsetX = radius * cos(angle)
        let offsetY = radius * sin(angle)

        return GIFGenerator.AnimationParameters(
            scale: params.scale,
            centerX: params.centerX + offsetX,
            centerY: params.centerY + offsetY
        )
    }
}
