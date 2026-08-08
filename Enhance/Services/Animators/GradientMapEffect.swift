import CoreImage
import CoreGraphics

/// Maps image luminance onto a user-chosen colour ramp — shadows take the ramp's
/// dark stop, highlights its light stop — via a precomputed colour cube.
struct GradientMapEffect: VisualEffect {
    private let strength: CGFloat
    private let stops: GradientStops

    private static let cubeDimension = 32

    init(intensity: Double = 0.5, stops: GradientStops = .default) {
        self.strength = CGFloat(max(0.15, min(1, intensity)))
        self.stops = stops
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amount = strength * min(1.0, progress * 1.5)
        guard amount > 0.01 else { return image }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }

        let cubeData = Self.cube(for: stops)

        // CIColorCubeWithColorSpace, not CIColorCube: the plain filter operates in
        // the CIContext's working space, which is linear sRGB by default. The stop
        // colours come from a ColorPicker as sRGB, so a plain cube would map
        // luminance computed in the wrong space and come out washed out.
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

    // MARK: - Cube cache

    /// Cubes are memoised because `EditorViewModel.activeVisualEffectList` is a
    /// *computed* property re-evaluated on every debounced preview update, so `init`
    /// and `apply` run on every slider-drag frame. Rebuilding 32³ entries each time
    /// would be ~33k iterations per frame.
    ///
    /// Colours are user-chosen now, so the key is the resolved RGB rather than a
    /// preset enum, and the cache is bounded — a user can produce unlimited distinct
    /// ramps by dragging the colour wheel. Intensity never affects the cube, so
    /// dragging the intensity slider always hits the cache.
    private static let cacheLock = NSLock()
    private static var cache: [CubeKey: Data] = [:]
    private static var insertionOrder: [CubeKey] = []
    private static let cacheLimit = 12

    private static func cube(for stops: GradientStops) -> Data {
        let key = stops.cacheKey

        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let built = makeCubeData(for: stops)

        cacheLock.lock()
        cache[key] = built
        insertionOrder.append(key)
        if insertionOrder.count > cacheLimit {
            let evicted = insertionOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheLock.unlock()

        return built
    }

    /// Builds the RGBA float lattice for `CIColorCubeWithColorSpace`. Each lattice
    /// point's Rec.709 luminance selects a colour from the ramp, which is what turns
    /// the cube into a luminance→ramp mapping rather than a per-channel curve.
    ///
    /// Cube data must be premultiplied. Alpha is always 1 here, so writing the RGB
    /// unscaled is already correct for opaque input.
    private static func makeCubeData(for stops: GradientStops) -> Data {
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
                    let mapped = stops.color(at: luminance)

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
