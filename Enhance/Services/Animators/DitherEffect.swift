import CoreImage

/// Ordered dithering with hard posterisation — the retro 1-bit stipple that pairs
/// with the app's Silkscreen pixel-art identity.
struct DitherEffect: VisualEffect {
    private let clamped: CGFloat

    init(intensity: Double = 0.5) {
        self.clamped = CGFloat(max(0, min(1, intensity)))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        // Quadratic ease-in: dither is a hard-edged effect and lands best arriving
        // late, once the zoom has established the subject.
        let t = min(1.0, progress * progress * 1.6)
        let amount = clamped * t
        guard amount > 0.01 else { return image }

        // Posterise hard — down to 3 levels at full strength. GIF output is already
        // 256-colour palettised with its own dithering, so a gentle pass gets
        // swamped and reads as "slightly noisy" rather than as a deliberate look.
        // A large dither amplitude against few levels is what survives that.
        let levels = 12.0 - 9.0 * amount

        // Dither *then* quantise. That order is the whole effect: the dither noise
        // pushes pixel values across the posterise boundaries, so flat gradients
        // break into stipple. Reversed, it just adds noise to an already-banded
        // image.
        return image
            .applyingFilter("CIDither", parameters: [
                kCIInputIntensityKey: 2.0 * amount
            ])
            .applyingFilter("CIColorPosterize", parameters: [
                "inputLevels": levels
            ])
            .cropped(to: image.extent)
    }
}
