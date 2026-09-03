import Testing
import CoreImage
import UIKit
@testable import Enhance

/// The motion foundation: what a context hands an effect, how it places burst-space images
/// into a frame, and that the generator hands every burst frame a context (and a still none).
struct MotionContextTests {

    private func solid(_ color: CIColor, side: CGFloat = 100) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    private func context(index: Int, count: Int = 4) -> MotionContext {
        let frames = (0..<count).map { solid(CIColor(red: CGFloat($0) / 4, green: 0, blue: 0)) }
        let masks: [CIImage?] = (0..<count).map { $0 == 1 ? nil : solid(.white) }
        return MotionContext(index: index, frames: frames, masks: masks,
                             subjectVelocity: CGVector(dx: 0.1, dy: 0), cameraVelocity: CGVector(dx: 0, dy: 0.2))
    }

    @Test func framesAndMasksLookBackwardsAndStopAtTheStart() {
        let ctx = context(index: 2)
        #expect(ctx.frame(back: 0) != nil)
        #expect(ctx.frame(back: 2) != nil)
        #expect(ctx.frame(back: 3) == nil, "past the start")
        #expect(ctx.frame(back: -1) == nil, "never forwards")
        #expect(ctx.mask(back: 1) == nil, "frame 1 has no mask")
        #expect(ctx.mask != nil)
        #expect(ctx.frameCount == 4)
    }

    @Test func velocityPrefersTheSubjectAndFallsBackToTheCamera() {
        let ctx = context(index: 0)
        #expect(ctx.velocity == CGVector(dx: 0.1, dy: 0))
        let noFace = MotionContext(index: 0, frames: [solid(.white)], masks: [nil],
                                   subjectVelocity: .zero, cameraVelocity: CGVector(dx: 0, dy: 0.2))
        #expect(noFace.velocity == CGVector(dx: 0, dy: 0.2))
    }

    @Test func placingScalesABurstSpaceImageToTheFrameContentRect() {
        let ctx = context(index: 0)
        let frame = solid(.black, side: 300)
        let geometry = FrameGeometry(scale: 1, contentOrigin: .zero, contentRect: frame.extent)
        let placed = ctx.place(ctx.frame(back: 0)!, in: frame, geometry: geometry)
        #expect(placed?.extent == frame.extent)
        // The preview's identity geometry (null rect) leaves the image as-is, cropped to the frame.
        let identity = ctx.place(ctx.frame(back: 0)!, in: frame, geometry: .identity)
        #expect(identity?.extent == frame.extent)
        // A cut-out exists where both a frame and a mask do, and not where the mask is missing.
        #expect(ctx.subjectCutout(back: 0, in: frame, geometry: geometry) != nil)
        #expect(context(index: 1).subjectCutout(back: 0, in: frame, geometry: geometry) == nil)
    }

    @Test func theDefaultOverloadDropsMotionAndIsByteIdentical() {
        let effect = FisheyeEffect(intensity: 0.7, size: 0.5)
        let image = CIImage(image: UIImage(systemName: "photo")!) ?? solid(.gray)
        let ctx = context(index: 0)
        let plain = effect.apply(to: image, progress: 0.8, frameIndex: 3, viewportCenter: nil, geometry: .identity)
        let withMotion = effect.apply(to: image, progress: 0.8, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        let ci = CIContext()
        let a = ci.createCGImage(plain, from: plain.extent)!
        let b = ci.createCGImage(withMotion, from: withMotion.extent)!
        #expect(a.dataProvider?.data as Data? == b.dataProvider?.data as Data?)
    }

    // MARK: - Generator

    /// Records what the generator hands each output frame.
    private final class RecordingEffect: VisualEffect {
        let lock = NSLock()
        var contexts: [MotionContext?] = []
        func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage { image }
        func apply(to image: CIImage, progress: CGFloat, frameIndex: Int, viewportCenter: CGPoint?, geometry: FrameGeometry, motion: MotionContext?) -> CIImage {
            lock.lock(); contexts.append(motion); lock.unlock()
            return image
        }
    }

    private func frame(_ hue: CGFloat) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80), format: f).image { ctx in
            UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
    }

    @Test func theGeneratorHandsEveryBurstFrameAContextAndAStillNone() {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let burst = (0..<5).map { i in
            BurstFrame(image: frame(CGFloat(i) / 5), faces: [], mask: solid(.white, side: 40),
                       subjectVelocity: CGVector(dx: 0.01 * CGFloat(i), dy: 0), cameraVelocity: .zero)
        }
        let recorder = RecordingEffect()
        _ = GIFGenerator(concurrency: 1).generateGIF(
            frames: burst, frameInterval: 0.1, currentScale: 1, visibleRect: rect, animator: StaticAnimator(),
            speed: 1, pauseDuration: 0, visualEffects: [recorder], faceEffect: nil, textOverlay: nil
        )
        // Five animated frames plus the one pause frame, every one with a context.
        #expect(recorder.contexts.count == 6)
        #expect(recorder.contexts.allSatisfy { $0 != nil })
        #expect(recorder.contexts[2]?.index == 2)
        #expect(recorder.contexts[2]?.frameCount == 5)
        #expect(recorder.contexts[2]?.mask != nil)
        #expect(abs((recorder.contexts[3]?.subjectVelocity.dx ?? 0) - 0.03) < 1e-9)
        #expect(recorder.contexts[5]?.index == 4, "the hold carries the last frame's context")

        let still = RecordingEffect()
        _ = GIFGenerator(concurrency: 1).generateGIF(
            from: frame(0.3), currentScale: 1, visibleRect: rect, animator: StaticAnimator(),
            speed: 1, pauseDuration: 0, visualEffects: [still]
        )
        #expect(!still.contexts.isEmpty)
        #expect(still.contexts.allSatisfy { $0 == nil })
    }

    @Test func maskConditioningKeepsExtentsAndTreatsMissingNeighboursAsSelf() {
        let m = solid(.white, side: 50)
        let feathered = MotionMasks.feathered(m, radius: 2)
        #expect(feathered.extent == m.extent)
        #expect(MotionMasks.feathered(m, radius: 0) === m)
        let smoothed = MotionMasks.neighbourSmoothed([m, nil, m])
        #expect(smoothed.count == 3)
        #expect(smoothed[1] == nil)
        #expect(smoothed[0]?.extent == m.extent)
    }
}
