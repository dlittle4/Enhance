import CoreImage

/// Bold posterization with boosted saturation and contrast,
/// inspired by Warhol-style pop art. Progress drives the
/// posterization level from smooth to chunky color bands.
struct PopArtEffect: VisualEffect {
    private let maxLevels: CGFloat

    init(intensity: Double = 0.5) {
        // Fewer levels = more extreme posterization.
        // At low intensity: 8 levels (subtle). At max: 3 levels (bold).
        self.maxLevels = CGFloat(max(3, 8 - 5 * intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let t = min(1.0, progress * 1.3)
        guard t > 0.01 else { return image }

        // Interpolate posterization levels: start smooth, end chunky
        let levels = max(3.0, 12.0 - (12.0 - maxLevels) * t)

        let saturated = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.0 + 0.8 * t,
            kCIInputContrastKey: 1.0 + 0.3 * t
        ])

        let posterized = saturated.applyingFilter("CIColorPosterize", parameters: [
            "inputLevels": levels
        ])

        return posterized.cropped(to: image.extent)
    }
}
