import CoreImage

/// Starts fully pixelated and progressively resolves to a sharp image.
/// At progress 0 the pixels are large and blocky; at progress 1 the image
/// is crisp — a "reveal" effect that pairs naturally with zoom animations.
/// Uses CIPixellate for efficient GPU-accelerated pixelation.
///
/// - `intensity` scales the maximum pixel block size at the start.
public struct PixelateEffect: VisualEffect {
    private let maxScale: CGFloat

    public init(intensity: Double = 0.5) {
        self.maxScale = max(4.0, 40.0 * CGFloat(intensity))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let remaining = 1.0 - progress
        let scale = 1.0 + (maxScale - 1.0) * (remaining * remaining)
        guard scale > 1.5 else { return image }

        let c = viewportCenter ?? CGPoint(x: image.extent.midX, y: image.extent.midY)
        let center = CIVector(x: c.x, y: c.y)

        // Crop back to the input extent. CIPixellate grows the extent by roughly half a
        // cell on each side, so an uncropped result is larger than its input — which
        // letterboxes the editor canvas and changes the GIF's frame dimensions.
        return image
            .applyingFilter("CIPixellate", parameters: [
                kCIInputCenterKey: center,
                kCIInputScaleKey: scale
            ])
            .cropped(to: image.extent)
    }
}
