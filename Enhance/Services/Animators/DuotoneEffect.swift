import CoreImage

/// Maps shadows to a dark tint and highlights to the selected color,
/// producing a classic duotone look. Progress drives the blend from
/// original to full duotone.
struct DuotoneEffect: VisualEffect {
    private let strength: CGFloat
    private let shadowR: CGFloat
    private let shadowG: CGFloat
    private let shadowB: CGFloat
    private let highlightR: CGFloat
    private let highlightG: CGFloat
    private let highlightB: CGFloat

    init(intensity: Double = 0.5, color: LaserColor = .red) {
        self.strength = CGFloat(max(0.1, intensity))
        let (r, g, b) = color.rgb
        self.highlightR = r
        self.highlightG = g
        self.highlightB = b
        // Dark complementary shadow: invert and darken the highlight
        self.shadowR = (1.0 - r) * 0.15
        self.shadowG = (1.0 - g) * 0.15
        self.shadowB = (1.0 - b) * 0.15
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amount = strength * min(1.0, progress * 1.5)
        guard amount > 0.01 else { return image }

        let grayscale = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0
        ])

        let rRange = highlightR - shadowR
        let gRange = highlightG - shadowG
        let bRange = highlightB - shadowB

        let duotoned = grayscale.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: rRange, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gRange, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: bRange, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: shadowR, y: shadowG, z: shadowB, w: 0)
        ])

        let result = image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: duotoned,
            kCIInputTimeKey: amount
        ])

        return result.cropped(to: image.extent)
    }
}
