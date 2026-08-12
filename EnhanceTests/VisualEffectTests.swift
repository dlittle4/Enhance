import Testing
import CoreImage
import UIKit
import SwiftUI
@testable import Enhance

struct VisualEffectTests {
    
    /// Creates a 100x100 solid red CIImage for testing effects.
    private func makeTestImage() -> CIImage {
        CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    
    // MARK: - ChromaticAberrationEffect
    
    @Test func chroma_atZeroProgress_returnsUnchanged() {
        let effect = ChromaticAberrationEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        
        #expect(output.extent == input.extent)
    }
    
    @Test func chroma_atFullProgress_producesOutput() {
        let effect = ChromaticAberrationEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 19)
        
        #expect(output.extent.width > 0)
        #expect(output.extent.height > 0)
    }
    
    @Test func chroma_lowProgress_skipsSubPixelShifts() {
        let effect = ChromaticAberrationEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.05, frameIndex: 1)
        #expect(output.extent == input.extent)
    }
    
    // MARK: - HalftoneEffect
    
    @Test func halftone_atZeroProgress_returnsUnchanged() {
        let effect = HalftoneEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        
        #expect(output.extent == input.extent)
    }
    
    @Test func halftone_atFullProgress_producesOutput() {
        let effect = HalftoneEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 19)
        
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }
    
    // MARK: - FisheyeEffect
    
    @Test func fisheye_atZeroProgress_returnsUnchanged() {
        let effect = FisheyeEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        
        #expect(output.extent == input.extent)
    }
    
    @Test func fisheye_atFullProgress_producesOutput() {
        let effect = FisheyeEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 19)
        
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    @Test func fisheye_smallVsLargeSize_producesDifferentResults() {
        let ctx = CIContext()
        let input = makeTestImage()

        let small = FisheyeEffect(intensity: 0.8, size: 0.1)
        let large = FisheyeEffect(intensity: 0.8, size: 1.0)

        let outSmall = small.apply(to: input, progress: 1.0, frameIndex: 0)
        let outLarge = large.apply(to: input, progress: 1.0, frameIndex: 0)

        guard let cgSmall = ctx.createCGImage(outSmall, from: outSmall.extent),
              let cgLarge = ctx.createCGImage(outLarge, from: outLarge.extent) else {
            Issue.record("Failed to render CGImage")
            return
        }
        #expect(cgSmall.width > 0)
        #expect(cgLarge.width > 0)
    }

    // MARK: - SwirlEffect

    @Test func swirl_atZeroProgress_returnsUnchanged() {
        let effect = SwirlEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func swirl_atFullProgress_producesOutput() {
        let effect = SwirlEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 19)
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    @Test func swirl_respectsViewportCenter() {
        let ctx = CIContext()
        let input = makeTestImage()
        let effect = SwirlEffect(intensity: 0.8)
        let centered = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: CGPoint(x: 50, y: 50))
        let offset = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: CGPoint(x: 10, y: 10))
        guard let cgCentered = ctx.createCGImage(centered, from: centered.extent),
              let cgOffset = ctx.createCGImage(offset, from: offset.extent) else {
            Issue.record("Failed to render CGImage")
            return
        }
        #expect(cgCentered.width > 0)
        #expect(cgOffset.width > 0)
    }

    // MARK: - PixelateEffect

    /// Pixelate's progress is inverted relative to other effects: it starts fully
    /// blocky and resolves to sharp, so progress 0 is maximum pixelation and
    /// progress 1 is the pass-through. See LEARNINGS 2026-03-11.
    @Test func pixelate_atZeroProgress_isFullyPixelated() {
        let effect = PixelateEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output !== input)
    }

    @Test func pixelate_atFullProgress_returnsUnchanged() {
        let effect = PixelateEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func pixelate_atFullProgress_producesOutput() {
        let effect = PixelateEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 19)
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    @Test func pixelate_respectsViewportCenter() {
        let ctx = CIContext()
        let input = makeTestImage()
        let effect = PixelateEffect(intensity: 0.8)
        let centered = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: CGPoint(x: 50, y: 50))
        let offset = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: CGPoint(x: 10, y: 10))
        guard let cgCentered = ctx.createCGImage(centered, from: centered.extent),
              let cgOffset = ctx.createCGImage(offset, from: offset.extent) else {
            Issue.record("Failed to render CGImage")
            return
        }
        #expect(cgCentered.width > 0)
        #expect(cgOffset.width > 0)
    }

    // MARK: - Extent preservation

    /// Every effect must return the extent it was given.
    ///
    /// Distortion filters like CIBumpDistortion and CITwirlDistortion grow the extent
    /// past their input. An effect that returns a larger image letterboxes the editor
    /// canvas — whose scroll geometry is configured once from the source image — and
    /// changes the frame dimensions in the GIF pipeline. Fisheye and Swirl both had this
    /// bug; it was visible on device as a black band above the preview.
    @Test func allEffects_preserveInputExtent() {
        let input = makeTestImage()
        for type in VisualEffectType.allCases {
            let effect = type.effect(intensity: 1.0)
            for progress in [CGFloat(0.5), 1.0] {
                let output = effect.apply(to: input, progress: progress, frameIndex: 7)
                #expect(
                    output.extent == input.extent,
                    "\(type.rawValue) at progress \(progress) returned \(output.extent) for input \(input.extent)"
                )
            }
        }
    }

    /// Same guarantee through the viewport-centred entry point, which is the one the
    /// live preview uses — an off-centre distortion centre grows the extent asymmetrically.
    @Test func allEffects_preserveInputExtentWithOffsetViewportCentre() {
        let input = makeTestImage()
        let offCentre = CGPoint(x: 15, y: 85)
        for type in VisualEffectType.allCases {
            let effect = type.effect(intensity: 1.0)
            // Both ends of the ramp: some effects early-return at one of them (pixelate
            // is a pass-through at 1.0), which is how it slipped past an earlier version
            // of this test that only checked full progress.
            for progress in [CGFloat(0.5), 1.0] {
                let output = effect.apply(to: input, progress: progress, frameIndex: 7, viewportCenter: offCentre)
                #expect(
                    output.extent == input.extent,
                    "\(type.rawValue) off-centre at progress \(progress) returned \(output.extent)"
                )
            }
        }
    }

    // MARK: - VisualEffectType enum
    
    /// Deliberately walks `allCases`, not `selectable`: retired effects are hidden
    /// from the picker but still compiled, and this is what stops them rotting while
    /// they're out of the UI. If a retired effect breaks, it should fail here.
    @Test func visualEffectType_allCasesProduceOutput() {
        let input = makeTestImage()
        let ctx = CIContext()

        for type in VisualEffectType.allCases {
            let effect = type.effect()
            let output = effect.apply(to: input, progress: 0.5, frameIndex: 10)
            let cgImage = ctx.createCGImage(output, from: output.extent)
            #expect(cgImage != nil)
        }
    }

    // MARK: - Retirement

    @Test func selectable_excludesRetiredAndKeepsTheRest() {
        let selectable = VisualEffectType.selectable

        #expect(!selectable.isEmpty)
        #expect(selectable.count == VisualEffectType.allCases.count - VisualEffectType.retired.count)
        for retired in VisualEffectType.retired {
            #expect(!selectable.contains(retired))
        }
        for type in selectable {
            #expect(!type.isRetired)
        }
    }

    /// Retiring an effect must not disturb the order of the ones still on show —
    /// the carousel's ordering comes straight from this list.
    @Test func selectable_preservesDeclarationOrder() {
        let selectable = VisualEffectType.selectable
        let expected = VisualEffectType.allCases.filter { !$0.isRetired }
        #expect(selectable == expected)
    }

    /// `supportsColorPicker` is derived from `colorPickerKind`; the two must never
    /// drift apart.
    @Test func colorPicker_flagAgreesWithKind() {
        for type in VisualEffectType.allCases {
            #expect(type.supportsColorPicker == (type.colorPickerKind != nil))
        }
    }

    /// Every visible effect claiming a picker slot must be one EditorView knows how
    /// to render. Fails loudly when a new effect claims the picker without the view
    /// gaining a matching branch. Duotone still claims `.tintColor` but stays retired.
    @Test func colorPicker_visibleConsumersAreTheExpectedSet() {
        #expect(VisualEffectType.duotone.isRetired)
        let visible = Set(VisualEffectType.selectable.filter(\.supportsColorPicker))
        #expect(visible == [.gradientMap, .coloredEdges])
    }

    // MARK: - Required filter names

    /// `applyingFilter` fails *silently* on an unknown filter name — it returns an
    /// unchanged image rather than throwing — so a typo would surface as a subtly
    /// wrong look rather than a test failure. This is the cheapest guard available.
    @Test func requiredFilterNames_exist() {
        let names = [
            "CIColorCubeWithColorSpace", "CIEdges", "CIMaximumComponent",
            "CIGammaAdjust", "CIColorMatrix", "CIAdditionCompositing",
            "CIDither", "CIColorPosterize", "CIDissolveTransition",
            "CIColorControls"
        ]
        for name in names {
            #expect(CIFilter(name: name) != nil, "missing CIFilter: \(name)")
        }
    }

    // MARK: - Gradient Map

    @Test func gradientMap_atZeroProgress_returnsUnchanged() {
        let effect = GradientMapEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func gradientMap_atFullProgress_producesOutput() {
        let effect = GradientMapEffect(intensity: 1.0)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(CIContext().createCGImage(output, from: output.extent) != nil)
    }

    /// An arbitrary user-chosen ramp must render.
    @Test func gradientMap_withCustomStopsRenders() {
        let ctx = CIContext()
        let input = makeTestImage()
        let cases = [
            GradientStops(dark: .blue, mid: .green, light: .yellow),
            GradientStops(dark: .black, mid: .gray, light: .white)
        ]
        for stops in cases {
            let effect = GradientMapEffect(intensity: 1.0, stops: stops)
            let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
            #expect(ctx.createCGImage(output, from: output.extent) != nil)
        }
    }

    /// Stops must span the full luminance range so a lookup anywhere in [0,1] is
    /// bracketed by two stops.
    @Test func gradientStops_resolvedSpanZeroToOne() {
        let resolved = GradientStops.default.resolved
        #expect(resolved.count == 3)
        #expect(resolved.first?.location == 0.0)
        #expect(resolved.last?.location == 1.0)
        let locations = resolved.map(\.location)
        #expect(locations == locations.sorted())
    }

    /// Out-of-range lookups must clamp rather than extrapolate or crash.
    @Test func gradientStops_colorClampsOutOfRangeInput() {
        let stops = GradientStops.default
        #expect(stops.color(at: -0.5) == stops.color(at: 0.0))
        #expect(stops.color(at: 1.5) == stops.color(at: 1.0))
    }

    /// ColorPicker can hand back Display P3 colours whose sRGB components fall
    /// outside 0–1. Unclamped, those would corrupt the colour cube.
    @Test func gradientStops_resolvedComponentsAreClampedToUnitRange() {
        let wide = GradientStops(
            dark: Color(.displayP3, red: 1.0, green: 0.0, blue: 0.0),
            mid: Color(.displayP3, red: 0.0, green: 1.0, blue: 0.0),
            light: Color(.displayP3, red: 0.0, green: 0.0, blue: 1.0)
        )
        for stop in wide.resolved {
            #expect(stop.rgb.r >= 0 && stop.rgb.r <= 1)
            #expect(stop.rgb.g >= 0 && stop.rgb.g <= 1)
            #expect(stop.rgb.b >= 0 && stop.rgb.b <= 1)
        }
    }

    /// The cube cache is keyed on resolved RGB, so equal stops must share a key and
    /// different stops must not — otherwise dragging the intensity slider would
    /// rebuild a 32³ lattice on every frame.
    @Test func gradientStops_cacheKeyIsStableAndDistinct() {
        let a = GradientStops.default
        let b = GradientStops.default
        #expect(a.cacheKey == b.cacheKey)

        var c = GradientStops.default
        c.light = .red
        #expect(a.cacheKey != c.cacheKey)

        var d = GradientStops.default
        d.mid = .cyan
        #expect(a.cacheKey != d.cacheKey)
    }

    // MARK: - Colored Edges

    @Test func coloredEdges_atZeroProgress_returnsUnchanged() {
        let effect = ColoredEdgesEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func coloredEdges_atFullProgress_producesOutput() {
        let effect = ColoredEdgesEffect(intensity: 1.0, color: .blue)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(CIContext().createCGImage(output, from: output.extent) != nil)
    }

    /// CIEdges is a convolution: without `clampedToExtent()` before it and a crop
    /// after, it samples off-image and paints a false border on all four sides.
    /// This fails if either is dropped.
    @Test func coloredEdges_outputExtentMatchesInput() {
        let effect = ColoredEdgesEffect(intensity: 1.0)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    // MARK: - Dither

    @Test func dither_atZeroProgress_returnsUnchanged() {
        let effect = DitherEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func dither_atFullProgress_producesOutput() {
        let effect = DitherEffect(intensity: 1.0)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(CIContext().createCGImage(output, from: output.extent) != nil)
    }

    /// Cell size scales with the frame's zoom so the stipple stays the same size
    /// relative to the subject. Without this the GIF pattern is fixed in output pixels
    /// and reads as a static overlay the image slides beneath.
    @Test func dither_scalesCellWithFrameScale() {
        let ctx = CIContext()
        let input = makeTestImage()
        let effect = DitherEffect(intensity: 1.0, size: 0.5)
        for scale in [CGFloat(1), 2, 4, 8] {
            let output = effect.apply(
                to: input, progress: 1.0, frameIndex: 0,
                viewportCenter: nil, geometry: FrameGeometry(scale: scale)
            )
            #expect(output.extent == input.extent, "extent drifted at \(scale)x")
            #expect(ctx.createCGImage(output, from: output.extent) != nil)
        }
    }

    /// Phase alignment: shifting the content origin must not change the output extent
    /// or leave uncovered strips at the edges. Scaling the cell alone is not enough,
    /// because the animation pans as it zooms.
    @Test func dither_phaseAlignsToContentOriginWithoutGaps() {
        let ctx = CIContext()
        let input = makeTestImage()
        let effect = DitherEffect(intensity: 1.0, size: 0.8)
        for offset in [CGFloat(0), 3, 7.5, 19, -11] {
            let geometry = FrameGeometry(scale: 4.0, contentOrigin: CGPoint(x: offset, y: offset * 0.5))
            let output = effect.apply(
                to: input, progress: 1.0, frameIndex: 0,
                viewportCenter: nil, geometry: geometry
            )
            #expect(output.extent == input.extent, "extent drifted at offset \(offset)")
            #expect(ctx.createCGImage(output, from: output.extent) != nil, "render failed at offset \(offset)")
        }
    }

    /// Decisive check on the phase mechanism. With `size` 1.0 and scale 1.0 the cell is
    /// exactly 8pt, so shifting the content origin by one whole cell must land the grid
    /// on the same lattice and render byte-identical output, while a half-cell shift
    /// must not. This is what "the grid follows the content" actually means, and it
    /// cannot be verified by extent or non-nil checks.
    @Test func dither_phaseIsPeriodicInCellSize() throws {
        let input = gradientTestImage()
        let effect = DitherEffect(intensity: 1.0, size: 1.0)   // baseCell = 8
        let cell: CGFloat = 8

        func render(originX: CGFloat) throws -> Data {
            let out = effect.apply(
                to: input, progress: 1.0, frameIndex: 0,
                viewportCenter: nil,
                geometry: FrameGeometry(scale: 1.0, contentOrigin: CGPoint(x: originX, y: 0))
            )
            let ctx = CIContext()
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        let base = try render(originX: 0)
        let oneCell = try render(originX: cell)
        let halfCell = try render(originX: cell / 2)

        #expect(base == oneCell, "a whole-cell shift should reproduce the same lattice")
        #expect(base != halfCell, "a half-cell shift should move the lattice")
    }

    /// A luminance ramp, so the dither has something to stipple. A solid colour
    /// posterises flat and would make the periodicity test pass trivially.
    // MARK: - Control audit: MOTION BLUR angle, SWIRL size

    /// The default must reproduce the look these effects shipped with. Exposing a hidden
    /// constant is only safe if the midpoint of the new control *is* the old constant —
    /// otherwise every existing GIF silently re-renders differently on the next edit.

    @Test func motionBlur_defaultAngle_reproducesTheShipped45Degrees() throws {
        let input = gradientTestImage()
        let ctx = CIContext()

        func png(_ img: CIImage) throws -> Data {
            let cg = try #require(ctx.createCGImage(img, from: img.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        let viaControl = MotionBlurEffect(intensity: 0.8, angle: 0.5)
            .apply(to: input, progress: 1.0, frameIndex: 0)

        // The pre-audit implementation, inline: radius ramp unchanged, angle hardcoded.
        let t = min(1.0, 1.0 * 1.2)
        let legacy = input.applyingFilter("CIMotionBlur", parameters: [
            kCIInputRadiusKey: CGFloat(max(2.0, 30.0 * 0.8)) * t * t,
            kCIInputAngleKey: CGFloat.pi / 4
        ]).cropped(to: input.extent)

        #expect(try png(viaControl) == png(legacy),
                "angle 0.5 must still be the 45° this effect shipped with")
    }

    @Test func motionBlur_angleIsLiveAcrossItsRange() throws {
        let input = gradientTestImage()
        let ctx = CIContext()

        func png(_ angle: Double) throws -> Data {
            let out = MotionBlurEffect(intensity: 0.8, angle: angle)
                .apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        // Assert the control is *live across its range*, not that any two positions are
        // byte-identical. The endpoints are one half-turn apart and so are the same
        // direction in principle — but they are reached by different arithmetic, and
        // asserting equality there tests CIMotionBlur's internal symmetry rather than
        // this control. That assertion passed in isolation and failed in a full run.
        #expect(try png(0.0) != png(0.5), "the low end must differ from the default")
        #expect(try png(0.5) != png(0.75), "the high end must differ from the default")
        #expect(try png(0.25) != png(0.75), "quarter turns apart must differ")
    }

    @Test func swirl_defaultSize_reproducesTheShipped040Radius() throws {
        let input = gradientTestImage()
        let ctx = CIContext()

        func png(_ img: CIImage) throws -> Data {
            let cg = try #require(ctx.createCGImage(img, from: img.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        let viaControl = SwirlEffect(intensity: 0.8, size: 0.5)
            .apply(to: input, progress: 1.0, frameIndex: 0)

        let legacy = input.applyingFilter("CITwirlDistortion", parameters: [
            kCIInputCenterKey: CIVector(x: input.extent.midX, y: input.extent.midY),
            kCIInputRadiusKey: max(input.extent.width, input.extent.height) * 0.4,
            kCIInputAngleKey: CGFloat.pi * CGFloat(max(0.1, 2.0 * 0.8)) * 1.0
        ]).cropped(to: input.extent)

        #expect(try png(viaControl) == png(legacy),
                "size 0.5 must still be the 0.4 radius fraction this effect shipped with")
    }

    @Test func swirl_sizeIsLiveAcrossItsRange() throws {
        let input = gradientTestImage()
        let ctx = CIContext()

        func png(_ size: Double) throws -> Data {
            let out = SwirlEffect(intensity: 0.8, size: size)
                .apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        #expect(try png(0.0) != png(0.5), "a tight vortex must differ from the default")
        #expect(try png(0.5) != png(1.0), "a wide vortex must differ from the default")
    }

    // MARK: - Control audit: HALFTONE, CHROMA SHIFT, HEAT HAZE

    @Test func chromaShift_defaultAngle_reproducesTheShippedDiagonal() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ img: CIImage) throws -> Data {
            let cg = try #require(ctx.createCGImage(img, from: img.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        let viaControl = ChromaticAberrationEffect(intensity: 0.8, angle: 0.5)
            .apply(to: input, progress: 1.0, frameIndex: 0)
        let legacy = ChromaticAberrationEffect(intensity: 0.8)
            .apply(to: input, progress: 1.0, frameIndex: 0)

        #expect(try png(viaControl) == png(legacy),
                "angle 0.5 must keep both the direction and the magnitude that shipped")
    }

    @Test func chromaShift_angleIsLiveAcrossItsRange() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ a: Double) throws -> Data {
            let out = ChromaticAberrationEffect(intensity: 0.8, angle: a)
                .apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(0.0) != png(0.5))
        #expect(try png(0.5) != png(0.85))
    }

    @Test func halftone_defaultsReproduceTheShippedScreen() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ img: CIImage) throws -> Data {
            let cg = try #require(ctx.createCGImage(img, from: img.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        let viaControl = HalftoneEffect(intensity: 0.8, sharpness: 0.5, angle: 0.5)
            .apply(to: input, progress: 1.0, frameIndex: 0)

        // The pre-audit implementation: sharpness pinned to 0.7, inputAngle never set.
        let w: CGFloat = 2.0 + (max(4.0, 24.0 * 0.8) - 2.0) * 1.0
        let legacy = input.applyingFilter("CICMYKHalftone", parameters: [
            kCIInputCenterKey: CIVector(x: input.extent.midX, y: input.extent.midY),
            kCIInputWidthKey: w,
            kCIInputSharpnessKey: 0.7
        ])

        #expect(try png(viaControl) == png(legacy),
                "sharpness/angle at 0.5 must reproduce 0.7 and the filter's default angle")
    }

    @Test func halftone_sharpnessAndAngleAreBothLive() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ sharp: Double, _ ang: Double) throws -> Data {
            let out = HalftoneEffect(intensity: 0.8, sharpness: sharp, angle: ang)
                .apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(0.0, 0.5) != png(1.0, 0.5), "SHARPNESS must change the dots")
        #expect(try png(0.5, 0.0) != png(0.5, 1.0), "ANGLE must rotate the screen")
    }

    @Test func heatHaze_defaultsReproduceTheShippedShimmer() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ img: CIImage) throws -> Data {
            let cg = try #require(ctx.createCGImage(img, from: img.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }

        // frequency 0.5 -> 0.015 and speed 0.5 -> 0.35, the two shipped constants.
        let viaControl = HeatHazeEffect(intensity: 0.8, frequency: 0.5, speed: 0.5)
            .apply(to: input, progress: 1.0, frameIndex: 7)
        let legacy = HeatHazeEffect(intensity: 0.8)
            .apply(to: input, progress: 1.0, frameIndex: 7)

        #expect(try png(viaControl) == png(legacy))
    }

    @Test func heatHaze_frequencyAndSpeedAreBothLive() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ freq: Double, _ speed: Double, frame: Int) throws -> Data {
            let out = HeatHazeEffect(intensity: 1.0, frequency: freq, speed: speed)
                .apply(to: input, progress: 1.0, frameIndex: frame)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(0.0, 0.5, frame: 3) != png(1.0, 0.5, frame: 3),
                "FREQUENCY must change the wave scale")
        // SPEED only shows up across frames — at frame 0 the phase is 0 whatever it is.
        #expect(try png(0.5, 0.0, frame: 5) != png(0.5, 1.0, frame: 5),
                "SPEED must change how far the pattern has travelled by frame 5")
        #expect(try png(0.5, 0.0, frame: 0) == png(0.5, 1.0, frame: 0),
                "at frame 0 the phase is zero regardless of speed")
    }

    // MARK: - Control audit: DITHER LEVELS, RAINBOW SPEED, GRADIENT MIDPOINT

    @Test func dither_defaultLevels_reproducesTheShippedPosterisation() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ e: DitherEffect) throws -> Data {
            let out = e.apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(DitherEffect(intensity: 1.0, size: 0.6, levels: 0.5))
                == png(DitherEffect(intensity: 1.0, size: 0.6)),
                "levels 0.5 must still bottom out at the 3 levels that shipped")
    }

    /// The point of splitting LEVELS out of INTENSITY: heavy stipple at many levels, and
    /// light stipple at few, were both unreachable when one slider drove both.
    @Test func dither_levelsIsIndependentOfIntensity() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ intensity: Double, _ levels: Double) throws -> Data {
            let out = DitherEffect(intensity: intensity, size: 0.6, levels: levels)
                .apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(1.0, 0.0) != png(1.0, 1.0),
                "at fixed amplitude, LEVELS must still change the posterisation")
        #expect(try png(0.4, 0.9) != png(1.0, 0.9),
                "at fixed levels, INTENSITY must still change the stipple")
    }

    @Test func rainbow_defaultSpeed_reproducesTheShippedRate() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ e: RainbowGradientEffect, frame: Int) throws -> Data {
            let out = e.apply(to: input, progress: 1.0, frameIndex: frame)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(RainbowGradientEffect(intensity: 0.8, speed: 0.5), frame: 9)
                == png(RainbowGradientEffect(intensity: 0.8), frame: 9))
    }

    @Test func rainbow_speedChangesHowFarTheRingsHaveTravelled() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ speed: Double, frame: Int) throws -> Data {
            let out = RainbowGradientEffect(intensity: 0.8, speed: speed)
                .apply(to: input, progress: 1.0, frameIndex: frame)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(0.0, frame: 8) != png(1.0, frame: 8))
        #expect(try png(0.0, frame: 0) == png(1.0, frame: 0),
                "frame 0 has no phase to scale, whatever the speed")
    }

    @Test func gradientMap_defaultMidpoint_reproducesTheShippedRamp() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ e: GradientMapEffect) throws -> Data {
            let out = e.apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(GradientMapEffect(intensity: 1.0, stops: .default, midpoint: 0.5))
                == png(GradientMapEffect(intensity: 1.0, stops: .default)),
                "midpoint 0.5 must solve to an exponent of 1, i.e. the identity")
    }

    /// The cube is memoised on the stop colours. A midpoint changes the cube's contents
    /// without changing any stop, so a key that ignored it would serve a stale cube for
    /// every midpoint after the first — the effect would silently stop responding.
    @Test func gradientMap_midpointIsNotSwallowedByTheCubeCache() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ midpoint: Double) throws -> Data {
            let out = GradientMapEffect(intensity: 1.0, stops: .default, midpoint: midpoint)
                .apply(to: input, progress: 1.0, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        // Deliberately renders the default first, so a colour-only key would already be
        // warm and would return that cube for both of the next two.
        _ = try png(0.5)
        #expect(try png(0.05) != png(0.5), "a low midpoint must lift the shadows")
        #expect(try png(0.95) != png(0.5), "a high midpoint must deepen them")
        #expect(try png(0.05) != png(0.95))
    }

    @Test func gradientMap_cacheKeyDistinguishesExponents() {
        let stops = GradientStops.default
        #expect(stops.cacheKey(exponent: 1) != stops.cacheKey(exponent: 2))
        #expect(stops.cacheKey(exponent: 1) == stops.cacheKey)
    }

    // MARK: - Control audit: PIXELATE SHAPE

    @Test func pixelate_defaultShape_isTheSquareThatShipped() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ e: PixelateEffect) throws -> Data {
            let out = e.apply(to: input, progress: 0.2, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(PixelateEffect(intensity: 0.8, shape: .square))
                == png(PixelateEffect(intensity: 0.8)))
    }

    @Test func pixelate_hexShapeRendersDifferently() throws {
        let input = gradientTestImage()
        let ctx = CIContext()
        func png(_ shape: PixelShape) throws -> Data {
            let out = PixelateEffect(intensity: 0.8, shape: shape)
                .apply(to: input, progress: 0.2, frameIndex: 0)
            let cg = try #require(ctx.createCGImage(out, from: out.extent))
            return try #require(UIImage(cgImage: cg).pngData())
        }
        #expect(try png(.square) != png(.hex))
    }

    /// Both filters must exist on the device runtime — `applyingFilter` fails *silently* on an
    /// unknown name, so a typo would ship as "SHAPE does nothing" rather than as a crash.
    @Test func pixelShape_filterNamesExist() {
        for shape in PixelShape.allCases {
            #expect(CIFilter(name: shape.filterName) != nil, "\(shape.rawValue) -> \(shape.filterName)")
        }
    }

    /// Storing the shape as a case index would make the enum's *order* load-bearing. This
    /// asserts the values are carried by identity, so a future reorder cannot silently
    /// reinterpret saved state. See LEARNINGS 2026-08-10.
    @Test func pixelShape_isIdentifiedByNameNotOrdinal() {
        #expect(PixelShape(rawValue: "SQUARE") == .square)
        #expect(PixelShape(rawValue: "HEX") == .hex)
        #expect(PixelShape.allCases.count == 2)
    }

    // MARK: - SliceShiftEffect

    private func sliceFixture() -> CIImage {
        // Vertical stripes, so a *horizontal* displacement is visible. A gradient that
        // varies only along y would render identically however far the bands slide.
        CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
            .applyingFilter("CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                "inputPoint1": CIVector(x: 96, y: 0),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1)
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
    }

    private func slicePNG(_ effect: SliceShiftEffect,
                          progress: CGFloat = 1.0,
                          frame: Int = 0,
                          geometry: FrameGeometry = .identity) throws -> Data {
        let out = effect.apply(to: sliceFixture(), progress: progress, frameIndex: frame,
                               viewportCenter: nil, geometry: geometry)
        let cg = try #require(CIContext().createCGImage(out, from: out.extent))
        return try #require(UIImage(cgImage: cg).pngData())
    }

    @Test func sliceShift_atZeroProgress_returnsUnchanged() {
        let input = sliceFixture()
        let output = SliceShiftEffect().apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func sliceShift_atFullProgress_displacesBands() throws {
        let clean = try #require(CIContext().createCGImage(sliceFixture(), from: sliceFixture().extent))
        let cleanPNG = try #require(UIImage(cgImage: clean).pngData())
        #expect(try slicePNG(SliceShiftEffect(intensity: 0.8)) != cleanPNG)
    }

    /// All three controls must be independently live, or they are one control wearing
    /// three labels.
    @Test func sliceShift_amountSizeAndJitterAreAllLive() throws {
        #expect(try slicePNG(SliceShiftEffect(intensity: 0.2, size: 0.5, jitter: 0.5))
                != slicePNG(SliceShiftEffect(intensity: 1.0, size: 0.5, jitter: 0.5)),
                "AMOUNT must change the displacement")
        #expect(try slicePNG(SliceShiftEffect(intensity: 0.8, size: 0.0, jitter: 0.5))
                != slicePNG(SliceShiftEffect(intensity: 0.8, size: 1.0, jitter: 0.5)),
                "SIZE must change the band height")
        #expect(try slicePNG(SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 0.0))
                != slicePNG(SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 1.0)),
                "JITTER must change the pattern")
    }

    /// At jitter 0 the displacement is a pure alternating comb, so it must not depend on
    /// the frame — the bands hold still. Any frame dependence there would mean the comb
    /// is picking up hash noise it should not.
    @Test func sliceShift_withoutJitter_isFrameIndependent() throws {
        let effect = SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 0.0)
        #expect(try slicePNG(effect, frame: 0) == slicePNG(effect, frame: 11))
    }

    /// With jitter the pattern is meant to flicker across frames — that is the whole
    /// reason this effect earns its place, since almost nothing else in the app animates
    /// between frames.
    @Test func sliceShift_withJitter_changesBetweenFrames() throws {
        let effect = SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 1.0)
        #expect(try slicePNG(effect, frame: 0) != slicePNG(effect, frame: 11))
    }

    /// Reproducibility: the same frame must render identically every time, or GIF playback
    /// and the live preview disagree. Seeded from the band and frame indices, never random().
    @Test func sliceShift_isDeterministic() throws {
        let effect = SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 1.0)
        #expect(try slicePNG(effect, frame: 7) == slicePNG(effect, frame: 7))
    }

    /// Grid-effect contract, same property DITHER is held to: band height scales with the
    /// zoom, so the export matches the magnified preview instead of showing finer bands.
    @Test func sliceShift_scalesBandHeightWithFrameScale() throws {
        let effect = SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 0.0)
        #expect(try slicePNG(effect, geometry: FrameGeometry(scale: 1.0))
                != slicePNG(effect, geometry: FrameGeometry(scale: 3.0)))
    }

    /// The other half of the grid contract, and note the period is **two** bands, not one.
    ///
    /// DITHER's equivalent test uses a one-cell period because its lattice repeats every
    /// cell. This comb alternates direction, so a one-band shift of the content moves every
    /// band onto the opposite parity and *inverts* the pattern — a correct result that looks
    /// like a failure. Two bands is the true period. Do not "fix" the effect to make a
    /// one-band assertion pass; that would mean the parity had stopped tracking the content.
    @Test func sliceShift_phaseIsPeriodicInTwoBands() throws {
        // size 0.5 -> 22pt bands at scale 1.
        let effect = SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 0.0)
        let band: CGFloat = 22.0

        func at(_ dy: CGFloat) throws -> Data {
            try slicePNG(effect, geometry: FrameGeometry(scale: 1, contentOrigin: CGPoint(x: 0, y: dy)))
        }

        let base = try at(0)
        #expect(try base == at(band * 2), "two bands is the comb's period")
        #expect(try base != at(band), "one band inverts the comb rather than repeating it")
        #expect(try base != at(band / 2), "a half-band shift should move the bands")
    }

    // MARK: - Face pass -> visual pass handoff

    /// Face effects composite their glow additively, which pushes the brightest pixels past
    /// 1.0. That is invisible when rendered straight to screen, because the rasteriser clamps
    /// on the way out — but a visual effect chained after it does arithmetic on those values.
    /// SLICE SHIFT's source-over composite turned over-range pixels **black**, so laser eyes
    /// rendered as black blobs in the preview while the GIF — which rasterises between the two
    /// stages, and so clamps for free — was correct.
    ///
    /// Asserts the property rather than a coordinate: the bands move, so any fixed pixel is a
    /// coin flip. Compares the mean colour of the whole frame with and without the clamp.
    @Test func additivelyBlownInput_goesDarkThroughSliceShift_untilClamped() throws {
        let ctx = CIContext()
        let base = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))

        // A deliberately over-range patch, the way stacked additive glow layers end up.
        let hot = CIImage(color: CIColor(red: 4, green: 0, blue: 0))
            .cropped(to: CGRect(x: 24, y: 24, width: 48, height: 48))
        let blown = try #require(CIFilter(name: "CIAdditionCompositing", parameters: [
            kCIInputImageKey: hot, kCIInputBackgroundImageKey: base
        ])?.outputImage).cropped(to: base.extent)

        let clamped = try #require(CIFilter(name: "CIColorClamp", parameters: [
            kCIInputImageKey: blown,
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])?.outputImage).cropped(to: base.extent)

        /// The darkest red anywhere in the frame after slicing.
        ///
        /// The mean is no good here — the black holes and the blown-out glow average each
        /// other out. The defect *is* black pixels appearing, so measure the minimum.
        func darkestRed(_ img: CIImage) throws -> Int {
            let sliced = SliceShiftEffect(intensity: 0.8, size: 0.5, jitter: 0.0)
                .apply(to: img, progress: 1.0, frameIndex: 3)
            let w = 96, h = 96
            var px = [UInt8](repeating: 0, count: w * h * 4)
            ctx.render(sliced, toBitmap: &px, rowBytes: w * 4,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return stride(from: 0, to: px.count, by: 4).map { Int(px[$0]) }.min() ?? 0
        }

        // Asserts only the invariant this code owns: after clamping, nothing in the frame is
        // darker than the background it started from. Nothing in the fixture is darker than
        // the 0.5 grey, so a near-black pixel could only come from the composite going
        // negative.
        //
        // An earlier version also asserted the *unclamped* path goes black, to prove the bug
        // reproduces. That passed alone and failed in a full run: it was really an assertion
        // about how Core Image treats out-of-range values, which is its business and not a
        // property of this code. Same trap as the MOTION BLUR endpoint test above — assert
        // what you own, not what the framework happens to do.
        let withClamp = try darkestRed(clamped)
        #expect(withClamp > 90, "clamping must leave nothing darker than the grey background, got \(withClamp)")
    }

    private func gradientTestImage() -> CIImage {
        CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
            .applyingFilter("CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                "inputPoint1": CIVector(x: 96, y: 96),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1)
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
    }

    /// The default 4-arg entry point must behave as identity geometry, so the preview
    /// path (which applies to the un-zoomed source) is unaffected.
    @Test func dither_defaultOverloadMatchesIdentityGeometry() {
        let input = makeTestImage()
        let effect = DitherEffect(intensity: 1.0, size: 0.6)
        let viaDefault = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: nil)
        let viaIdentity = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: nil, geometry: .identity)
        #expect(viaDefault.extent == viaIdentity.extent)
    }

    /// The SCALE slider must actually change the output, not just the parameters.
    @Test func dither_sizeChangesOutput() {
        let ctx = CIContext()
        let input = makeTestImage()
        for size in [0.0, 0.5, 1.0] {
            let effect = DitherEffect(intensity: 1.0, size: size)
            let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
            #expect(output.extent == input.extent)
            #expect(ctx.createCGImage(output, from: output.extent) != nil, "size \(size) failed")
        }
    }
}
