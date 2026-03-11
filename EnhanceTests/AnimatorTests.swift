import Testing
import UIKit
@testable import Enhance

struct AnimatorTests {
    
    private func makeContext(
        fullScale: CGFloat = 1.0,
        fullCenterX: CGFloat = 300,
        fullCenterY: CGFloat = 300,
        userScale: CGFloat = 2.0,
        userCenterX: CGFloat = 400,
        userCenterY: CGFloat = 200
    ) -> GIFGenerator.DrawingContext {
        let image = UIImage()
        let size = CGSize(width: 600, height: 600)
        return GIFGenerator.DrawingContext(
            normalizedImage: image,
            outputSize: size,
            drawRect: CGRect(origin: .zero, size: size),
            fullViewParams: GIFGenerator.AnimationParameters(scale: fullScale, centerX: fullCenterX, centerY: fullCenterY),
            userZoomParams: GIFGenerator.AnimationParameters(scale: userScale, centerX: userCenterX, centerY: userCenterY),
            frameCount: 25,
            frameDelay: 0.04,
            pauseFrameCount: 25,
            pauseFrameDelay: 0.04
        )
    }
    
    // MARK: - ZoomInAnimator
    
    @Test func zoomIn_atProgressZero_returnsFullView() {
        let animator = ZoomInAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 0.0, in: ctx)
        
        #expect(abs(params.scale - ctx.fullViewParams.scale) < 0.001)
        #expect(abs(params.centerX - ctx.fullViewParams.centerX) < 0.001)
        #expect(abs(params.centerY - ctx.fullViewParams.centerY) < 0.001)
    }
    
    @Test func zoomIn_atProgressOne_returnsUserZoom() {
        let animator = ZoomInAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 1.0, in: ctx)
        
        #expect(abs(params.scale - ctx.userZoomParams.scale) < 0.001)
        #expect(abs(params.centerX - ctx.userZoomParams.centerX) < 0.001)
        #expect(abs(params.centerY - ctx.userZoomParams.centerY) < 0.001)
    }
    
    @Test func zoomIn_scaleMonotonicallyIncreases() {
        let animator = ZoomInAnimator()
        let ctx = makeContext()
        
        var previousScale: CGFloat = 0
        for i in 0...20 {
            let progress = CGFloat(i) / 20.0
            let params = animator.animationParameters(for: progress, in: ctx)
            #expect(params.scale >= previousScale)
            previousScale = params.scale
        }
    }
    
    // MARK: - ZoomOutAnimator
    
    @Test func zoomOut_atProgressZero_returnsUserZoom() {
        let animator = ZoomOutAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 0.0, in: ctx)
        
        #expect(abs(params.scale - ctx.userZoomParams.scale) < 0.001)
        #expect(abs(params.centerX - ctx.userZoomParams.centerX) < 0.001)
        #expect(abs(params.centerY - ctx.userZoomParams.centerY) < 0.001)
    }
    
    @Test func zoomOut_atProgressOne_returnsFullView() {
        let animator = ZoomOutAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 1.0, in: ctx)
        
        #expect(abs(params.scale - ctx.fullViewParams.scale) < 0.001)
        #expect(abs(params.centerX - ctx.fullViewParams.centerX) < 0.001)
        #expect(abs(params.centerY - ctx.fullViewParams.centerY) < 0.001)
    }
    
    @Test func zoomOut_scaleMonotonicallyDecreases() {
        let animator = ZoomOutAnimator()
        let ctx = makeContext()
        
        var previousScale: CGFloat = .infinity
        for i in 0...20 {
            let progress = CGFloat(i) / 20.0
            let params = animator.animationParameters(for: progress, in: ctx)
            #expect(params.scale <= previousScale)
            previousScale = params.scale
        }
    }
    
    // MARK: - PulseAnimator
    
    @Test func pulse_atProgressZero_returnsFullView() {
        let animator = PulseAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 0.0, in: ctx)
        
        #expect(abs(params.scale - ctx.fullViewParams.scale) < 0.001)
    }
    
    @Test func pulse_atProgressOne_returnsFullView() {
        let animator = PulseAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 1.0, in: ctx)
        
        #expect(abs(params.scale - ctx.fullViewParams.scale) < 0.01)
    }
    
    @Test func pulse_atMidpoint_reachesMaxZoom() {
        let animator = PulseAnimator()
        let ctx = makeContext()
        let params = animator.animationParameters(for: 0.5, in: ctx)
        
        #expect(params.scale > ctx.fullViewParams.scale)
        #expect(abs(params.scale - ctx.userZoomParams.scale) < 0.01)
    }
    
    // MARK: - AnimatorType enum
    
    @Test func animatorType_allCasesReturn() {
        for type in AnimatorType.allCases {
            let animator = type.animator
            let ctx = makeContext()
            let params = animator.animationParameters(for: 0.5, in: ctx)
            #expect(params.scale > 0)
        }
    }
}
