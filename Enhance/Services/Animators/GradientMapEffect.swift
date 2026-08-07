import CoreImage
import CoreGraphics

/// Maps image luminance onto a multi-stop colour ramp — shadows take the ramp's
/// first stop, highlights its last — via a precomputed colour cube.
struct GradientMapEffect: VisualEffect {
    private let strength: CGFloat
    private let ramp: GradientRamp

    private static let cubeDimension = 32

    /// Cubes are memoised per ramp because `EditorViewModel.activeVisualEffectList`
    /// is a *computed* property re-evaluated on every debounced preview update, so
    /// `init` runs on every slider-drag frame. Building 32³ entries each time would
    /// be ~33k iterations per frame. Intensity only affects the dissolve, never the
    /// cube, so the ramp alone is a complete cache key.
    private static let cubes: [GradientRamp: Data] = {
        var built: [GradientRamp: Data] = [:]
        for ramp in GradientRamp.allCases {
            built[ramp] = makeCubeData(for: ramp)
        }
        return built
    }()

    init(intensity: Double = 0.5, ramp: GradientRamp = .sunset) {
        self.strength = CGFloat(max(0.15, min(1, intensity)))
        self.ramp = ramp
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amount = strength * min(1.0, progress * 1.5)
        guard amount > 0.01 else { return image }
        guard let cubeData = Self.cubes[ramp],
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }

        // CIColorCubeWithColorSpace, not CIColorCube: the plain filter operates in
        // the CIContext's working space, which is linear sRGB by default. The ramp
        // stops are authored as sRGB, so a plain cube would map luminance computed
        // in the wrong space and come out washed out and midtone-heavy.
        let mapped = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.cubeDimension,
            "inputCubeData": cubeData,
            "inputColorSpace": colorSpace
        ])

        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: mapped,
            kCIInputTimeKey: amount
        ]).cropped(to: image.extent)
    }

    // MARK: - Cube construction

    /// Builds the RGBA float lattice for `CIColorCubeWithColorSpace`. Each lattice
    /// point's Rec.709 luminance selects a colour from the ramp, which is what turns
    /// the cube into a luminance→ramp mapping rather than a per-channel curve.
    ///
    /// Cube data must be premultiplied. Alpha is always 1 here, so writing the RGB
    /// unscaled is already correct for opaque input.
    private static func makeCubeData(for ramp: GradientRamp) -> Data {
        let dim = cubeDimension
        let divisor = Float(dim - 1)
        var values = [Float](repeating: 0, count: dim * dim * dim * 4)
        var offset = 0

        for b in 0..<dim {
            let blue = CGFloat(Float(b) / divisor)
            for g in 0..<dim {
                let green = CGFloat(Float(g) / divisor)
                for r in 0..<dim {
                    let red = CGFloat(Float(r) / divisor)

                    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                    let mapped = ramp.color(at: luminance)

                    values[offset]     = Float(mapped.r)
                    values[offset + 1] = Float(mapped.g)
                    values[offset + 2] = Float(mapped.b)
                    values[offset + 3] = 1.0
                    offset += 4
                }
            }
        }

        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
