import Testing
import CoreImage
@testable import Enhance

/// CAUSTIC — a Worley cell-wall network composited additively over the photo.
///
/// The properties worth guarding are the ones a plausible-but-wrong implementation would break:
/// that the light is *added* rather than blended, that the animation genuinely moves, and that it
/// **loops** — a seam at the GIF's wrap is invisible in a still and invisible in the preview, so
/// only a test comparing the first and last frames can catch it.
struct CausticTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let side = 48

    /// Mid grey, so added light has room to show and the comparison is not against a clipped
    /// white or a black floor.
    private func fixture() -> CIImage {
        CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    private func pixels(_ image: CIImage) -> [UInt8] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &buf, rowBytes: w * 4, bounds: image.extent,
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buf
    }

    private func meanLuma(_ bytes: [UInt8]) -> Double {
        var total = 0.0
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            total += 0.299 * Double(bytes[i]) + 0.587 * Double(bytes[i + 1]) + 0.114 * Double(bytes[i + 2])
            count += 1
        }
        return count > 0 ? total / Double(count) : 0
    }

    @Test("renders without changing the frame's extent")
    func caustic_preservesExtent() {
        let input = fixture()
        let output = CausticEffect().apply(to: input, progress: 0.5, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test("at zero intensity the frame is returned untouched")
    func caustic_atZeroIntensity_isANoOp() {
        let input = fixture()
        let output = CausticEffect(intensity: 0).apply(to: input, progress: 0.5, frameIndex: 0)
        #expect(pixels(output) == pixels(input))
    }

    /// Additive, not source-over. Light lands *on* the subject, so the mean must rise — a blend
    /// would darken the frame wherever the network is dim, which is the wrong look and the easy
    /// mistake. This also fails if the metallib never loaded, since `apply` then returns the
    /// input unchanged.
    @Test("the light is added, so the frame gets brighter")
    func caustic_addsLight() {
        let input = fixture()
        let output = CausticEffect(intensity: 1.0).apply(to: input, progress: 0.5, frameIndex: 0)

        let before = meanLuma(pixels(input))
        let after = meanLuma(pixels(output))
        #expect(after > before + 2.0, "expected added light, mean went \(before) → \(after)")
    }

    @Test("the network moves between frames")
    func caustic_animates() {
        let input = fixture()
        let effect = CausticEffect(intensity: 1.0)
        let early = pixels(effect.apply(to: input, progress: 0.1, frameIndex: 0))
        let late = pixels(effect.apply(to: input, progress: 0.6, frameIndex: 12))
        #expect(early != late)
    }

    /// The loop. Feature points orbit with period 1 and SPEED is quantised to a whole number of
    /// orbits, so progress 0 and progress 1 must render **identically** — otherwise the GIF jumps
    /// on every wrap. Nothing in a single frame or in the editor preview can reveal this.
    /// Tolerance rather than byte equality, and the reason matters. The loop is exact in *maths*
    /// — the orbits and the brightness swell are both periodic with period 1, and SPEED is a
    /// whole number of orbits — but not in *floating point*: `sin(2π·4)` is around 1e-7 rather
    /// than 0, and that survives a `pow` and a multiply into the odd last-bit difference.
    ///
    /// A real seam is not subtle. When the second octave advanced at a non-integer rate the
    /// frames differed by tens of levels across most of the image, which this still catches. One
    /// level out of 255 on a handful of pixels is invisible and not worth pinning.
    @Test("progress 0 and progress 1 match, so the GIF loops without a jump")
    func caustic_loopsSeamlessly() {
        let input = fixture()
        for speed in [0.0, 0.34, 0.67, 1.0] {
            let effect = CausticEffect(intensity: 1.0, speed: speed)
            let first = pixels(effect.apply(to: input, progress: 0.0, frameIndex: 0))
            let last = pixels(effect.apply(to: input, progress: 1.0, frameIndex: 24))

            let worst = zip(first, last).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(worst <= 2, "speed \(speed) does not loop — worst channel differs by \(worst)/255 at the wrap")
        }
    }

    /// Grid effect: the cells must scale with the zoom, or the preview (which applies effects to
    /// the un-zoomed source) and the export (which applies them after the zoom) disagree.
    @Test("the cell network tracks the frame's zoom")
    func caustic_scalesWithGeometry() {
        let input = fixture()
        let effect = CausticEffect(intensity: 1.0)
        let unzoomed = effect.apply(to: input, progress: 0.5, frameIndex: 0,
                                    viewportCenter: nil, geometry: .identity)
        let zoomed = effect.apply(to: input, progress: 0.5, frameIndex: 0,
                                  viewportCenter: nil,
                                  geometry: FrameGeometry(scale: 3.0, contentOrigin: .zero))
        #expect(pixels(unzoomed) != pixels(zoomed))
    }

    @Test("SCALE and SHARPNESS are both live")
    func caustic_scaleAndSharpnessAreLive() {
        let input = fixture()
        let coarse = CausticEffect(intensity: 1.0, size: 1.0)
        let fine = CausticEffect(intensity: 1.0, size: 0.0)
        #expect(pixels(coarse.apply(to: input, progress: 0.5, frameIndex: 0))
                != pixels(fine.apply(to: input, progress: 0.5, frameIndex: 0)))

        let broad = CausticEffect(intensity: 1.0, sharpness: 0.0)
        let thin = CausticEffect(intensity: 1.0, sharpness: 1.0)
        #expect(pixels(broad.apply(to: input, progress: 0.5, frameIndex: 0))
                != pixels(thin.apply(to: input, progress: 0.5, frameIndex: 0)))
    }

    /// A narrower ridge lights less of the frame. This pins the *direction* of SHARPNESS, which
    /// "they differ" above cannot — a control wired backwards would still pass that.
    @Test("higher sharpness means a thinner, dimmer-overall network")
    func caustic_sharpnessNarrowsTheRidges() {
        let input = fixture()
        let broad = meanLuma(pixels(CausticEffect(intensity: 1.0, sharpness: 0.0)
            .apply(to: input, progress: 0.5, frameIndex: 0)))
        let thin = meanLuma(pixels(CausticEffect(intensity: 1.0, sharpness: 1.0)
            .apply(to: input, progress: 0.5, frameIndex: 0)))
        #expect(thin < broad, "sharpness should narrow the ridges; got broad \(broad), thin \(thin)")
    }

    @Test("the tint colour reaches the kernel")
    func caustic_respectsItsTint() {
        let input = fixture()
        let blue = CausticEffect(intensity: 1.0, color: .blue)
        let red = CausticEffect(intensity: 1.0, color: .red)
        #expect(pixels(blue.apply(to: input, progress: 0.5, frameIndex: 0))
                != pixels(red.apply(to: input, progress: 0.5, frameIndex: 0)))
    }

    @Test("CAUSTIC declares three extra sliders and a tint picker")
    func caustic_parameterShape() {
        let params = VisualEffectType.caustic.parameters
        #expect(params.count == 5)
        // COLOR leads as of 2026-08-13; intensity is the first slider behind it.
        #expect(params.first?.kind == .tintColor)
        #expect(params.first { $0.kind == .slider }?.id == EffectParameter.intensityID)
        #expect(params.filter { $0.kind != .slider }.count == 1)
        #expect(VisualEffectType.caustic.colorPickerKind == .tintColor)
    }
}
