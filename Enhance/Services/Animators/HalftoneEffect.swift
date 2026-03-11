import CoreImage

/// Progressively applies a classic newspaper-style CMYK halftone dot pattern.
/// At progress 0 the image is normal; at progress 1 the dots are large and clearly visible.
/// Uses CICMYKHalftone for the authentic four-color printing look.
/// Intensity scales the maximum dot size.
public struct HalftoneEffect: VisualEffect {
    private let minWidth: CGFloat = 2.0
    private let maxWidth: CGFloat

    public init(intensity: Double = 0.5) {
        self.maxWidth = max(4.0, 24.0 * CGFloat(intensity))
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
            kCIInputSharpnessKey: 0.7
        ])
    }
}
