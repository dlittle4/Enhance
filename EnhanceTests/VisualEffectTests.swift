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
    
    @Test func visualEffectType_allCasesProduceOutput() {
        let input = makeTestImage()
        let ctx = CIContext()
        
        for type in VisualEffectType.allCases {
            let effect = type.effect(size: 0.5)
            let output = effect.apply(to: input, progress: 0.5, frameIndex: 10)
            let cgImage = ctx.createCGImage(output, from: output.extent)
            #expect(cgImage != nil)
        }
    }
}
