import CoreImage

/// Progressively splits the red and blue color channels outward from center,
/// creating a prismatic fringing effect that intensifies with animation progress.
/// At progress 0 the image is normal; at progress 1 the shift is at full strength.
/// Intensity scales the maximum pixel shift.
public struct ChromaticAberrationEffect: VisualEffect {
    private let maxShift: CGFloat

    public init(intensity: Double = 0.5) {
        self.maxShift = max(2.0, 20.0 * CGFloat(intensity))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let shift = maxShift * (progress * progress * progress)
        guard shift > 0.1 else { return image }

        let redOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let shiftedRed = redOnly.transformed(by: CGAffineTransform(translationX: shift, y: -shift))

        let blueOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let shiftedBlue = blueOnly.transformed(by: CGAffineTransform(translationX: -shift, y: shift))

        let greenOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        let composite = shiftedRed
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: greenOnly])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: shiftedBlue])
            .cropped(to: image.extent)

        return composite
    }
}
