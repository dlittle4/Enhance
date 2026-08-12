import CoreImage
import CoreGraphics

/// CAUSTIC — rippling pool light cast over the photo.
///
/// The kernel is `Shaders/CI/Caustic.ci.metal` and carries the technique notes. In short: the
/// bright network is a Worley cell-wall field, built analytically because LEARNINGS 2026-08-10
/// establishes that discrete structure — rays, cell walls, caustic ridges — cannot be recovered
/// from blurred noise. This is the effect that most needed the kernel gate; Core Image has no
/// caustic and no Voronoi generator with a controllable phase.
///
/// - `intensity` is how brightly the light lands.
/// - `size` is the cell size, i.e. how coarse the network reads.
/// - `speed` is **quantised to a whole number of orbits** so the animation loops seamlessly.
/// - `sharpness` narrows the ridges from broad glow to thin filigree.
/// - `color` tints the light; ridge cores stay white so any swatch still reads as light.
///
/// **This is a grid effect** (see EFFECTS.md): the cells have a size in pixels, so they scale with
/// `FrameGeometry.scale` and their phase follows `contentOrigin`. Without both, the network sits
/// on the frame and slides across the subject as the animation pans.
struct CausticEffect: VisualEffect {
    private let brightness: CGFloat
    private let cellSize: CGFloat
    private let orbits: CGFloat
    private let width: CGFloat
    private let tint: (CGFloat, CGFloat, CGFloat)

    private static let kernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "Caustic.ci", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIKernel(functionName: "caustic", fromMetalLibraryData: data)
    }()

    init(intensity: Double = 0.5,
         size: Double = 0.5,
         speed: Double = 0.5,
         sharpness: Double = 0.5,
         color: LaserColor = .blue) {
        // Tuned down from 1.2 after looking at it: at the midpoint the network overwhelmed the
        // photo and read as a lattice laid over it rather than as light falling on it. The
        // effect should still be able to go bold at the top of the range.
        self.brightness = 0.85 * CGFloat(max(0, min(1, intensity)))
        // 24pt cells are a tight shimmer; 120pt are the broad slow rolls you get in deep water.
        self.cellSize = 24.0 + 96.0 * CGFloat(max(0, min(1, size)))
        // Deliberately an integer. The feature points orbit with period 1, so a whole number of
        // orbits over the GIF's progress means the last frame equals the first — a seamless loop
        // with no cross-fade. A continuous speed would look right in the preview and jump on the
        // GIF's wrap, which is the kind of bug that only shows up in the exported artifact.
        self.orbits = CGFloat(1 + Int((3.0 * max(0, min(1, speed))).rounded()))
        // Higher sharpness → narrower wall band → thinner, brighter filigree.
        //
        // Range narrowed after looking at it: the original 0.05–0.35 put the *midpoint* at a
        // 0.20 band, which drew a thick connected lattice — unmistakably a Voronoi diagram
        // rather than light on water. Caustics are thin. The top of the range is still broad
        // enough to glow.
        self.width = 0.03 + 0.17 * (1.0 - CGFloat(max(0, min(1, sharpness))))
        self.tint = color.rgb
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
        guard brightness > 0.01 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return image }
        guard let kernel = Self.kernel else { return image }

        let zoom = max(1.0, geometry.scale)
        let cell = cellSize * zoom

        // Time comes from `progress`, not `frameIndex`, so the loop is defined by the animation
        // rather than by however many frames the current speed setting produced.
        let phase = progress * orbits

        let origin = CGPoint(x: geometry.contentOrigin.x.truncatingRemainder(dividingBy: cell),
                             y: geometry.contentOrigin.y.truncatingRemainder(dividingBy: cell))

        let output = kernel.apply(
            extent: extent,
            // The kernel samples only its own destination coordinate, so the region of interest
            // is exactly the region being rendered. No outset — unlike RISO, which samples at an
            // offset for misregistration and has to widen this.
            roiCallback: { _, rect in rect },
            arguments: [image,
                        CIVector(x: tint.0, y: tint.1, z: tint.2, w: 1),
                        cell, phase, width, brightness,
                        CIVector(x: origin.x, y: origin.y)]
        )

        return output?.cropped(to: extent) ?? image
    }
}
