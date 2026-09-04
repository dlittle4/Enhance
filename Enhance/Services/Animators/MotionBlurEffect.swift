import CoreImage

/// Applies directional motion blur that increases with progress,
/// creating a sense of speed or movement.
///
/// - `intensity` scales the maximum blur radius.
/// - `angle` sets the blur direction. A directional blur whose direction cannot be set is
///   half a feature — horizontal and diagonal smears read as completely different effects.
struct MotionBlurEffect: VisualEffect {
    private let maxRadius: CGFloat
    private let angle: CGFloat

    init(intensity: Double = 0.5, angle: Double = 0.5) {
        self.maxRadius = CGFloat(max(2.0, 30.0 * intensity))
        // Centred on the 45° this effect shipped with, so the default look is unchanged,
        // and spanning a full half-turn either side of it. Directions repeat every π for a
        // symmetric blur, so 0 and 1 land on the same angle and the whole range is covered
        // exactly once.
        self.angle = .pi / 4 + (CGFloat(max(0, min(1, angle))) - 0.5) * .pi
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let t = min(1.0, progress * 1.2)
        let radius = maxRadius * t * t
        guard radius > 0.5 else { return image }

        return image.applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputAngleKey: angle
        ]).cropped(to: image.extent)
    }

    /// Speed, in normalized units per frame, at which the blur reaches its full radius.
    static let fullBlurSpeed: CGFloat = 0.06

    /// On a burst the blur follows what actually moved: the angle comes from the measured
    /// velocity and the radius from its speed, with no progress ramp — a frame where nothing
    /// moved stays sharp (FEATURE-MOTION-EFFECTS.md §3). The ANGLE slider is the fallback for
    /// a frame with no measurable motion, and the whole of it for a still.
    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage {
        guard let motion, motion.velocity.motionMagnitude >= SpeedLinesEffect.minimumSpeed else {
            return apply(to: image, progress: progress, frameIndex: frameIndex)
        }
        let speed = motion.velocity.motionMagnitude
        let radius = maxRadius * min(1, speed / Self.fullBlurSpeed)
        guard radius > 0.5 else { return image }
        return image.applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputAngleKey: motion.velocity.motionAngle
        ]).cropped(to: image.extent)
    }
}
