import CoreImage

/// Applies a soft glow / light-bleed from bright areas of the image.
/// Progress drives the bloom radius and intensity upward.
struct BloomEffect: VisualEffect {
    private let maxRadius: CGFloat
    private let maxIntensity: CGFloat

    init(intensity: Double = 0.5) {
        self.maxRadius = CGFloat(max(2.0, 25.0 * intensity))
        self.maxIntensity = CGFloat(max(0.2, 1.2 * intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let t = min(1.0, progress * 1.3)
        let radius = maxRadius * t * t
        let bloomIntensity = maxIntensity * t
        guard radius > 0.5 else { return image }

        return image.applyingFilter("CIBloom", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputIntensityKey: bloomIntensity
        ]).cropped(to: image.extent)
    }
}
