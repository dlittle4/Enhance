import CoreImage

/// Progressively applies a water-like ripple/wave distortion that undulates
/// across the image. At progress 0 the image is still; at progress 1 the
/// waves are at full amplitude. Uses horizontal sine-wave displacement of
/// image rows via CIAffineTransform strips, composited back together.
///
/// - `intensity` scales the maximum wave amplitude and frequency.
public struct RippleEffect: VisualEffect {
    private let maxAmplitude: CGFloat
    private let frequency: CGFloat

    public init(intensity: Double = 0.5) {
        self.maxAmplitude = max(2.0, 20.0 * CGFloat(intensity))
        self.frequency = 3.0 + 5.0 * CGFloat(intensity)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amplitude = maxAmplitude * (progress * progress)
        guard amplitude > 0.5 else { return image }

        let extent = image.extent
        let stripCount = 40
        let stripHeight = extent.height / CGFloat(stripCount)
        var result = CIImage.empty()

        let phase = CGFloat(frameIndex) * 0.5

        for i in 0..<stripCount {
            let normalizedY = CGFloat(i) / CGFloat(stripCount)
            let dx = amplitude * sin((normalizedY * frequency + phase) * .pi * 2)

            let stripY = extent.origin.y + CGFloat(i) * stripHeight
            let stripRect = CGRect(x: extent.origin.x, y: stripY,
                                   width: extent.width, height: stripHeight)

            let strip = image.cropped(to: stripRect)
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))

            result = strip.composited(over: result)
        }

        return result.cropped(to: extent)
    }
}
