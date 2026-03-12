import CoreImage

/// Progressively displaces horizontal bands of the image, creating a digital
/// glitch / data corruption aesthetic. At progress 0 the image is clean;
/// at progress 1 bands are shifted at full intensity. Uses deterministic
/// pseudo-random offsets seeded by frameIndex for consistent GIF output.
///
/// - `intensity` scales the maximum horizontal displacement.
/// - `inversion` controls how many displaced bands get their colors inverted
///   (0 = none, 1 = all displaced bands inverted).
public struct GlitchEffect: VisualEffect {
    private let maxShift: CGFloat
    private let inversionAmount: CGFloat
    private let bandCount: Int = 48

    public init(intensity: Double = 0.5, inversion: Double = 0.0) {
        self.maxShift = max(2.0, 60.0 * CGFloat(intensity))
        self.inversionAmount = CGFloat(max(0, min(1, inversion)))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil)
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        let shift = maxShift * (progress * progress)
        guard shift > 1.0 else { return image }

        let extent = image.extent
        let bandHeight = extent.height / CGFloat(bandCount)
        var result = image

        for i in 0..<bandCount {
            let seed = UInt64(frameIndex * 137 + i * 31)
            let hash = pseudoRandom(seed)
            let shouldShift = hash % 3 == 0
            guard shouldShift else { continue }

            let direction: CGFloat = (hash % 2 == 0) ? 1.0 : -1.0
            let magnitude = CGFloat(hash % 100) / 100.0
            let dx = shift * magnitude * direction

            let bandY = extent.origin.y + CGFloat(i) * bandHeight
            let bandRect = CGRect(x: extent.origin.x, y: bandY, width: extent.width, height: bandHeight)

            var band = image.cropped(to: bandRect)
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))

            if inversionAmount > 0 {
                let inversionHash = pseudoRandom(seed &+ 97)
                let inversionChance = CGFloat(inversionHash % 100) / 100.0
                if inversionChance < inversionAmount {
                    band = band.applyingFilter("CIColorInvert")
                        .cropped(to: band.extent)
                }
            }

            result = band.composited(over: result)
        }

        return result.cropped(to: extent)
    }

    private func pseudoRandom(_ seed: UInt64) -> UInt64 {
        var x = seed
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        return x
    }
}
