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
}
