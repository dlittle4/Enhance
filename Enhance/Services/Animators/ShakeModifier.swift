import CoreGraphics

/// Adds rapid jittery displacement to centerX/centerY.
/// Uses layered sine waves at incommensurate frequencies for organic, deterministic motion.
/// Amplitude decays with progress so the animation "settles" onto the focal point.
public struct ShakeModifier: MotionModifier {
    public init() {}

    public func modifyParameters(
        _ params: GIFGenerator.AnimationParameters,
        for progress: CGFloat,
        in context: GIFGenerator.DrawingContext
    ) -> GIFGenerator.AnimationParameters {
        let decay = 1.0 - easeInOut(progress)

        let amplitude: CGFloat = 25.0 * decay

        let jitterX = amplitude * (
            sin(progress * 23.0 * .pi) +
            sin(progress * 37.0 * .pi) * 0.6 +
            sin(progress * 53.0 * .pi) * 0.3
        )

        let jitterY = amplitude * (
            sin(progress * 19.0 * .pi + 1.3) +
            sin(progress * 41.0 * .pi + 2.7) * 0.6 +
            sin(progress * 59.0 * .pi + 0.8) * 0.3
        )

        return GIFGenerator.AnimationParameters(
            scale: params.scale,
            centerX: params.centerX + jitterX,
            centerY: params.centerY + jitterY
        )
    }
}
