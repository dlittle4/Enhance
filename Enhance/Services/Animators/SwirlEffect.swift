import CoreImage

/// Progressively applies a spiral/vortex distortion centered on the viewport.
/// At progress 0 the image is undistorted; at progress 1 the center twists
/// at full rotation. Uses CITwirlDistortion for GPU-accelerated twirl.
///
/// - `intensity` scales the maximum rotation angle.
/// - `size` controls the radius of the twisted area (0 = tight vortex, 1 = most of the frame).
///   Straight parity with `FisheyeEffect`, which wraps the same kind of radius-bounded
///   distortion and has always exposed it.
public struct SwirlEffect: VisualEffect {
    private let maxAngle: CGFloat
    private let radiusFraction: CGFloat

    public init(intensity: Double = 0.5, size: Double = 0.5) {
        self.maxAngle = CGFloat.pi * CGFloat(max(0.1, 2.0 * intensity))
        // Brackets the 0.4 this effect shipped with, so size 0.5 reproduces it exactly.
        self.radiusFraction = 0.15 + 0.5 * CGFloat(max(0, min(1, size)))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let angle = maxAngle * (progress * progress)
        guard abs(angle) > 0.02 else { return image }

        let c = viewportCenter ?? CGPoint(x: image.extent.midX, y: image.extent.midY)
        let center = CIVector(x: c.x, y: c.y)
        let radius = max(image.extent.width, image.extent.height) * radiusFraction

        // Crop back to the input extent — see FisheyeEffect for why a grown extent
        // letterboxes the canvas and changes the GIF's frame dimensions.
        return image
            .applyingFilter("CITwirlDistortion", parameters: [
                kCIInputCenterKey: center,
                kCIInputRadiusKey: radius,
                kCIInputAngleKey: angle
            ])
            .cropped(to: image.extent)
    }
}
