import CoreImage

/// Applies directional motion blur that increases with progress,
/// creating a sense of speed or movement.
struct MotionBlurEffect: VisualEffect {
    private let maxRadius: CGFloat

    init(intensity: Double = 0.5) {
        self.maxRadius = CGFloat(max(2.0, 30.0 * intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let t = min(1.0, progress * 1.2)
        let radius = maxRadius * t * t
        guard radius > 0.5 else { return image }

        // Diagonal angle (45 degrees) for a dynamic feel
        let angle: CGFloat = .pi / 4

        return image.applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputAngleKey: angle
        ]).cropped(to: image.extent)
    }
}
