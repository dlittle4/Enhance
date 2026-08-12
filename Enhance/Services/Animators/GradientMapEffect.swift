import CoreImage
import CoreGraphics

/// Maps image luminance onto a user-chosen colour ramp — shadows take the ramp's
/// dark stop, highlights its light stop — via a precomputed colour cube.
struct GradientMapEffect: VisualEffect {
    private let strength: CGFloat
    private let stops: GradientStops
    private let midpointExponent: CGFloat

    private static let cubeDimension = 32

    /// - `midpoint` slides which input luminance lands on the ramp's middle stop, which
    ///   is what decides whether an image reads as mostly-shadow or mostly-highlight
    ///   against the same three colours. It was pinned to 0.5.
    init(intensity: Double = 0.5, stops: GradientStops = .default, midpoint: Double = 0.5) {
        self.strength = CGFloat(max(0.15, min(1, intensity)))
        self.stops = stops
        // Implemented as a gamma on the luminance *lookup* rather than by moving the
        // stop: the ramp keeps its even spacing, and the exponent solves
        // pow(m, k) == 0.5, so k is exactly 1 at the default and the shipped look is
        // reproduced bit for bit.
        let m = 0.15 + 0.7 * CGFloat(max(0, min(1, midpoint)))
        self.midpointExponent = log(0.5) / log(m)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amount = strength * min(1.0, progress * 1.5)
        guard amount > 0.01 else { return image }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }

        let cubeData = Self.cube(for: stops, exponent: midpointExponent)

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

    private static func cube(for stops: GradientStops, exponent: CGFloat) -> Data {
        // The exponent MUST be part of the key. It changes the cube's contents without
        // changing a single stop colour, so keying on colours alone would serve a stale
        // cube for every midpoint after the first — a silent wrong-look bug with no
        // failure anywhere.
        let key = stops.cacheKey(exponent: Float(exponent))

        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let built = makeCubeData(for: stops, exponent: exponent)

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
    private static func makeCubeData(for stops: GradientStops, exponent: CGFloat) -> Data {
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
                    // Gamma on the lookup position; exponent 1 is the identity.
                    let positioned = exponent == 1 ? luminance : pow(max(0, luminance), exponent)
                    let mapped = stops.color(at: positioned)

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
