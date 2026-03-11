import CoreImage

/// Progressively overlays horizontal scanlines and slight color bleeding to
/// simulate a CRT / VHS display. At progress 0 the image is clean;
/// at progress 1 the scanlines are fully visible with a subtle green tint.
/// Combines CILineScreen for the stripe pattern with a color tint overlay.
///
/// - `intensity` scales the scanline opacity and tint strength.
public struct ScanlinesEffect: VisualEffect {
    private let maxOpacity: CGFloat

    public init(intensity: Double = 0.5) {
        self.maxOpacity = max(0.1, 0.6 * CGFloat(intensity))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let opacity = maxOpacity * (progress * progress)
        guard opacity > 0.01 else { return image }

        let extent = image.extent
        let lineWidth: CGFloat = 2.0

        guard let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            kCIInputCenterKey: CIVector(x: 0, y: 0),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: opacity),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputWidth": lineWidth,
            "inputSharpness": 1.0
        ])?.outputImage else { return image }

        let croppedStripes = stripes.cropped(to: extent)

        let withLines = croppedStripes.composited(over: image)

        let tintStrength = opacity * 0.3
        let tinted = withLines.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.0 - tintStrength * 0.2, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1.0 + tintStrength * 0.1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1.0 - tintStrength * 0.15, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        return tinted.cropped(to: extent)
    }
}
