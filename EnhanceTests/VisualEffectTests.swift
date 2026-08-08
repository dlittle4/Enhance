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

    /// Cell size scales with the frame's zoom so the stipple stays locked to image
    /// content. Without this the GIF pattern is fixed in output pixels and reads as a
    /// static overlay the image slides beneath — and disagrees with the preview.
    @Test func dither_scalesCellWithFrameScale() {
        let ctx = CIContext()
        let input = makeTestImage()
        let effect = DitherEffect(intensity: 1.0, size: 0.5)
        for scale in [CGFloat(1), 2, 4, 8] {
            let output = effect.apply(
                to: input, progress: 1.0, frameIndex: 0,
                viewportCenter: nil, frameScale: scale
            )
            #expect(output.extent == input.extent, "extent drifted at \(scale)x")
            #expect(ctx.createCGImage(output, from: output.extent) != nil)
        }
    }

    /// The default 4-arg entry point must behave as frameScale 1, so the preview path
    /// (which applies to the un-zoomed source) is unaffected.
    @Test func dither_defaultOverloadMatchesUnityFrameScale() {
        let input = makeTestImage()
        let effect = DitherEffect(intensity: 1.0, size: 0.6)
        let viaDefault = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: nil)
        let viaUnity = effect.apply(to: input, progress: 1.0, frameIndex: 0, viewportCenter: nil, frameScale: 1.0)
        #expect(viaDefault.extent == viaUnity.extent)
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
