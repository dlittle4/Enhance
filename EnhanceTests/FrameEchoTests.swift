import Testing
import CoreImage
import UIKit
@testable import Enhance

/// FRAME ECHO: earlier subjects drawn behind the current one, from a burst's motion context.
struct FrameEchoTests {

    private let side: CGFloat = 100

    /// A white square at `x` on black, and its mask (the same picture).
    private func frame(squareAt x: CGFloat) -> (CIImage, CIImage) {
        let bg = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        let white = CIImage(color: .white).cropped(to: CGRect(x: x, y: 40, width: 20, height: 20))
        let image = white.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: bg]).cropped(to: bg.extent)
        return (image, image)
    }

    private func red(at point: CGPoint, of image: CIImage) -> Int {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Int(pixel[0])
    }

    /// A square moving right 20px a frame; the context for the last frame.
    private func movingBurst(count: Int = 4) -> (MotionContext, CIImage) {
        var frames: [CIImage] = [], masks: [CIImage?] = []
        for i in 0..<count {
            let (f, m) = frame(squareAt: 10 + CGFloat(i) * 20)
            frames.append(f); masks.append(m)
        }
        let ctx = MotionContext(index: count - 1, frames: frames, masks: masks, subjectVelocity: CGVector(dx: 0.2, dy: 0), cameraVelocity: .zero)
        return (ctx, frames[count - 1])
    }

    @Test func withoutMotionTheFrameIsUntouched() {
        let (_, image) = movingBurst()
        let out = FrameEchoEffect(intensity: 0.8, echoes: 1).apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: nil)
        #expect(red(at: CGPoint(x: 20, y: 50), of: out) < 10, "the earlier square's spot stays black")
    }

    @Test func echoesLandWhereTheSubjectWasAndFadeWithAge() {
        let (ctx, image) = movingBurst()  // squares at x = 10, 30, 50, 70; current at 70
        let effect = FrameEchoEffect(intensity: 0.6, echoes: 1, spacing: 0)  // 6 echoes, spacing 1
        let out = effect.apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        let current = red(at: CGPoint(x: 80, y: 50), of: out)
        let one = red(at: CGPoint(x: 60, y: 50), of: out)
        let two = red(at: CGPoint(x: 40, y: 50), of: out)
        let three = red(at: CGPoint(x: 20, y: 50), of: out)
        #expect(current > 240, "the subject stays solid")
        #expect(one > 40 && one < current, "one back is a dimmer echo")
        #expect(two < one && three < two, "older echoes fade")
        #expect(three > 0)
        #expect(red(at: CGPoint(x: 95, y: 5), of: out) < 5, "elsewhere untouched")
    }

    @Test func spacingSkipsFramesAndAMissingMaskSkipsThatEcho() {
        var (ctx, image) = movingBurst()
        let spaced = FrameEchoEffect(intensity: 0.8, echoes: 0, spacing: 1.0 / 3)  // 1 echo, 2 frames back
        let out = spaced.apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        #expect(red(at: CGPoint(x: 40, y: 50), of: out) > 40, "two back is drawn")
        #expect(red(at: CGPoint(x: 60, y: 50), of: out) < 10, "one back is not")

        var masks = ctx.masks; masks[1] = nil
        ctx = MotionContext(index: 3, frames: ctx.frames, masks: masks, subjectVelocity: .zero, cameraVelocity: .zero)
        let gapped = spaced.apply(to: image, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: .identity, motion: ctx)
        #expect(red(at: CGPoint(x: 40, y: 50), of: gapped) < 10, "no mask, no echo")
    }

    @Test func echoesPlaceThroughTheFrameGeometry() {
        // A 200px frame with the 100px burst frames mapped into its content rect: the echo
        // one back sits at twice the burst-space x.
        let (ctx, _) = movingBurst()
        let big = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let geometry = FrameGeometry(scale: 2, contentOrigin: .zero, contentRect: big.extent)
        let out = FrameEchoEffect(intensity: 0.9, echoes: 0).apply(to: big, progress: 1, frameIndex: 3, viewportCenter: nil, geometry: geometry, motion: ctx)
        #expect(red(at: CGPoint(x: 120, y: 100), of: out) > 40, "one back at 60 → 120")
        #expect(red(at: CGPoint(x: 60, y: 100), of: out) < 10)
    }

    // MARK: - Card visibility

    @MainActor
    @Test func frameEchoIsOfferedOnlyWithABurstAndTheFlag() {
        let key = FeatureFlags.motionEffectsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let vm = EditorViewModel(content: .newImage(UIImage()))
        UserDefaults.standard.set(true, forKey: key)
        #expect(!vm.carouselVisualEffects.contains(.frameEcho), "a still never shows it")

        let f = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        vm.adoptBurst([f, f])
        #expect(vm.carouselVisualEffects.contains(.frameEcho))
        #expect(VisualEffectType.selectable.contains(.frameEcho), "the lab still sees it")

        vm.selectedVisualEffect = .frameEcho
        vm.adoptBurst(nil)
        #expect(vm.selectedVisualEffect == nil, "cleared with the burst")

        UserDefaults.standard.set(false, forKey: key)
        vm.adoptBurst([f, f])
        #expect(!vm.carouselVisualEffects.contains(.frameEcho), "flag off hides it")
    }

    @Test func frameEchoDeclaresItsRowsAndNoBackgroundOnly() {
        let ids = VisualEffectType.frameEcho.parameters.map(\.id)
        #expect(ids.contains("tint"))
        #expect(ids.contains(EffectParameter.intensityID))
        #expect(ids.contains(EffectParameter.sizeID))
        #expect(ids.contains(EffectParameter.tertiaryID))
        #expect(ids.contains(EffectParameter.quaternaryID))
        #expect(!ids.contains(EffectParameter.backgroundOnlyID))
        #expect(VisualEffectType.frameEcho.effect() is FrameEchoEffect)
    }
}
