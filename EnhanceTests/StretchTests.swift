import Testing
import CoreImage
@testable import Enhance

/// STRETCH — pixels sampled from their projection onto a line, so a perpendicular column collapses
/// onto one source point and draws a streak.
///
/// The distinguishing property, and the one worth testing, is that the smear is **not a blur**:
/// along the streak the pixels are *identical copies*, not averages. A blur-based lookalike would
/// pass "the output changed" and fail that.
struct StretchTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let side = 64

    /// A colour patchwork that varies along **both** axes.
    ///
    /// The first version of this was horizontal bands only, and it made three tests fail against
    /// a working effect: a stretch along x moves each pixel to a different x at the *same* y, so
    /// on an image that is constant in x the output is legitimately identical to the input. A
    /// fixture has to vary along whichever axis the displacement runs, and since ANGLE is a
    /// control here, that means both.
    private func bands() -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        var image = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.05)).cropped(to: bounds)
        let colours: [CIColor] = [
            CIColor(red: 1, green: 0, blue: 0), CIColor(red: 0, green: 1, blue: 0),
            CIColor(red: 0, green: 0, blue: 1), CIColor(red: 1, green: 1, blue: 0),
            CIColor(red: 0, green: 1, blue: 1), CIColor(red: 1, green: 0, blue: 1)
        ]
        let step = CGFloat(side) / 4.0
        for row in 0..<4 {
            for column in 0..<4 {
                let colour = colours[(row * 4 + column) % colours.count]
                let patch = CIImage(color: colour).cropped(
                    to: CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step,
                               width: step, height: step))
                image = patch.composited(over: image)
            }
        }
        return image.cropped(to: bounds)
    }

    private func pixels(_ image: CIImage) -> [UInt8] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &buf, rowBytes: w * 4, bounds: image.extent,
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buf
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * side + x) * 4
        return Array(bytes[i..<(i + 3)])
    }

    @Test("renders without changing the frame's extent")
    func stretch_preservesExtent() {
        let input = bands()
        let output = StretchEffect().apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test("at zero intensity the frame is returned untouched")
    func stretch_atZeroIntensity_isANoOp() {
        let input = bands()
        let output = StretchEffect(intensity: 0).apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(pixels(output) == pixels(input))
    }

    /// Quadratic ease-in — the smear should not be present on the first frame.
    @Test("at zero progress the effect has not started")
    func stretch_atZeroProgress_isANoOp() {
        let input = bands()
        let output = StretchEffect().apply(to: input, progress: 0, frameIndex: 0)
        #expect(pixels(output) == pixels(input))
    }

    @Test("at full strength the bands are visibly dragged")
    func stretch_smearsTheImage() {
        let input = bands()
        let output = StretchEffect(intensity: 1.0, reach: 1.0)
            .apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(pixels(output) != pixels(input))
    }

    /// The property that separates a stretch from a blur. With a horizontal line at the centre and
    /// full strength, a column of pixels near the line all sample the *same* source point, so they
    /// must be byte-identical to each other — not merely similar, which is all a blur would give.
    @Test("the smear copies pixels rather than averaging them")
    func stretch_producesIdenticalPixelsAlongTheStreak() {
        let input = bands()
        // angle 0 → the line runs horizontally; position 0.5 → through the centre.
        let output = pixels(StretchEffect(intensity: 1.0, angle: 0.0, position: 0.5, reach: 1.0)
            .apply(to: input, progress: 1.0, frameIndex: 0))

        let mid = side / 2
        let reference = pixel(output, mid, mid)
        // Inside the plateau only. reach 1.0 puts the band at 32px with the ramp starting at
        // 0.6 * 32 ≈ 19, so rows within ~19 of the line are fully collapsed; sampling outside
        // that would be testing the deliberate soft edge, not the copy.
        for dy in [-12, -6, 6, 12] {
            #expect(pixel(output, mid, mid + dy) == reference,
                    "row \(mid + dy) differs from the line row — the smear is averaging, not copying")
        }
        // And the streak should not simply be the background: something was actually dragged.
        #expect(reference != [5, 5, 5])
    }

    @Test("ANGLE, POSITION and REACH are all live")
    func stretch_controlsAreLive() {
        let input = bands()
        func render(_ e: StretchEffect) -> [UInt8] {
            pixels(e.apply(to: input, progress: 1.0, frameIndex: 0))
        }
        let base = render(StretchEffect(intensity: 1.0, angle: 0.0, position: 0.5, reach: 0.5))
        #expect(render(StretchEffect(intensity: 1.0, angle: 0.5, position: 0.5, reach: 0.5)) != base)
        #expect(render(StretchEffect(intensity: 1.0, angle: 0.0, position: 0.2, reach: 0.5)) != base)
        #expect(render(StretchEffect(intensity: 1.0, angle: 0.0, position: 0.5, reach: 1.0)) != base)
    }

    /// A wider reach must smear more of the frame. This pins the control's *direction*, which
    /// "they differ" above cannot — a slider wired backwards would still pass that.
    @Test("a wider REACH changes more of the frame")
    func stretch_reachWidensTheAffectedBand() {
        let input = bands()
        let original = pixels(input)

        func changedPixels(reach: Double) -> Int {
            let out = pixels(StretchEffect(intensity: 1.0, angle: 0.0, position: 0.5, reach: reach)
                .apply(to: input, progress: 1.0, frameIndex: 0))
            return stride(from: 0, to: out.count, by: 4).reduce(into: 0) { count, i in
                if out[i] != original[i] || out[i + 1] != original[i + 1] || out[i + 2] != original[i + 2] {
                    count += 1
                }
            }
        }

        let narrow = changedPixels(reach: 0.1)
        let wide = changedPixels(reach: 1.0)
        #expect(wide > narrow, "REACH should widen the smear; narrow \(narrow), wide \(wide)")
    }

    /// Grid-ish effect: the band is measured in pixels, so it must scale with the zoom or the
    /// preview and the export disagree once the user pinches.
    @Test("the smear tracks the frame's zoom")
    func stretch_scalesWithGeometry() {
        let input = bands()
        let effect = StretchEffect(intensity: 1.0, reach: 0.3)
        let unzoomed = effect.apply(to: input, progress: 1.0, frameIndex: 0,
                                    viewportCenter: nil, geometry: .identity)
        let zoomed = effect.apply(to: input, progress: 1.0, frameIndex: 0,
                                  viewportCenter: nil,
                                  geometry: FrameGeometry(scale: 3.0, contentOrigin: .zero))
        #expect(pixels(unzoomed) != pixels(zoomed))
    }

    @Test("STRETCH declares four sliders and no picker")
    func stretch_parameterShape() {
        let params = VisualEffectType.stretch.parameters
        // Four sliders plus the shared BACKGROUND ONLY toggle (2026-08-18).
        #expect(params.count == 5)
        #expect(params.first?.id == EffectParameter.intensityID)
        #expect(params.dropLast().allSatisfy { $0.kind == .slider })
        #expect(params.last?.id == EffectParameter.backgroundOnlyID)
        #expect(VisualEffectType.stretch.colorPickerKind == nil)
    }
}
