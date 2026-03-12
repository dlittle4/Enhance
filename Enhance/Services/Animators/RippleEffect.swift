import CoreImage

/// Rapidly shakes the entire image horizontally and overlays a red tint,
/// simulating an angry vibration effect. Shake intensity is fixed at a
/// strong level; the `redness` parameter controls how red the image gets.
///
/// - `redness` (0–1) controls the strength of the red color overlay.
public struct RippleEffect: VisualEffect {
    private let maxAmplitude: CGFloat = 3.75
    private let speed: CGFloat = 60.0
    private let redness: CGFloat

    public init(intensity: Double = 0.5) {
        self.redness = CGFloat(max(0, min(1, intensity)))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let ramp = min(progress * 2.0, 1.0)
        let amplitude = maxAmplitude * ramp
        guard amplitude > 0.1 else { return image }

        let dx = amplitude * sin(CGFloat(frameIndex) * speed)

        let clamped = image.clamped(to: image.extent)
        var result = clamped
            .transformed(by: CGAffineTransform(translationX: dx, y: 0))
            .cropped(to: image.extent)

        if redness > 0.01 {
            let redAlpha = redness * 0.45 * ramp
            let redOverlay = CIImage(color: CIColor(red: 0.9, green: 0.05, blue: 0.02, alpha: redAlpha))
                .cropped(to: image.extent)
            result = redOverlay.composited(over: result).cropped(to: image.extent)
        }

        return result
    }
}
