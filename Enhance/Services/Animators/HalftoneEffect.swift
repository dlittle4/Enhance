import CoreImage

/// Progressively applies a classic newspaper-style CMYK halftone dot pattern.
/// At progress 0 the image is normal; at progress 1 the dots are large and clearly visible.
/// Uses CICMYKHalftone for the authentic four-color printing look.
/// Intensity scales the maximum dot size.
///
/// - `sharpness` is dot hardness: low reads as soft ink bleed, high as crisp print.
/// - `angle` rotates the screen. `CICMYKHalftone` offsets its four channels internally,
///   so this turns the whole rosette rather than breaking the moire-avoiding spacing.
///
/// Both were supported by the filter all along and simply never set — `inputAngle` was
/// left at its default and sharpness hardcoded.
public struct HalftoneEffect: VisualEffect {
    private let minWidth: CGFloat = 2.0
    private let maxWidth: CGFloat
    private let sharpness: CGFloat
    private let angle: CGFloat

    public init(intensity: Double = 0.5, sharpness: Double = 0.5, angle: Double = 0.5) {
        self.maxWidth = max(4.0, 24.0 * CGFloat(intensity))
        // 0.5 reproduces the 0.7 this effect shipped with.
        self.sharpness = 0.4 + 0.6 * CGFloat(max(0, min(1, sharpness)))
        // 0.5 reproduces the filter's own default of 0, spanning a quarter turn either
        // way — beyond that a dot screen repeats.
        self.angle = (CGFloat(max(0, min(1, angle))) - 0.5) * .pi / 2
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let width = minWidth + (maxWidth - minWidth) * (progress * progress)
        guard width > minWidth + 0.1 else { return image }

        let c = viewportCenter ?? CGPoint(x: image.extent.midX, y: image.extent.midY)
        let center = CIVector(x: c.x, y: c.y)

        return image.applyingFilter("CICMYKHalftone", parameters: [
            kCIInputCenterKey: center,
            kCIInputWidthKey: width,
            kCIInputSharpnessKey: sharpness,
            kCIInputAngleKey: angle
        ])
    }
}
