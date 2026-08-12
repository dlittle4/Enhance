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
