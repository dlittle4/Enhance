import Testing
import UIKit
@testable import Enhance

struct MotionModifierTests {
    
    private func makeContext() -> GIFGenerator.DrawingContext {
        let image = UIImage()
        let size = CGSize(width: 600, height: 600)
        return GIFGenerator.DrawingContext(
            normalizedImage: image,
            outputSize: size,
            drawRect: CGRect(origin: .zero, size: size),
            fullViewParams: GIFGenerator.AnimationParameters(scale: 1.0, centerX: 300, centerY: 300),
            userZoomParams: GIFGenerator.AnimationParameters(scale: 2.0, centerX: 400, centerY: 200),
            frameCount: 25,
            frameDelay: 0.04,
            pauseFrameCount: 25,
            pauseFrameDelay: 0.04
        )
    }
    
    private func makeParams(
        scale: CGFloat = 1.5,
        centerX: CGFloat = 350,
        centerY: CGFloat = 250
    ) -> GIFGenerator.AnimationParameters {
        GIFGenerator.AnimationParameters(scale: scale, centerX: centerX, centerY: centerY)
    }
    
    // MARK: - StraightModifier
    
    @Test func straight_returnsParametersUnchanged() {
        let modifier = StraightModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let output = modifier.modifyParameters(input, for: 0.5, in: ctx)
        
        #expect(output.scale == input.scale)
        #expect(output.centerX == input.centerX)
        #expect(output.centerY == input.centerY)
    }
    
    @Test func straight_unchangedAtAllProgresses() {
        let modifier = StraightModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        for i in 0...10 {
            let progress = CGFloat(i) / 10.0
            let output = modifier.modifyParameters(input, for: progress, in: ctx)
            #expect(output.scale == input.scale)
            #expect(output.centerX == input.centerX)
            #expect(output.centerY == input.centerY)
        }
    }
    
    // MARK: - ShakeModifier
    
    @Test func shake_preservesScale() {
        let modifier = ShakeModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let output = modifier.modifyParameters(input, for: 0.3, in: ctx)
        #expect(output.scale == input.scale)
    }
    
    @Test func shake_displacesCenterAtMidProgress() {
        let modifier = ShakeModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let output = modifier.modifyParameters(input, for: 0.25, in: ctx)
        let hasDrift = output.centerX != input.centerX || output.centerY != input.centerY
        #expect(hasDrift)
    }
    
    @Test func shake_decaysAtFullProgress() {
        let modifier = ShakeModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let outputEnd = modifier.modifyParameters(input, for: 1.0, in: ctx)
        
        let driftX = abs(outputEnd.centerX - input.centerX)
        let driftY = abs(outputEnd.centerY - input.centerY)
        #expect(driftX < 1.0)
        #expect(driftY < 1.0)
    }
    
    @Test func shake_isDeterministic() {
        let modifier = ShakeModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let a = modifier.modifyParameters(input, for: 0.4, in: ctx)
        let b = modifier.modifyParameters(input, for: 0.4, in: ctx)
        
        #expect(a.centerX == b.centerX)
        #expect(a.centerY == b.centerY)
    }
    
    // MARK: - SpiralModifier
    
    @Test func spiral_preservesScale() {
        let modifier = SpiralModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let output = modifier.modifyParameters(input, for: 0.3, in: ctx)
        #expect(output.scale == input.scale)
    }
    
    @Test func spiral_displacesCenterAtStart() {
        let modifier = SpiralModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let output = modifier.modifyParameters(input, for: 0.0, in: ctx)
        let hasDrift = output.centerX != input.centerX || output.centerY != input.centerY
        #expect(hasDrift)
    }
    
    @Test func spiral_settlesAtEnd() {
        let modifier = SpiralModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let output = modifier.modifyParameters(input, for: 1.0, in: ctx)
        
        let driftX = abs(output.centerX - input.centerX)
        let driftY = abs(output.centerY - input.centerY)
        #expect(driftX < 1.0)
        #expect(driftY < 1.0)
    }
    
    @Test func spiral_radiusDecreases() {
        let modifier = SpiralModifier()
        let ctx = makeContext()
        let input = makeParams()
        
        let earlyOutput = modifier.modifyParameters(input, for: 0.1, in: ctx)
        let lateOutput = modifier.modifyParameters(input, for: 0.9, in: ctx)
        
        let earlyDist = hypot(earlyOutput.centerX - input.centerX, earlyOutput.centerY - input.centerY)
        let lateDist = hypot(lateOutput.centerX - input.centerX, lateOutput.centerY - input.centerY)
        
        #expect(earlyDist > lateDist)
    }
    
    // MARK: - CompositeAnimator
    
    @Test func composite_combinesBaseAndModifier() {
        let base = ZoomInAnimator()
        let modifier = ShakeModifier()
        let composite = CompositeAnimator(base: base, modifier: modifier)
        let ctx = makeContext()
        
        let baseParams = base.animationParameters(for: 0.3, in: ctx)
        let compositeParams = composite.animationParameters(for: 0.3, in: ctx)
        
        #expect(compositeParams.scale == baseParams.scale)
        let hasDrift = compositeParams.centerX != baseParams.centerX || compositeParams.centerY != baseParams.centerY
        #expect(hasDrift)
    }
    
    @Test func composite_conformsToAnimator() {
        let composite: Animator = CompositeAnimator(base: ZoomInAnimator(), modifier: SpiralModifier())
        let ctx = makeContext()
        let params = composite.animationParameters(for: 0.5, in: ctx)
        #expect(params.scale > 0)
    }
    
    // MARK: - ModifierType enum
    
    @Test func modifierType_allCasesReturnModifier() {
        let ctx = makeContext()
        let input = makeParams()
        
        for type in ModifierType.allCases {
            let modifier = type.modifier
            let output = modifier.modifyParameters(input, for: 0.5, in: ctx)
            #expect(output.scale > 0)
        }
    }
}
