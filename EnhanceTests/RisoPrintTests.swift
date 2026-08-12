import Testing
import CoreImage
import SwiftUI
@testable import Enhance

/// RISO — the app's first custom kernel effect.
///
/// EFFECTS.md is blunt that structural tests cannot see a wrong-*looking* effect, and both
/// `extent ==` and `createCGImage != nil` passed while EDGES rendered cyan instead of green. So
/// these deliberately assert *behaviour a wrong port would break* — the spot colours reaching
/// the output, the early-out, the screen tracking zoom — and the "does it look like a
/// risograph print" question is answered by rendering and looking, not here.
struct RisoPrintTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let side = 64

    /// A luminance ramp, not a flat colour. RISO separates *tonal bands*, so a solid fixture
    /// exercises exactly one band and would hide any error in the other two — the same trap
    /// LEARNINGS records for the laser-eyes clamp bug.
    private func ramp() -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: bounds)
            .applyingFilter("CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                "inputPoint1": CIVector(x: CGFloat(side), y: CGFloat(side)),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1)
            ])
            .cropped(to: bounds)
    }

    private func pixels(_ image: CIImage) -> [UInt8] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &buf, rowBytes: w * 4, bounds: image.extent,
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buf
    }

    @Test("renders at full progress without changing the frame's extent")
    func riso_producesOutput() {
        let input = ramp()
        let output = RisoPrintEffect().apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(output.extent == input.extent)
        #expect(pixels(output).contains { $0 != 0 })
    }

    /// The early-out. This is a performance contract, not a cosmetic one — three input samples
    /// and three screens make RISO the most expensive effect in the app, so it must not run at
    /// zero strength.
    @Test("at zero intensity the frame is returned untouched")
    func riso_atZeroIntensity_isANoOp() {
        let input = ramp()
        let output = RisoPrintEffect(intensity: 0).apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(pixels(output) == pixels(input))
    }

    @Test("at zero progress the effect has not started")
    func riso_atZeroProgress_isANoOp() {
        let input = ramp()
        let output = RisoPrintEffect().apply(to: input, progress: 0, frameIndex: 0)
        #expect(pixels(output) == pixels(input))
    }

    /// The one that would catch a dead kernel. A greyscale ramp has zero chroma; RISO prints it
    /// in three coloured inks, so the output must gain colour. If the metallib failed to load,
    /// `apply` returns the input unchanged and this fails — which is the failure mode a
    /// `!= nil` check cannot see.
    @Test("a greyscale ramp comes back coloured, because the inks are applied")
    func riso_introducesColourIntoAGreyscaleImage() {
        let input = ramp()
        let output = RisoPrintEffect(intensity: 1.0).apply(to: input, progress: 1.0, frameIndex: 0)

        func meanChroma(_ bytes: [UInt8]) -> Double {
            var total = 0.0
            var count = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                total += Double(max(r, max(g, b)) - min(r, min(g, b)))
                count += 1
            }
            return count > 0 ? total / Double(count) : 0
        }

        let before = meanChroma(pixels(input))
        let after = meanChroma(pixels(output))
        #expect(before < 2.0, "fixture should be greyscale, measured chroma \(before)")
        #expect(after > before + 5.0, "RISO should print in colour; chroma went \(before) → \(after)")
    }

    /// Changing the spot colours must change the picture. This is what proves the
    /// `GradientStops` actually reach the kernel rather than being dropped on the way through
    /// `EffectOptions` — a wiring mistake that would otherwise render a perfectly plausible
    /// print in the default palette forever.
    @Test("the stop colours reach the kernel")
    func riso_respectsItsStopColours() {
        let input = ramp()
        let warm = RisoPrintEffect(intensity: 1.0, stops: .default)
        let cool = RisoPrintEffect(
            intensity: 1.0,
            stops: GradientStops(dark: .blue, mid: .green, light: .cyan)
        )

        let a = pixels(warm.apply(to: input, progress: 1.0, frameIndex: 0))
        let b = pixels(cool.apply(to: input, progress: 1.0, frameIndex: 0))
        #expect(a != b)
    }

    /// A grid effect must scale its screen with the zoom, or the preview and the export
    /// disagree the moment the user pinches — the preview applies effects to the un-zoomed
    /// source and lets the scroll view magnify the result. Same class of bug as DITHER's crawl.
    @Test("the halftone screen tracks the frame's zoom")
    func riso_screenScalesWithGeometry() {
        let input = ramp()
        let effect = RisoPrintEffect(intensity: 1.0)

        let unzoomed = effect.apply(to: input, progress: 1.0, frameIndex: 0,
                                    viewportCenter: nil, geometry: .identity)
        let zoomed = effect.apply(to: input, progress: 1.0, frameIndex: 0,
                                  viewportCenter: nil,
                                  geometry: FrameGeometry(scale: 3.0, contentOrigin: .zero))
        #expect(pixels(unzoomed) != pixels(zoomed))
    }

    /// Contrast is a real control, not decoration: it decides how much of the image lands in
    /// each tonal band, and a flat photo without it collapses into a single ink.
    @Test("contrast changes the tonal distribution")
    func riso_contrastIsLive() {
        let input = ramp()
        let low = RisoPrintEffect(intensity: 1.0, contrast: 0.0)
        let high = RisoPrintEffect(intensity: 1.0, contrast: 1.0)
        #expect(pixels(low.apply(to: input, progress: 1.0, frameIndex: 0))
                != pixels(high.apply(to: input, progress: 1.0, frameIndex: 0)))
    }

    /// Declaration shape, checked here as well as in EffectParameterTests because RISO is the
    /// effect that moved the cap: four sliders plus one colour picker, INTENSITY first.
    @Test("RISO declares four sliders and a single colour picker")
    func riso_parameterShape() {
        let params = VisualEffectType.risoPrint.parameters
        #expect(params.count == 6)
        #expect(params.first?.id == EffectParameter.intensityID)
        #expect(params.filter { $0.kind == .slider }.count == 5)
        #expect(params.filter { $0.kind != .slider }.count == 1)
        #expect(VisualEffectType.risoPrint.colorPickerKind == .gradientStops)
    }
}
