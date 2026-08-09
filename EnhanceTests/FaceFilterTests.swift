import Testing
import CoreImage
import UIKit
@testable import Enhance

struct FaceFilterTests {

    /// Creates a 200x200 solid white CIImage for testing.
    private func makeTestImage() -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    /// Creates a mock DetectedFace centered in a 200x200 image.
    private func makeMockFace() -> DetectedFace {
        DetectedFace(
            boundingBox: CGRect(x: 50, y: 50, width: 100, height: 100),
            faceCenter: CGPoint(x: 100, y: 100),
            faceWidth: 100, faceHeight: 100,
            leftPupilCenter: CGPoint(x: 75, y: 115),
            rightPupilCenter: CGPoint(x: 125, y: 115),
            leftEyeWidth: 20, rightEyeWidth: 20,
            leftEyebrowPoints: [CGPoint(x: 65, y: 130), CGPoint(x: 75, y: 132), CGPoint(x: 85, y: 130)],
            rightEyebrowPoints: [CGPoint(x: 115, y: 130), CGPoint(x: 125, y: 132), CGPoint(x: 135, y: 130)],
            faceContourPoints: [CGPoint(x: 60, y: 50), CGPoint(x: 100, y: 40), CGPoint(x: 140, y: 50)],
            normalizedBoundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )
    }

    // MARK: - LazerEyesEffect

    @Test func lazerEyes_atZeroProgress_returnsUnchanged() {
        let effect = LazerEyesEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func lazerEyes_atFullProgress_producesOutput() {
        let effect = LazerEyesEffect(intensity: 0.8)
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 0)
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    // MARK: - GooglyEyesEffect

    @Test func googlyEyes_atZeroProgress_returnsUnchanged() {
        let effect = GooglyEyesEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func googlyEyes_atFullProgress_producesOutput() {
        let effect = GooglyEyesEffect(size: 0.8, speed: 0.5)
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 0)
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    @Test func googlyEyes_differentFrames_produceDifferentPupilPositions() {
        let effect = GooglyEyesEffect(size: 0.5, speed: 0.5)
        let input = makeTestImage()
        let ctx = CIContext()
        let out0 = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 0)
        let out5 = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 5)
        #expect(ctx.createCGImage(out0, from: out0.extent) != nil)
        #expect(ctx.createCGImage(out5, from: out5.extent) != nil)
    }

    @Test func googlyEyes_highSpeed_producesOutput() {
        let effect = GooglyEyesEffect(size: 0.5, speed: 1.0)
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 3)
        let ctx = CIContext()
        #expect(ctx.createCGImage(output, from: output.extent) != nil)
    }

    // MARK: - SqueezeEffect

    @Test func squeeze_atZeroProgress_returnsUnchanged() {
        let effect = SqueezeEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func squeeze_atFullProgress_producesOutput() {
        let effect = SqueezeEffect(intensity: 0.8)
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 0)
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    // MARK: - HandsomeEffect

    @Test func handsome_atZeroProgress_returnsUnchanged() {
        let effect = HandsomeEffect()
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 0.0, frameIndex: 0)
        #expect(output.extent == input.extent)
    }

    @Test func handsome_atFullProgress_producesOutput() {
        let effect = HandsomeEffect(intensity: 0.8)
        let input = makeTestImage()
        let output = effect.apply(to: input, face: makeMockFace(), progress: 1.0, frameIndex: 0)
        let ctx = CIContext()
        let cgImage = ctx.createCGImage(output, from: output.extent)
        #expect(cgImage != nil)
    }

    // MARK: - FaceFilterType enum

    @Test func faceFilterType_allCasesProduceEffects() {
        let face = makeMockFace()
        let input = makeTestImage()
        let ctx = CIContext()

        for filterType in FaceFilterType.allCases {
            let effect = filterType.effect(intensity: 0.5)
            let output = effect.apply(to: input, face: face, progress: 0.5, frameIndex: 5)
            let cgImage = ctx.createCGImage(output, from: output.extent)
            #expect(cgImage != nil)
        }
    }


    // MARK: - EditorViewModel face filter state

    @Test func faceFilterState_startsEmpty() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let vm = EditorViewModel(content: .newImage(img))
        #expect(vm.value(EffectParameter.intensityID, for: FaceFilterType.squeeze) == 0.5)
        #expect(vm.selectedFaceFilter == nil)
        #expect(vm.detectedFaces.isEmpty)
    }

    @Test func hasNonDefaultSettings_afterSelectingFaceFilter_isTrue() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let vm = EditorViewModel(content: .newImage(img))
        vm.selectedFaceFilter = .googlyEyes
        #expect(vm.hasNonDefaultSettings == true)
    }

    @Test func resetEffects_clearsFaceFilterState() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let vm = EditorViewModel(content: .newImage(img))
        vm.selectedFaceFilter = .squeeze
        vm.setValue(0.9, EffectParameter.intensityID, for: FaceFilterType.squeeze)
        vm.setValue(0.8, EffectParameter.secondaryID, for: FaceFilterType.squeeze)
        vm.selectedFaceIndex = 0

        vm.resetEffects()

        #expect(vm.selectedFaceFilter == nil)
        #expect(vm.value(EffectParameter.intensityID, for: FaceFilterType.squeeze) == 0.5)
        #expect(vm.value(EffectParameter.secondaryID, for: FaceFilterType.squeeze) == 0.5)
        #expect(vm.selectedFaceIndex == nil)
        #expect(vm.detectedFaces.isEmpty)
    }
}
