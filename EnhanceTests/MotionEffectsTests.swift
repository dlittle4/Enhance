import Testing
import CoreImage
import UIKit
@testable import Enhance

/// FEATURE-MOTION-EFFECTS.md §3: the effects that read motion.
struct MotionEffectsTests {

    private let side: CGFloat = 100

    private func frame(squareAt x: CGFloat) -> CIImage {
        let bg = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        let white = CIImage(color: .white).cropped(to: CGRect(x: x, y: 40, width: 20, height: 20))
        return white.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: bg]).cropped(to: bg.extent)
    }

    private func red(at point: CGPoint, of image: CIImage) -> Int {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Int(pixel[0])
    }

    /// A square moving right; the context for the last frame, velocity rightward.
    private func movingRight(velocity: CGVector = CGVector(dx: 0.2, dy: 0)) -> (MotionContext, CIImage) {
        let frames = (0..<4).map { frame(squareAt: 10 + CGFloat($0) * 20) }
        let ctx = MotionContext(index: 3, frames: frames, masks: frames.map { Optional($0) }, subjectVelocity: velocity, cameraVelocity: .zero)
        return (ctx, frames[3])
    }

    // MARK: - MOTION BLUR

    @Test func motionBlurFollowsTheMeasuredVelocityAndStaysSharpWhenStill() {
        let (ctx, image) = movingRight()
        let effect = MotionBlurEffect(intensity: 1, angle: 0.5)  // slider angle 45°, ignored on a burst
        let moving = effect.apply(to: image, progress: 0.1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        // Rightward motion smears horizontally: the row through the square lights up to its
        // right, while the column above it stays dark.
        #expect(red(at: CGPoint(x: 95, y: 50), of: moving) > 8, "smear reaches right along the motion")
        #expect(red(at: CGPoint(x: 80, y: 90), of: moving) < 5, "nothing above")

        let still = MotionContext(index: 3, frames: ctx.frames, masks: ctx.masks, subjectVelocity: .zero, cameraVelocity: .zero)
        let sharp = effect.apply(to: image, progress: 0.1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: still)
        // No motion falls back to the still behaviour: at progress 0.1 that is nearly no blur.
        #expect(red(at: CGPoint(x: 95, y: 50), of: sharp) < 3)
    }

    // MARK: - MOTION TRAIL

    @Test func trailSmearsEachEchoAlongTheMotion() {
        let (ctx, image) = movingRight()
        let crisp = FrameEchoEffect(intensity: 1, echoes: 0, opacity: 1, smear: 0)
            .apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        let trail = FrameEchoEffect(intensity: 1, echoes: 0, opacity: 1, smear: 1)
            .apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        // The echo one back sits at x 50…70. Crisp, x = 45 is black; smeared, it carries light.
        #expect(red(at: CGPoint(x: 45, y: 50), of: crisp) < 5)
        #expect(red(at: CGPoint(x: 45, y: 50), of: trail) > 10)
        #expect(VisualEffectType.motionTrail.effect() is FrameEchoEffect)
    }

    // MARK: - SPEED LINES

    @Test func speedLinesTrailBehindTheSubjectNotInFront() {
        let (ctx, image) = movingRight()  // current square at x 70…90, moving right
        let effect = SpeedLinesEffect(intensity: 1, density: 1)
        let out = effect.apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        // Behind (left of) the body: some light along the row; sample several points since
        // stripes alternate.
        let behind = (0..<8).map { red(at: CGPoint(x: 40 + CGFloat($0) * 3, y: 45 + CGFloat($0 % 4) * 3), of: out) }
        #expect(behind.max() ?? 0 > 30, "lines behind the body")
        // In front (right of) the body: nothing.
        #expect(red(at: CGPoint(x: 96, y: 50), of: out) < 5)
        // Far above: nothing.
        #expect(red(at: CGPoint(x: 50, y: 90), of: out) < 5)
        // The body itself is untouched by lines.
        #expect(red(at: CGPoint(x: 80, y: 50), of: out) > 240)
    }

    @Test func speedLinesNeedMotionAndAMask() {
        let (ctx, image) = movingRight(velocity: .zero)
        let out = SpeedLinesEffect(intensity: 1).apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        #expect(red(at: CGPoint(x: 50, y: 50), of: out) < 5, "no motion, no lines")
        let noMask = MotionContext(index: 3, frames: ctx.frames, masks: ctx.frames.map { _ in nil }, subjectVelocity: CGVector(dx: 0.2, dy: 0), cameraVelocity: .zero)
        let out2 = SpeedLinesEffect(intensity: 1).apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: noMask)
        #expect(red(at: CGPoint(x: 50, y: 50), of: out2) < 5, "no mask, no lines")
        #expect(VisualEffectType.speedLines.effect() is SpeedLinesEffect)
    }

    // MARK: - SHAKE

    private func context(cameraVelocities: [CGVector]) -> GIFGenerator.DrawingContext {
        GIFGenerator.DrawingContext(
            normalizedImage: UIImage(), outputSize: CGSize(width: 600, height: 600),
            drawRect: CGRect(x: 0, y: 0, width: 600, height: 600),
            fullViewParams: .init(scale: 1, centerX: 300, centerY: 300),
            userZoomParams: .init(scale: 2, centerX: 300, centerY: 300),
            frameCount: 10, frameDelay: 0.04, pauseFrameCount: 1, pauseFrameDelay: 0.04,
            cameraVelocities: cameraVelocities
        )
    }

    @Test func shakeGrowsWithTheMeasuredCameraMotion() {
        let still = context(cameraVelocities: [])
        let shaky = context(cameraVelocities: Array(repeating: CGVector(dx: 0.03, dy: 0), count: 10))
        #expect(ShakeModifier.realShake(at: 0.5, in: still) == 0)
        #expect(abs(ShakeModifier.realShake(at: 0.5, in: shaky) - 0.03) < 1e-9)

        let base = GIFGenerator.AnimationParameters(scale: 2, centerX: 300, centerY: 300)
        let modifier = ShakeModifier()
        // Late in the loop the synthetic shake has decayed; a shaky burst still jitters.
        let quiet = modifier.modifyParameters(base, for: 0.97, in: still)
        let real = modifier.modifyParameters(base, for: 0.97, in: shaky)
        let quietOffset = hypot(quiet.centerX - 300, quiet.centerY - 300)
        let realOffset = hypot(real.centerX - 300, real.centerY - 300)
        #expect(realOffset > quietOffset)
    }

    @Test func burstOnlyCardsAreTheThreeMotionCards() {
        #expect(VisualEffectType.burstOnly == [.frameEcho, .motionTrail, .speedLines])
        for type in VisualEffectType.burstOnly {
            let params = type.parameters
            #expect(params.first?.kind == .tintColorOrNone, "\(type.rawValue) leads with a NONE-capable colour")
            #expect(!params.contains { $0.id == EffectParameter.backgroundOnlyID })
        }
        #expect(VisualEffectType.speedLines.parameters.first { $0.kind == .slider }?.label == "LENGTH")
        #expect(VisualEffectType.motionTrail.parameters.first { $0.kind == .slider }?.label == "FADE")
    }
}
