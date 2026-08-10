import Testing
import CoreImage
import Foundation
@testable import Enhance

/// LENS is radial chromatic dispersion. Flat fixtures cannot show it — a blurred flat field
/// is still flat — so these render a *structured* fixture to pixels and measure the colour
/// spread the effect introduces, the same way the reference renders were analysed.
struct LensDistortionTests {

    private let ctx = CIContext(options: [.useSoftwareRenderer: true])
    private let side = 120

    /// A bright white square off the centre, on black. A radial per-channel blur smears its
    /// hard edges into coloured fringes, which is the thing to measure.
    private func fixture(width: Int = 120, height: Int = 120) -> CIImage {
        let bg = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let block = CIImage(color: .white)
            .cropped(to: CGRect(x: Double(width) * 0.55, y: Double(height) * 0.55,
                                width: Double(width) * 0.3, height: Double(height) * 0.3))
        return block.composited(over: bg)
    }

    /// Renders to RGBA8 and returns mean per-pixel chroma (max−min of R,G,B, 0…255) plus a
    /// byte fingerprint. Chroma is the dispersion signal: grey pixels have chroma ~0, a
    /// coloured fringe has chroma > 0.
    private func measure(_ image: CIImage) -> (chroma: Double, bytes: [UInt8]) {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(image, toBitmap: &buf, rowBytes: w * 4,
                   bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var total = 0.0
        for p in stride(from: 0, to: buf.count, by: 4) {
            let r = Int(buf[p]), g = Int(buf[p+1]), b = Int(buf[p+2])
            total += Double(max(r, g, b) - min(r, g, b))
        }
        return (total / Double(w * h), buf)
    }

    // MARK: - Identity and determinism

    /// Progress 0 is a pass-through — the quadratic ramp is zero and the effect early-returns.
    /// Byte-identical, not just same-extent, since this is the "off" state.
    @Test func atZeroProgress_isBytewiseIdentity() {
        let input = fixture()
        let effect = LensDistortionEffect(intensity: 1.0, reach: 0.5)
        let out = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(measure(out).bytes == measure(input).bytes)
    }

    /// A visual effect must be a pure function of its inputs — preview, thumbnail and every
    /// GIF frame at the same progress have to agree, and the pause frames must not shimmer.
    @Test func isDeterministic() {
        let input = fixture()
        let effect = LensDistortionEffect(intensity: 0.8, reach: 0.5)
        let a = effect.apply(to: input, progress: 1.0, frameIndex: 3)
        let b = effect.apply(to: input, progress: 1.0, frameIndex: 99)
        #expect(measure(a).bytes == measure(b).bytes, "same progress must render identically regardless of frame index")
    }

    // MARK: - The effect actually disperses

    /// The load-bearing test: at full strength the effect introduces colour a plain blur
    /// would not. On this fixture the input is greyscale (white block on grey), so any
    /// chroma in the output is dispersion the effect created.
    @Test func atFullStrength_introducesChroma() {
        let input = fixture()
        let inputChroma = measure(input).chroma
        let out = LensDistortionEffect(intensity: 1.0, reach: 1.0).apply(to: input, progress: 1.0, frameIndex: 0)
        let outChroma = measure(out).chroma
        #expect(inputChroma < 1.0, "fixture should be near-greyscale, was \(inputChroma)")
        #expect(outChroma > inputChroma + 2.0, "expected visible dispersion, chroma went \(inputChroma) → \(outChroma)")
    }

    /// AMOUNT is a live control across its whole range: low, mid and high settings each
    /// produce a distinct, non-trivial result.
    ///
    /// Deliberately *not* asserting that chroma rises monotonically with intensity — it does
    /// not, and that is correct. Mean per-pixel chroma peaks around the middle of the range
    /// and falls toward the top, because past a point the streaks spread so far they dilute:
    /// max dispersion is a wide, low-saturation wash rather than a saturated fringe, which is
    /// exactly what the reference showed at full strength. Measuring "how much the output
    /// differs from the original" captures the live-ness without over-claiming saturation.
    @Test func intensityIsALiveControlAcrossItsRange() {
        let input = fixture()
        let inputBytes = measure(input).bytes

        func changedPixels(_ intensity: Double) -> Int {
            let bytes = measure(LensDistortionEffect(intensity: intensity, reach: 1.0)
                .apply(to: input, progress: 1.0, frameIndex: 0)).bytes
            var n = 0
            for i in stride(from: 0, to: bytes.count, by: 4)
            where bytes[i] != inputBytes[i] || bytes[i+1] != inputBytes[i+1] || bytes[i+2] != inputBytes[i+2] { n += 1 }
            return n
        }

        let low = changedPixels(0.25), mid = changedPixels(0.5), high = changedPixels(1.0)
        // Each setting genuinely processes the image…
        for (label, n) in [("low", low), ("mid", mid), ("high", high)] {
            #expect(n > 20, "\(label) intensity barely changed the image (\(n) px)")
        }
        // …and the settings are not collapsed onto one output — the knob spans a range.
        #expect(low != mid && mid != high, "intensities produced identical outputs: \(low)/\(mid)/\(high)")
    }

    /// REACH is a real, independent control: widening it lets the dispersion fill more of the
    /// frame, so more of the image differs from the original. If REACH did nothing the two
    /// renders would be identical.
    @Test func reachChangesHowMuchOfTheFrameIsAffected() {
        let input = fixture()
        let narrow = measure(LensDistortionEffect(intensity: 1.0, reach: 0.0).apply(to: input, progress: 1.0, frameIndex: 0)).bytes
        let wide = measure(LensDistortionEffect(intensity: 1.0, reach: 1.0).apply(to: input, progress: 1.0, frameIndex: 0)).bytes

        var changed = 0
        for i in stride(from: 0, to: narrow.count, by: 4) where narrow[i] != wide[i] || narrow[i+1] != wide[i+1] || narrow[i+2] != wide[i+2] {
            changed += 1
        }
        #expect(changed > (narrow.count / 4) / 20, "reach 0 vs 1 barely differ (\(changed) px) — REACH is inert")
    }

    // MARK: - Geometry

    /// Extent preservation is asserted generically over every effect; this pins the two
    /// non-square aspect ratios specifically, since the reach mask is built from the frame
    /// diagonal and a bad radius could grow the extent on a rectangle only.
    @Test func preservesExtentOnEveryAspect() {
        let effect = LensDistortionEffect(intensity: 1.0, reach: 0.6)
        for size in [(120, 120), (72, 120), (120, 72)] {
            let input = fixture(width: size.0, height: size.1)
            let out = effect.apply(to: input, progress: 1.0, frameIndex: 0)
            #expect(out.extent == input.extent, "aspect \(size) grew to \(out.extent)")
        }
    }

    /// The face variant hands the effect a `viewportCenter`. An off-centre centre must not
    /// grow the extent — the exact bug class the generic off-centre test guards, pinned here
    /// against a centre near the corner where the radial filters reach furthest.
    @Test func offCentreViewportPreservesExtent() {
        let input = fixture()
        let out = LensDistortionEffect(intensity: 1.0, reach: 1.0)
            .apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: CGPoint(x: 10, y: 110))
        #expect(out.extent == input.extent)
    }
}
