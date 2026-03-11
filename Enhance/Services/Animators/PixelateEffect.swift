import CoreImage

/// Progressively pixelates the image into a chunky mosaic. At progress 0 the
/// image is sharp; at progress 1 the pixels are large and blocky.
/// Uses CIPixellate for efficient GPU-accelerated pixelation.
///
/// - `intensity` scales the maximum pixel block size.
public struct PixelateEffect: VisualEffect {
    private let maxScale: CGFloat

    public init(intensity: Double = 0.5) {
        self.maxScale = max(4.0, 40.0 * CGFloat(intensity))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let scale = 1.0 + (maxScale - 1.0) * (progress * progress)
        guard scale > 1.5 else { return image }

        let c = viewportCenter ?? CGPoint(x: image.extent.midX, y: image.extent.midY)
        let center = CIVector(x: c.x, y: c.y)

        return image.applyingFilter("CIPixellate", parameters: [
            kCIInputCenterKey: center,
            kCIInputScaleKey: scale
        ])
    }
}
