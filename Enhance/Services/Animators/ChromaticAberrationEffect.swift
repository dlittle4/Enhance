import CoreImage

/// Progressively splits the red and blue color channels outward from center,
/// creating a prismatic fringing effect that intensifies with animation progress.
/// At progress 0 the image is normal; at progress 1 the shift is at full strength.
/// Intensity scales the maximum pixel shift.
///
/// - `angle` sets the direction the channels separate along. Horizontal and diagonal
///   fringing read as visually distinct effects; the direction was previously fixed.
public struct ChromaticAberrationEffect: VisualEffect {
    private let maxShift: CGFloat
    private let angle: CGFloat

    public init(intensity: Double = 0.5, angle: Double = 0.5) {
        self.maxShift = max(2.0, 20.0 * CGFloat(intensity))
        // Centred on the down-right diagonal this effect shipped with, spanning a half
        // turn. Red and blue move in opposite directions, so a half turn covers every
        // distinct configuration once.
        self.angle = -.pi / 4 + (CGFloat(max(0, min(1, angle))) - 0.5) * .pi
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let shift = maxShift * (progress * progress * progress)
        guard shift > 0.1 else { return image }

        // The shipped offsets were (+shift, -shift) — a diagonal whose magnitude is
        // shift*sqrt(2), not shift. Preserving that magnitude is what keeps the default
        // identical to what shipped rather than 30% weaker.
        let reach = shift * CGFloat(2.0).squareRoot()
        let dx = reach * cos(angle)
        let dy = reach * sin(angle)

        let redOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let shiftedRed = redOnly.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        let blueOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let shiftedBlue = blueOnly.transformed(by: CGAffineTransform(translationX: -dx, y: -dy))

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
