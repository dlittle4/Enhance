import CoreImage
import CoreGraphics

/// RISO — risograph emulation, and the app's first custom Core Image kernel.
///
/// Ported from `Docs/reference/riso-print.wgsl`; the kernel itself is
/// `Shaders/CI/Riso.ci.metal` and carries the pipeline comments. The look is tonal-band
/// separation — luminance split into shadow / midtone / highlight, one spot colour per band,
/// each screened at its own halftone angle, composited subtractively onto warm paper.
///
/// - `intensity` blends back toward the untouched frame, the same way GRADIENT's strength does.
/// - `stops` supplies the three spot colours. Shadows / midtones / highlights *is* dark / mid /
///   light, so `GradientStops` models this exactly rather than being borrowed to save a row.
/// - `scale` is the halftone cell size, `misregistration` the plate misalignment, `grain` the
///   paper texture, `contrast` the tonal punch that decides how much of the image lands in each
///   band — on a flat photo without it, everything collapses into the midtone colour.
///
/// **This is a grid effect** (see EFFECTS.md): the halftone screen has a characteristic size in
/// pixels, so the cell scales with `FrameGeometry.scale` and the screen's phase follows
/// `contentOrigin`. Without both the dots crawl across the subject as the animation pans, which
/// is the bug DITHER shipped with.
struct RisoPrintEffect: VisualEffect {
    private let strength: CGFloat
    private let stops: GradientStops
    private let cellSize: CGFloat
    private let misregistration: CGFloat
    private let grain: CGFloat
    private let contrast: CGFloat

    /// Loaded once. `init` runs on every preview frame and building a `CIKernel` parses the
    /// whole library, so constructing it per-instance would reparse on every slider tick.
    ///
    /// `$INPUT_FILE_BASE` strips only the last extension, so `Riso.ci.metal` builds to
    /// `Riso.ci.metallib` and the resource name keeps the `.ci`. Getting that wrong yields a
    /// silent nil rather than an error — see EFFECTS.md.
    private static let kernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "Riso.ci", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIKernel(functionName: "riso", fromMetalLibraryData: data)
    }()

    init(intensity: Double = 0.5,
         stops: GradientStops = .default,
         scale: Double = 0.5,
         misregistration: Double = 0.5,
         grain: Double = 0.5,
         contrast: Double = 0.5) {
        self.strength = CGFloat(max(0, min(1, intensity)))
        self.stops = stops
        // 2pt cells are a fine newsprint screen; 14pt are coarse enough to read as poster art.
        self.cellSize = 2.0 + 12.0 * CGFloat(max(0, min(1, scale)))
        // In pixels. The source normalised by image *width* and applied the result to both axes,
        // which makes the vertical offset proportionally smaller on a landscape image — almost
        // certainly unintentional. Working in pixels here treats both axes alike.
        self.misregistration = 8.0 * CGFloat(max(0, min(1, misregistration)))
        self.grain = CGFloat(max(0, min(1, grain)))
        // Exponential so the midpoint is exactly neutral: 0.5 → 1.0, 0 → 0.5, 1 → 2.0. A linear
        // ramp would make the default slider position already alter the tones.
        self.contrast = pow(2.0, (CGFloat(max(0, min(1, contrast))) - 0.5) * 2.0)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
        // Early-out *before* touching the kernel: three input samples and three screens make this
        // the most expensive effect in the app, and it is pure waste at zero strength.
        let amount = strength * min(1.0, progress * 1.5)
        guard amount > 0.01 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.isInfinite == false else { return image }
        guard let kernel = Self.kernel else { return image }

        let zoom = max(1.0, geometry.scale)
        let cell = cellSize * zoom
        let shift = misregistration * zoom

        // Only the phase modulo the cell matters, so this stays small regardless of how far the
        // frame has panned — the kernel does the same subtraction in floats.
        let phase = CGPoint(x: geometry.contentOrigin.x.truncatingRemainder(dividingBy: cell),
                            y: geometry.contentOrigin.y.truncatingRemainder(dividingBy: cell))

        let rgb = stops.resolved
        let shadow = Self.vector(rgb[0].rgb)
        let mid = Self.vector(rgb[1].rgb)
        let highlight = Self.vector(rgb[2].rgb)

        let output = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in
                // Outset by however far the misregistration samples reach, plus a margin.
                // Too tight gives black seams at Core Image's internal tile boundaries — which
                // show up only on large images, so never in a small test fixture.
                rect.insetBy(dx: -(shift + 2), dy: -(shift + 2))
            },
            arguments: [image, shadow, mid, highlight,
                        cell, shift, grain, contrast,
                        CIVector(x: phase.x, y: phase.y), amount]
        )

        return output?.cropped(to: extent) ?? image
    }

    /// Stop colours reach the kernel as a plain `CIVector`, not a `CIColor`. A `CIColor` would be
    /// colour-managed into the working space on the way in, which would double-apply the
    /// conversion the kernel already does deliberately — see the gamma note in `Riso.ci.metal`.
    private static func vector(_ rgb: RGB) -> CIVector {
        CIVector(x: CGFloat(rgb.r), y: CGFloat(rgb.g), z: CGFloat(rgb.b), w: 1)
    }
}
