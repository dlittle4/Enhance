import CoreImage
import Foundation

/// One of the twelve SwiftUIShaders looks graduated from SHADER LAB, run as a Core Image kernel
/// so it lives in the same pipeline as every other IMAGE effect.
///
/// The kernels are `Shaders/CI/ShaderPack.ci.metal` — the vendored bodies verbatim inside a
/// frame that stands in for `SwiftUI::Layer` (origin flip, sRGB round-trip, and a virtual
/// 650px frame so the pack's pixel constants export at the size they were tuned on). This type
/// owns the frame's arguments; each `VisualEffectType` case owns the mapping from its 0…1 sliders
/// to the pack's real units, in `effect(intensity:options:)`.
///
/// **Time.** The pack animates on wall-clock seconds; a GIF has none. `progress` drives `time`
/// across `cycleSeconds`, so the export plays the look through one fixed stretch of its
/// animation and the preview (progress 1) shows the end of it. Not every look loops cleanly at
/// the wrap — the pack was never asked to — which is why the amount ramps in over the first
/// frames (EFFECTS.md rule 4) rather than starting at full strength.
struct PackShaderEffect: VisualEffect {

    /// The kernel functions, by Metal name.
    enum Kernel: String, CaseIterable {
        case heatShimmer = "bcs_ci_heatShimmer"
        case chromaticSplit = "bcs_ci_chromaticSplit"
        case liveRipple = "bcs_ci_liveRipple"
        case pulse = "bcs_ci_pulse"
        case wavePool = "bcs_ci_wavePool"
        case melt = "bcs_ci_melt"
        case neonEdge = "bcs_ci_neonEdge"
        case pixelateStorm = "bcs_ci_pixelateStorm"
        case shockwave = "bcs_ci_shockwave"
        case thermal = "bcs_ci_thermal"
        case solarize = "bcs_ci_solarize"
        case datamosh = "bcs_ci_datamosh"
    }

    /// The short side of the virtual frame, in virtual pixels — the live preview's resolution,
    /// which is where the pack's constants were judged.
    static let referenceShortSide: CGFloat = 650

    /// How many seconds of the pack's animation one GIF plays through.
    static let cycleSeconds: Double = 4

    let kernel: Kernel

    /// The pack's parameters in kernel order, given the progress ramp (0…1) to apply to whatever
    /// reads as the look's *amount*. Baked as a closure at `init` so `apply` never sees a slider.
    let arguments: (Double) -> [Double]

    /// Loaded once per function; building a `CIKernel` parses the whole library. All twelve
    /// share one metallib (`ShaderPack.ci.metallib` — `$INPUT_FILE_BASE` keeps the `.ci`).
    private static let kernels: [Kernel: CIKernel] = {
        guard let url = Bundle.main.url(forResource: "ShaderPack.ci", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return [:] }
        var loaded: [Kernel: CIKernel] = [:]
        for kernel in Kernel.allCases {
            loaded[kernel] = try? CIKernel(functionName: kernel.rawValue, fromMetalLibraryData: data)
        }
        return loaded
    }()

    init(kernel: Kernel, arguments: @escaping (Double) -> [Double]) {
        self.kernel = kernel
        self.arguments = arguments
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: nil, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?) -> CIImage {
        apply(to: image, progress: progress, frameIndex: frameIndex, viewportCenter: viewportCenter, geometry: .identity)
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return image }
        guard let kernel = Self.kernels[kernel] else { return image }

        // Linear-with-clamp ramp, so the first frames ease in rather than pop; a pure 0 is a
        // no-op by construction because every amount multiplies by it.
        let ramp = Double(min(1.0, max(0.0, progress) * 1.5))
        let scale = max(extent.width, extent.height) > 0
            ? min(extent.width, extent.height) / Self.referenceShortSide
            : 1
        let virtualSize = CGSize(width: extent.width / scale, height: extent.height / scale)
        let time = Double(progress) * Self.cycleSeconds

        var args: [Any] = [
            image,
            CIVector(x: extent.origin.x, y: extent.origin.y),
            CIVector(x: virtualSize.width, y: virtualSize.height),
            scale,
            time
        ]
        args.append(contentsOf: arguments(ramp).map { $0 as Any })

        // Whole-frame ROI: PIXEL STORM's swirl and SHOCKWAVE's rings can read from anywhere, and a
        // tight ROI shows as black seams at tile edges only on large exports, never in a fixture.
        let output = kernel.apply(extent: extent, roiCallback: { _, _ in extent }, arguments: args)
        return output?.cropped(to: extent) ?? image
    }
}
