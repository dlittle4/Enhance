import CoreImage

/// The mask conditioning FEATURE-MOTION-EFFECTS.md §1b calls for: feathering each mask, and
/// averaging it with its neighbours so Vision's frame-to-frame edge jitter does not show up
/// five times over in an echo stack. Lazy CI graphs, no context — the caller's renders them.
enum MotionMasks {

    /// Softens a mask's edge by `radius` mask pixels. 0 returns it untouched.
    static func feathered(_ mask: CIImage, radius: Double) -> CIImage {
        guard radius > 0.01 else { return mask }
        return mask
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: mask.extent)
    }

    /// `¼·m₋₁ + ½·m + ¼·m₊₁` per frame, treating a missing neighbour as the frame itself so the
    /// weights still sum to one. Masks must share an extent; a neighbour of a different size
    /// is ignored the same way.
    static func neighbourSmoothed(_ masks: [CIImage?]) -> [CIImage?] {
        masks.indices.map { i in
            guard let centre = masks[i] else { return nil }
            func neighbour(_ j: Int) -> CIImage {
                guard masks.indices.contains(j), let m = masks[j], m.extent == centre.extent else { return centre }
                return m
            }
            let prev = neighbour(i - 1), next = neighbour(i + 1)
            let sum = scaled(centre, by: 0.5)
                .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: scaled(prev, by: 0.25)])
                .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: scaled(next, by: 0.25)])
            return sum.cropped(to: centre.extent)
        }
    }

    private static func scaled(_ image: CIImage, by weight: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: weight, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: weight, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: weight, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: weight)
        ])
    }
}
