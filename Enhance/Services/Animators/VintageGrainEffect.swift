import CoreImage
import UIKit

/// Applies a vintage film look: slight warm color shift, reduced
/// saturation, and animated noise grain overlay.
struct VintageGrainEffect: VisualEffect {
    private let grainStrength: CGFloat
    private let colorShift: CGFloat

    init(intensity: Double = 0.5) {
        self.grainStrength = CGFloat(max(0.05, 0.25 * intensity))
        self.colorShift = CGFloat(max(0.05, intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let t = min(1.0, progress * 1.3)
        guard t > 0.01 else { return image }

        let extent = image.extent

        // Warm vintage color grade: slight desaturation + warm tint
        let graded = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.0 - 0.35 * colorShift * t,
            kCIInputContrastKey: 1.0 + 0.1 * colorShift * t
        ]).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.0 + 0.08 * colorShift * t, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1.0 + 0.03 * colorShift * t, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1.0 - 0.12 * colorShift * t, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        // Generate grain noise using CIRandomGenerator + frame-based seed
        let noise = CIImage(color: CIColor.white)
            .cropped(to: extent)
            .applyingFilter("CIRandomGenerator")
            .cropped(to: extent)

        // Shift noise each frame for animated grain
        let offsetX = CGFloat((frameIndex * 137) % 256)
        let offsetY = CGFloat((frameIndex * 251) % 256)
        let shiftedNoise = noise.transformed(
            by: CGAffineTransform(translationX: offsetX, y: offsetY)
        ).cropped(to: extent)

        // Convert noise to grayscale and set alpha for blending
        let grainOverlay = shiftedNoise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0
        ]).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: grainStrength * t, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        let result = grainOverlay.composited(over: graded).cropped(to: extent)
        return result
    }
}
