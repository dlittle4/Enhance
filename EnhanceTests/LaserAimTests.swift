import Testing
import CoreImage
import UIKit
@testable import Enhance

/// LAZER EYES aiming: the target model, the beam timing, and that an aimed render actually
/// puts light where the user pointed.
struct LaserAimTests {

    private func whiteImage() -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    private func blackImage() -> CIImage {
        CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    private func face() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 50, y: 50, width: 100, height: 100),
            faceCenter: CGPoint(x: 100, y: 100),
            faceWidth: 100, faceHeight: 100,
            leftPupilCenter: CGPoint(x: 75, y: 115),
            rightPupilCenter: CGPoint(x: 125, y: 115),
            leftEyeWidth: 20, rightEyeWidth: 20,
            leftEyebrowPoints: [], rightEyebrowPoints: [], faceContourPoints: [],
            normalizedBoundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )
    }

    /// Red channel (0…255) of one pixel of a rendered image.
    private func red(at point: CGPoint, of image: CIImage) -> Int {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        return Int(pixel[0])
    }

    // MARK: - Model

    @Test func canvasPointFlipsYAndNormalises() {
        let aim = LaserAim.from(canvasPoint: CGPoint(x: 50, y: 25), in: CGSize(width: 200, height: 100))
        #expect(aim == LaserAim(x: 0.25, y: 0.75))
    }

    @Test func canvasPointOutsideTheImageClampsToTheEdge() {
        let aim = LaserAim.from(canvasPoint: CGPoint(x: -10, y: 500), in: CGSize(width: 200, height: 100))
        #expect(aim == LaserAim(x: 0, y: 0))
    }

    @Test func degenerateBoundsGiveNoAim() {
        #expect(LaserAim.from(canvasPoint: .zero, in: .zero) == nil)
    }

    @Test func aimMapsIntoAnOffsetExtent() {
        let point = LaserAim(x: 0.5, y: 0.25).point(in: CGRect(x: 100, y: 200, width: 40, height: 80))
        #expect(point == CGPoint(x: 120, y: 220))
    }

    // MARK: - Timing

    @Test func beamsDoNotFireBeforeTheEyesGlow() {
        #expect(LazerEyesEffect.beamReach(at: 0) == 0)
        #expect(LazerEyesEffect.beamReach(at: LazerEyesEffect.beamStart) == 0)
        #expect(LazerEyesEffect.beamReach(at: 1) == 1)
    }

    @Test func scorchWaitsForTheBeamToArrive() {
        #expect(LazerEyesEffect.scorchBloom(at: LazerEyesEffect.beamArrival) == 0)
        #expect(LazerEyesEffect.scorchBloom(at: 0.45) == 0)
        #expect(LazerEyesEffect.scorchBloom(at: 1) == 1)
    }

    // MARK: - Rendering

    @Test func unaimedRenderIsUnchangedByTheNewCode() {
        // The classic look is what every thumbnail shows; an aim of nil must not alter it.
        let effect = LazerEyesEffect(intensity: 0.8)
        let output = effect.apply(to: whiteImage(), face: face(), progress: 1.0, frameIndex: 0)
        #expect(output.extent == whiteImage().extent)
    }

    @Test func aimedBeamLightsThePathToTheTarget() {
        // Target at the top-right of a black frame; the pupils are around (75–125, 115).
        // A point on the line from the right eye to the target should be lit; the bottom-left
        // corner, far from both eyes and the target, should stay dark.
        let aim = LaserAim(x: 0.9, y: 0.9)
        let effect = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red, aim: aim)
        let output = effect.apply(to: blackImage(), face: face(), progress: 1.0, frameIndex: 0)

        // Right pupil (125,115) → target (180,180): midpoint ≈ (152,147).
        let onBeam = red(at: CGPoint(x: 152, y: 147), of: output)
        let offBeam = red(at: CGPoint(x: 15, y: 15), of: output)
        #expect(onBeam > 40, "beam midpoint red=\(onBeam)")
        #expect(offBeam < 10, "corner red=\(offBeam)")
    }

    @Test func aimedBeamHasNotReachedTheTargetEarlyOn() {
        let aim = LaserAim(x: 0.9, y: 0.9)
        let effect = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red, aim: aim)
        // Just after the beams start: they have travelled a fraction of the way.
        let early = effect.apply(to: blackImage(), face: face(), progress: 0.36, frameIndex: 0)
        let late = effect.apply(to: blackImage(), face: face(), progress: 1.0, frameIndex: 0)
        let nearTarget = CGPoint(x: 172, y: 172)
        #expect(red(at: nearTarget, of: early) < red(at: nearTarget, of: late))
    }

    @Test func scorchDarkensAWhiteTargetOnceTheBeamLands() {
        let aim = LaserAim(x: 0.9, y: 0.9)
        let effect = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red, aim: aim)
        let output = effect.apply(to: whiteImage(), face: face(), progress: 1.0, frameIndex: 0)
        // The char disc is source-over black; its rim (outside the hot pit) reads darker than
        // untouched white. Sample a ring point just inside the char radius.
        let unaimed = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red)
            .apply(to: whiteImage(), face: face(), progress: 1.0, frameIndex: 0)
        let ringPoint = CGPoint(x: 180 + 12, y: 180 - 12)
        #expect(red(at: ringPoint, of: output) < red(at: ringPoint, of: unaimed))
    }

    @Test func batchRenderWithTwoFacesStillProducesOutput() {
        let aim = LaserAim(x: 0.5, y: 0.1)
        let effect = LazerEyesEffect(aim: aim)
        let output = effect.apply(to: whiteImage(), faces: [face(), face()], progress: 1.0, frameIndex: 3)
        #expect(output.extent == whiteImage().extent)
    }

    // MARK: - Pulse

    @Test func pulseKernelIsBundledAndLoads() {
        // Same trap as the kernel gate: a misnamed resource yields a silent nil and the beams
        // quietly stop pulsing. Pin it.
        #expect(LazerEyesEffect.pulseKernelIsAvailable)
    }

    @Test func pulseMovesAlongTheBeamBetweenFrames() {
        // With pulse depth at full, a point on the beam is bright on some frames and dark on
        // others; a steady beam renders the same red on every frame.
        let aim = LaserAim(x: 0.9, y: 0.9)
        let pulsing = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red, aim: aim, pulse: 1.0, pulseSpeed: 0.5)
        let steady = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red, aim: aim, pulse: 0.0)
        let point = CGPoint(x: 152, y: 147)

        let pulsingReds = (0..<8).map { red(at: point, of: pulsing.apply(to: blackImage(), face: face(), progress: 1.0, frameIndex: $0)) }
        let steadyReds = (0..<8).map { red(at: point, of: steady.apply(to: blackImage(), face: face(), progress: 1.0, frameIndex: $0)) }

        let pulsingRange = (pulsingReds.max() ?? 0) - (pulsingReds.min() ?? 0)
        let steadyRange = (steadyReds.max() ?? 0) - (steadyReds.min() ?? 0)
        #expect(pulsingRange > 20, "pulsing reds \(pulsingReds)")
        // The eye's flicker still varies the steady beam a little; it must be far less than a pulse.
        #expect(steadyRange < pulsingRange / 2, "steady reds \(steadyReds)")
    }

    @Test func pulseAlsoRidesTheClassicFlare() {
        let pulsing = LazerEyesEffect(intensity: 0.8, size: 0.5, laserColor: .red, pulse: 1.0, pulseSpeed: 0.5)
        // 30px right of the right pupil (125,115): inside the bloom and on the flare, which is
        // where the classic look actually has light — profiled at red 86 here and 19 by x=185.
        let point = CGPoint(x: 155, y: 115)
        let reds = (0..<8).map { red(at: point, of: pulsing.apply(to: blackImage(), face: face(), progress: 1.0, frameIndex: $0)) }
        #expect((reds.max() ?? 0) - (reds.min() ?? 0) > 20, "flare reds \(reds)")
    }

    @Test func lazerEyesDeclaresPulseRows() {
        let ids = FaceFilterType.lazerEyes.parameters.map(\.id)
        #expect(ids.contains(EffectParameter.tertiaryID))
        #expect(ids.contains(EffectParameter.quaternaryID))
        #expect(FaceFilterType.googlyEyes.parameters.map(\.id).contains(EffectParameter.tertiaryID) == false)
    }

    // MARK: - Editor session

    @MainActor
    @Test func aimSessionRecordsOneUndoEntryAndRestoresTheOldTarget() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.selectedEffectCategory = .faceFilters
        vm.selectedFaceFilter = .lazerEyes

        vm.beginLaserAim()
        vm.updateLaserAim(LaserAim(x: 0.2, y: 0.2))
        vm.updateLaserAim(LaserAim(x: 0.7, y: 0.6))
        #expect(vm.isLaserAimActive)
        vm.endLaserAim()

        #expect(!vm.isLaserAimActive)
        #expect(vm.laserAim == LaserAim(x: 0.7, y: 0.6))
        #expect(vm.canUndo)

        vm.undo()
        #expect(vm.laserAim == nil)
        vm.redo()
        #expect(vm.laserAim == LaserAim(x: 0.7, y: 0.6))
    }

    @MainActor
    @Test func aimSessionThatMovesNothingLeavesNoUndoEntry() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.beginLaserAim()
        vm.endLaserAim()
        #expect(!vm.canUndo)
    }

    @MainActor
    @Test func laserHintShowsOnlyWhileAimingIsPossibleAndUnused() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.showControls = true
        vm.selectedEffectCategory = .faceFilters
        vm.selectedFaceFilter = .lazerEyes
        // No faces detected: nothing to fire from, so no aim and no hint.
        #expect(!vm.wantsLaserAim)
        #expect(!vm.showsLaserHint)

        vm.detectedFaces = [face()]
        #expect(vm.wantsLaserAim)
        #expect(vm.showsLaserHint)

        vm.noteLaserAimed()
        #expect(!vm.showsLaserHint)
    }

    @MainActor
    @Test func resetClearsTheAim() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.laserAim = LaserAim(x: 0.3, y: 0.3)
        vm.resetEffects()
        #expect(vm.laserAim == nil)
    }
}
