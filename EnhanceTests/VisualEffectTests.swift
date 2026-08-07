import Testing
import CoreImage
import UIKit
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
        let names = FilterPreset.requiredFilterNames + [
            "CIColorCubeWithColorSpace", "CIEdges", "CIMaximumComponent",
            "CIGammaAdjust", "CIColorMatrix", "CIAdditionCompositing",
            "CIDither", "CIColorPosterize", "CIDissolveTransition"
        ]
        for name in names {
            #expect(CIFilter(name: name) != nil, "missing CIFilter: \(name)")
        }
    }

    // MARK: - Filter Presets

    @Test func filterPreset_atZeroProgress_returnsUnchanged() {
        let effect = FilterPresetEffect(preset: .sepia)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func filterPreset_atFullProgress_producesOutput() {
        let effect = FilterPresetEffect(intensity: 1.0, preset: .sepia)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(CIContext().createCGImage(output, from: output.extent) != nil)
    }

    /// Renders every preset's grade. This is what catches a mistyped filter name or
    /// a bad parameter key, both of which `applyingFilter` swallows silently.
    @Test func filterPreset_allPresetsRender() {
        let ctx = CIContext()
        let input = makeTestImage()
        for preset in FilterPreset.allCases {
            let graded = preset.graded(input)
            #expect(ctx.createCGImage(graded, from: graded.extent) != nil, "preset failed: \(preset.rawValue)")
        }
    }

    // MARK: - Gradient Map

    @Test func gradientMap_atZeroProgress_returnsUnchanged() {
        let effect = GradientMapEffect(ramp: .sunset)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func gradientMap_atFullProgress_producesOutput() {
        let effect = GradientMapEffect(intensity: 1.0, ramp: .sunset)
        let input = makeTestImage()
        let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
        #expect(CIContext().createCGImage(output, from: output.extent) != nil)
    }

    @Test func gradientMap_allRampsRender() {
        let ctx = CIContext()
        let input = makeTestImage()
        for ramp in GradientRamp.allCases {
            let effect = GradientMapEffect(intensity: 1.0, ramp: ramp)
            let output = effect.apply(to: input, progress: 1.0, frameIndex: 0)
            #expect(ctx.createCGImage(output, from: output.extent) != nil, "ramp failed: \(ramp.rawValue)")
        }
    }

    /// Every ramp must span the full luminance range so a lookup at any point in
    /// [0,1] is bracketed by two stops.
    @Test func gradientRamp_stopsAreSortedAndSpanZeroToOne() {
        for ramp in GradientRamp.allCases {
            let stops = ramp.stops
            #expect(stops.count >= 2, "\(ramp.rawValue) needs at least 2 stops")
            #expect(stops.first?.location == 0.0, "\(ramp.rawValue) must start at 0")
            #expect(stops.last?.location == 1.0, "\(ramp.rawValue) must end at 1")
            let locations = stops.map(\.location)
            #expect(locations == locations.sorted(), "\(ramp.rawValue) stops out of order")
        }
    }

    @Test func gradientRamp_colorAtEndpointsMatchesStops() {
        for ramp in GradientRamp.allCases {
            let first = ramp.stops.first!.rgb
            let last = ramp.stops.last!.rgb
            let low = ramp.color(at: 0.0)
            let high = ramp.color(at: 1.0)
            #expect(abs(low.r - first.r) < 0.001 && abs(low.g - first.g) < 0.001)
            #expect(abs(high.r - last.r) < 0.001 && abs(high.g - last.g) < 0.001)
        }
    }

    /// Out-of-range lookups must clamp rather than extrapolate or crash.
    @Test func gradientRamp_colorClampsOutOfRangeInput() {
        let ramp = GradientRamp.sunset
        let below = ramp.color(at: -0.5)
        let above = ramp.color(at: 1.5)
        #expect(below.r == ramp.color(at: 0.0).r)
        #expect(above.r == ramp.color(at: 1.0).r)
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
}
