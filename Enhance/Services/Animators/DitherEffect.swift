import CoreImage

/// Ordered dithering with hard posterisation — the retro stipple that pairs with the
/// app's Silkscreen pixel-art identity.
///
/// - `intensity` drives dither amplitude and how far the image is posterised.
/// - `size` sets the dither cell size, i.e. how chunky the stipple reads.
struct DitherEffect: VisualEffect {
    private let clamped: CGFloat
    private let baseCell: CGFloat

    /// Sanity bound on cell size in output pixels. Deliberately generous: at the top of
    /// the SCALE range and full zoom the honest cell size is ~96px, and clamping below
    /// that would silently stop the grid tracking the zoom — which is the drift this
    /// effect exists to avoid.
    private static let maxCell: CGFloat = 96

    init(intensity: Double = 0.5, size: Double = 0.5) {
        self.clamped = CGFloat(max(0, min(1, intensity)))
        // 1pt is native-resolution dither (finest); 8pt is heavily blocky.
        self.baseCell = 1.0 + 7.0 * CGFloat(max(0, min(1, size)))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
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

        // Scale the cell with the zoom so the stipple stays the same size relative to
        // the subject rather than to the output frame.
        let cell = min(Self.maxCell, max(1.0, baseCell * max(1.0, geometry.scale)))

        // A 1pt cell is native-resolution dither, so skip the resample entirely —
        // there is no grid to align at that size.
        guard cell > 1.5 else {
            return quantise(image, amount: amount, levels: levels).cropped(to: image.extent)
        }

        // Phase-align the grid to the content. Scaling the cell alone is not enough:
        // the animation pans as it zooms, so a grid anchored to the frame's corner
        // still slides across the subject. Offsetting by the content origin modulo the
        // cell size pins cells to the same image features from frame to frame.
        let phaseX = geometry.contentOrigin.x.truncatingRemainder(dividingBy: cell)
        let phaseY = geometry.contentOrigin.y.truncatingRemainder(dividingBy: cell)

        // Pad before shifting so the offset cannot expose an uncovered strip at the
        // edges once the result is cropped back to the original extent.
        let padded = image
            .clampedToExtent()
            .cropped(to: image.extent.insetBy(dx: -cell * 2, dy: -cell * 2))

        // Dither at 1/cell resolution, then blow it back up with nearest-neighbour
        // sampling so each dither dot becomes a solid cell×cell block. Dithering at
        // full resolution and *then* pixelating would average the dots away; the
        // pattern has to be generated at the size it will be displayed.
        let shifted = padded.transformed(by: CGAffineTransform(translationX: -phaseX, y: -phaseY))
        let shrunk = shifted.transformed(by: CGAffineTransform(scaleX: 1.0 / cell, y: 1.0 / cell))
        let dithered = quantise(shrunk, amount: amount, levels: levels)

        return dithered
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .transformed(by: CGAffineTransform(translationX: phaseX, y: phaseY))
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
