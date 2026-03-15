import CoreImage

/// Smoothly transitions from the original image colors to a full
/// color inversion. Progress drives the blend from normal to inverted.
struct InversionEffect: VisualEffect {
    private let strength: CGFloat

    init(intensity: Double = 0.5) {
        self.strength = CGFloat(max(0.1, intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amount = strength * min(1.0, progress * 1.5)
        guard amount > 0.01 else { return image }

        let inverted = image.applyingFilter("CIColorInvert")

        let result = image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: inverted,
            kCIInputTimeKey: amount
        ])

        return result.cropped(to: image.extent)
    }
}
