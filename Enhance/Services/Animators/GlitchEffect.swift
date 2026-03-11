import CoreImage

/// Progressively displaces horizontal bands of the image, creating a digital
/// glitch / data corruption aesthetic. At progress 0 the image is clean;
/// at progress 1 bands are shifted at full intensity. Uses deterministic
/// pseudo-random offsets seeded by frameIndex for consistent GIF output.
///
/// - `intensity` scales the maximum horizontal displacement.
public struct GlitchEffect: VisualEffect {
    private let maxShift: CGFloat
    private let bandCount: Int = 12

    public init(intensity: Double = 0.5) {
        self.maxShift = max(2.0, 60.0 * CGFloat(intensity))
    }

    public func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
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

            let band = image.cropped(to: bandRect)
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))

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
