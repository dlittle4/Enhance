import CoreImage

/// Progressively desaturates the image from full color to black-and-white
/// as the animation progresses. At progress 0 the image is untouched;
/// at progress 1 it's fully monochrome. Intensity controls the maximum desaturation.
public struct FadeToBWEffect: VisualEffect {
    private let intensity: CGFloat

    public init(intensity: Double = 0.5) {
        self.intensity = CGFloat(intensity)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let strength = intensity * 2.0
        let saturation = max(0.0, 1.0 - progress * strength)

        return image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation
        ])
    }
}
