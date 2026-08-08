import CoreImage

/// Progressively applies a center-bulge fisheye distortion reminiscent of
/// 2000s music video aesthetics. At progress 0 the image is undistorted;
/// at progress 1 the center bulges outward at full intensity.
/// Uses CIBumpDistortion with a positive scale for the convex "bulge" look.
///
/// - `intensity` scales the maximum bulge strength (warp).
/// - `size` controls the radius of the distorted area (0 = tight spot, 1 = nearly full image).
public struct FisheyeEffect: VisualEffect {
    private let maxScale: CGFloat
    private let radiusFraction: CGFloat

    public init(intensity: Double = 0.5, size: Double = 0.5) {
        self.maxScale = max(0.1, 1.4 * CGFloat(intensity))
        self.radiusFraction = 0.1 + 0.4 * CGFloat(max(0, min(1, size)))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let scale = maxScale * (progress * progress)
        guard scale > 0.01 else { return image }

        let c = viewportCenter ?? CGPoint(x: image.extent.midX, y: image.extent.midY)
        let center = CIVector(x: c.x, y: c.y)
        let radius = max(image.extent.width, image.extent.height) * radiusFraction

        // Crop back to the input extent. CIBumpDistortion *grows* the extent past its
        // input, so without this the returned image has a different size and aspect
        // ratio than the source — which letterboxes the editor's canvas (its scroll
        // geometry is configured once from the source image) and changes the frame
        // dimensions in the GIF pipeline.
        return image
            .applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: center,
                kCIInputRadiusKey: radius,
                kCIInputScaleKey: scale
            ])
            .cropped(to: image.extent)
    }
}
