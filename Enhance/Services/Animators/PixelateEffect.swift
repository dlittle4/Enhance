import CoreImage

/// Starts fully pixelated and progressively resolves to a sharp image.
/// At progress 0 the pixels are large and blocky; at progress 1 the image
/// is crisp — a "reveal" effect that pairs naturally with zoom animations.
/// Uses CIPixellate for efficient GPU-accelerated pixelation.
///
/// - `intensity` scales the maximum pixel block size at the start.
/// - `shape` picks the cell shape. `CIHexagonalPixellate` takes the same centre and scale
///   as `CIPixellate`, so the second shape costs a filter name.
public struct PixelateEffect: VisualEffect {
    private let maxScale: CGFloat
    private let shape: PixelShape

    public init(intensity: Double = 0.5, shape: PixelShape = .square) {
        self.maxScale = max(4.0, 40.0 * CGFloat(intensity))
        self.shape = shape
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

        // Crop back to the input extent. Both pixellate filters grow the extent by roughly
        // half a cell on each side, so an uncropped result is larger than its input — which
        // letterboxes the editor canvas and changes the GIF's frame dimensions.
        return image
            .applyingFilter(shape.filterName, parameters: [
                kCIInputCenterKey: center,
                kCIInputScaleKey: scale
            ])
            .cropped(to: image.extent)
    }
}
