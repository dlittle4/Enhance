import CoreImage

/// Desaturates the image and applies a warm sepia-style tint.
/// Progress drives the transition from full color to monotone.
struct MonotoneEffect: VisualEffect {
    private let tintStrength: CGFloat

    init(intensity: Double = 0.5) {
        self.tintStrength = CGFloat(max(0.1, intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let strength = tintStrength * min(1.0, progress * 1.5)
        guard strength > 0.01 else { return image }

        let desaturated = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.0 - strength
        ])

        // Warm sepia tint via CIColorMatrix: boost red slightly, reduce blue
        let tinted = desaturated.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.0 + 0.15 * strength, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1.0 + 0.05 * strength, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1.0 - 0.15 * strength, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0.02 * strength, y: 0, z: 0, w: 0)
        ])

        return tinted.cropped(to: image.extent)
    }
}
