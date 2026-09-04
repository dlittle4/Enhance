import CoreGraphics

/// Adds rapid jittery displacement to centerX/centerY.
/// Uses layered sine waves at incommensurate frequencies for organic, deterministic motion.
/// Amplitude decays with progress so the animation "settles" onto the focal point.
public struct ShakeModifier: MotionModifier {
    public init() {}

    static let realGain: CGFloat = 0.65

    /// The measured camera speed at `progress`, or 0 for a still. Pure, for tests.
    static func realShake(at progress: CGFloat, in context: GIFGenerator.DrawingContext) -> CGFloat {
        let velocities = context.cameraVelocities
        guard !velocities.isEmpty else { return 0 }
        let index = Int((max(0, min(1, progress)) * CGFloat(velocities.count - 1)).rounded())
        return velocities[index].motionMagnitude
    }

    public func modifyParameters(
        _ params: GIFGenerator.AnimationParameters,
        for progress: CGFloat,
        in context: GIFGenerator.DrawingContext
    ) -> GIFGenerator.AnimationParameters {
        let decay = 1.0 - easeInOut(progress)

        // On a burst, the real camera shake adds to the synthetic one: still footage shakes
        // as it always did, a shaky burst shakes more, in proportion to what the camera did
        // (FEATURE-MOTION-EFFECTS.md §3). `realGain` turns normalized units per frame into
        // output pixels — 0.02 of the frame becomes ~8px.
        let real = Self.realShake(at: progress, in: context)
        let amplitude: CGFloat = 25.0 * decay + Self.realGain * real * context.outputSize.width

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
