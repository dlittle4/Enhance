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

    // MARK: - Mask motion

    /// How the subject moved between two masks, in normalized units of the mask's extent:
    /// the centroid of the pixels that *appeared* (the leading edge) minus the centroid of
    /// the pixels that *vanished* (the trailing edge). A waving hand on a still body moves
    /// this where a face track sees nothing, which is why it is the primary subject velocity
    /// (device pass, 2026-09-03). Nil when nothing appeared or vanished.
    static func motion(from previous: CIImage, to current: CIImage, context: CIContext) -> CGVector? {
        guard previous.extent == current.extent, current.extent.width > 0, current.extent.height > 0 else { return nil }
        let appeared = current.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: previous.applyingFilter("CIColorInvert")
        ]).cropped(to: current.extent)
        let vanished = previous.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: current.applyingFilter("CIColorInvert")
        ]).cropped(to: current.extent)
        guard let lead = centroid(of: appeared, context: context),
              let trail = centroid(of: vanished, context: context) else { return nil }
        return CGVector(dx: lead.x - trail.x, dy: lead.y - trail.y)
    }

    /// The centroid of a mask's white, in normalized units of its extent, or nil when it is
    /// (near) empty. Two area averages: the mask weighted by an x ramp and a y ramp, over the
    /// mask's own average.
    static func centroid(of mask: CIImage, context: CIContext) -> CGPoint? {
        let extent = mask.extent
        guard let area = average(of: mask, context: context), area > 0.0005 else { return nil }
        let rampX = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.minX, y: extent.midY),
            "inputPoint1": CIVector(x: extent.maxX, y: extent.midY),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1)
        ])?.outputImage?.cropped(to: extent)
        let rampY = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: extent.minY),
            "inputPoint1": CIVector(x: extent.midX, y: extent.maxY),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1)
        ])?.outputImage?.cropped(to: extent)
        guard let rampX, let rampY,
              let mx = average(of: mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: rampX]).cropped(to: extent), context: context),
              let my = average(of: mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: rampY]).cropped(to: extent), context: context)
        else { return nil }
        return CGPoint(x: mx / area, y: my / area)
    }

    /// Mean red channel over the whole image, 0…1.
    private static func average(of image: CIImage, context: CIContext) -> CGFloat? {
        guard let out = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)
        ])?.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(out, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return CGFloat(pixel[0])
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
