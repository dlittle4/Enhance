import CoreImage

/// Ordered dithering with hard posterisation — the retro stipple that pairs with the
/// app's Silkscreen pixel-art identity.
///
/// - `intensity` drives dither amplitude and how far the image is posterised.
/// - `size` sets the dither cell size, i.e. how chunky the stipple reads.
struct DitherEffect: VisualEffect {
    private let clamped: CGFloat
    private let baseCell: CGFloat

    /// Ceiling on cell size in output pixels. Without it, a base cell of 8 at 12x zoom
    /// would be 96px — six blocks across the whole frame. This trades exact
    /// lock-to-content at extreme zoom for staying recognisable as an image.
    private static let maxCell: CGFloat = 40

    init(intensity: Double = 0.5, size: Double = 0.5) {
        self.clamped = CGFloat(max(0, min(1, intensity)))
        // 1pt is native-resolution dither (finest); 8pt is heavily blocky.
        self.baseCell = 1.0 + 7.0 * CGFloat(max(0, min(1, size)))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, frameScale: 1.0)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, frameScale: 1.0)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, frameScale: CGFloat) -> CIImage {
        // Quadratic ease-in: dither is a hard-edged effect and lands best arriving
        // late, once the zoom has established the subject.
        let t = min(1.0, progress * progress * 1.6)
        let amount = clamped * t
        guard amount > 0.01 else { return image }

        // Posterise hard — down to 3 levels at full strength. GIF output is already
        // 256-colour palettised with its own dithering, so a gentle pass gets swamped
        // and reads as "slightly noisy" rather than as a deliberate look. A large
        // dither amplitude against few levels is what survives that.
        let levels = 12.0 - 9.0 * amount

        // Scale the cell by the frame's zoom so the stipple stays locked to image
        // content rather than to the output frame. Without this the pattern is a fixed
        // size in output pixels and the image appears to slide underneath a static
        // overlay, which also makes the GIF disagree with the preview.
        let cell = min(Self.maxCell, max(1.0, baseCell * max(1.0, frameScale)))

        // A 1pt cell is native-resolution dither, so skip the resample entirely.
        guard cell > 1.5 else {
            return quantise(image, amount: amount, levels: levels).cropped(to: image.extent)
        }

        // Dither at 1/cell resolution, then blow it back up with nearest-neighbour
        // sampling so each dither dot becomes a solid cell×cell block. Dithering at
        // full resolution and *then* pixelating would average the dots away; the
        // pattern has to be generated at the size it will be displayed.
        let shrunk = image.transformed(by: CGAffineTransform(scaleX: 1.0 / cell, y: 1.0 / cell))
        let dithered = quantise(shrunk, amount: amount, levels: levels)

        return dithered
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .cropped(to: image.extent)
    }

    /// Dither *then* posterise. That order is the whole effect: the dither noise pushes
    /// pixel values across the posterise boundaries, so flat gradients break into
    /// stipple. Reversed, it just adds noise to an already-banded image.
    private func quantise(_ image: CIImage, amount: CGFloat, levels: CGFloat) -> CIImage {
        image
            .applyingFilter("CIDither", parameters: [
                kCIInputIntensityKey: 2.0 * amount
            ])
            .applyingFilter("CIColorPosterize", parameters: [
                "inputLevels": levels
            ])
    }
}
