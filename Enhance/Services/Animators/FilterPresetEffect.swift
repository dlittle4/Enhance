import CoreImage

/// Applies a `FilterPreset` colour grade, dissolving from the original toward the
/// fully-graded image so intensity works uniformly across every preset.
struct FilterPresetEffect: VisualEffect {
    private let strength: CGFloat
    private let preset: FilterPreset

    /// - Parameter intensity: maps to the dissolve ceiling over `0.35...1.0`. A
    ///   colour grade at 0% is indistinguishable from having no effect selected,
    ///   so the floor keeps the whole slider range meaningful.
    init(intensity: Double = 0.5, preset: FilterPreset = .sepia) {
        let clamped = CGFloat(max(0, min(1, intensity)))
        self.strength = 0.35 + 0.65 * clamped
        self.preset = preset
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        // Settles by the halfway point: a grade that keeps shifting through the
        // whole zoom reads as a colour-cast glitch rather than as a look.
        let amount = strength * min(1.0, progress * 2.0)
        guard amount > 0.01 else { return image }

        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: preset.graded(image),
            kCIInputTimeKey: amount
        ]).cropped(to: image.extent)
    }
}
