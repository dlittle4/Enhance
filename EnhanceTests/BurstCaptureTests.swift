import Testing
import AVFoundation
import ImageIO
import UIKit
@testable import Enhance

/// BURST CAPTURE: frames are sampled and capped while the shutter is held, and the generator
/// plays a stack of real frames through in order.
struct BurstCaptureTests {

    /// A camera stub that lets a test push frames through the tap.
    @MainActor
    final class StubCamera: CameraServing {
        var state: CameraSessionState = .running
        var position: CameraPosition = .back
        var zoomOptions: [CameraZoomOption] = []
        var currentZoomIndex: Int = 0
        var onStateChange: ((CameraSessionState) -> Void)?
        var onPreviewFrame: ((CGImage) -> Void)?
        var framesEnabled = false
        var stopped = false
        func setPreviewFrames(_ enabled: Bool) { framesEnabled = enabled }
        func makePreviewUIView() -> UIView { UIView() }
        func start() async {}
        func stop() { stopped = true }
        func cycleZoom() {}
        func flip() async {}
        func capturePhoto() async throws -> UIImage { UIImage() }
    }

    private func frame(_ hue: CGFloat, side: Int = 80) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side + 20))
        return renderer.image { ctx in
            UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side + 20))
        }.cgImage!
    }

    @MainActor
    @Test func burstKeepsFramesAtTheSampleRateAndStopsTheCamera() async throws {
        let camera = StubCamera()
        let vm = CameraViewModel(service: camera, authorizationStatus: { .authorized }, requestAccess: { true })

        vm.beginBurst(fps: 1000, duration: 5)
        #expect(vm.isBursting)
        #expect(camera.framesEnabled)
        // Spaced past the 1ms sample interval: frames pushed in one instant thin to one.
        for i in 0..<6 {
            camera.onPreviewFrame?(frame(CGFloat(i) / 6))
            try await Task.sleep(for: .milliseconds(5))
        }

        let frames = await vm.endBurst()
        #expect(!vm.isBursting)
        #expect(!camera.framesEnabled)
        #expect(camera.stopped)
        let count = try #require(frames?.count)
        #expect(count == 6)
        // Every frame normalized to one exact square.
        let side = CanvasTuningStore.shared.tuning.burstFrameSide
        for f in frames ?? [] { #expect(f.size == CGSize(width: side, height: side)) }
        #expect(vm.capturedImage != nil)
        #expect(vm.capturedBurst?.count == 6)
    }

    @MainActor
    @Test func tooShortAHoldYieldsNothingSoATapCanStillTakeAPhoto() async {
        let camera = StubCamera()
        let vm = CameraViewModel(service: camera, authorizationStatus: { .authorized }, requestAccess: { true })
        vm.beginBurst(fps: 1000, duration: 5)
        camera.onPreviewFrame?(frame(0.2))
        camera.onPreviewFrame?(frame(0.4))
        let frames = await vm.endBurst()
        #expect(frames == nil)
        #expect(vm.capturedImage == nil)
        #expect(!camera.stopped)
    }

    @MainActor
    @Test func sampleRateThinsFramesThatArriveTooFast() async {
        let camera = StubCamera()
        let vm = CameraViewModel(service: camera, authorizationStatus: { .authorized }, requestAccess: { true })
        // 1 fps: a burst of frames within the same instant keeps only the first.
        vm.beginBurst(fps: 1, duration: 5)
        for i in 0..<10 { camera.onPreviewFrame?(frame(CGFloat(i) / 10)) }
        // Not enough kept to count as a burst.
        let frames = await vm.endBurst()
        #expect(frames == nil)
    }

    // MARK: - Generator

    @Test func burstIndexStretchesTheStackOverTheOutput() {
        #expect(GIFGenerator.burstIndex(forOutputFrame: 0, of: 25, burstCount: 6) == 0)
        #expect(GIFGenerator.burstIndex(forOutputFrame: 24, of: 25, burstCount: 6) == 5)
        #expect(GIFGenerator.burstIndex(forOutputFrame: 12, of: 25, burstCount: 6) == 3)
        #expect(GIFGenerator.burstIndex(forOutputFrame: 5, of: 25, burstCount: 1) == 0)
    }

    @Test func gifFromABurstChangesSourceOverTime() throws {
        let generator = GIFGenerator()
        let red = UIImage(cgImage: frame(0.0, side: 120))
        let blue = UIImage(cgImage: frame(0.66, side: 120))
        let square = { (img: UIImage) in CameraImageProcessor.centerSquareCrop(img) }
        let frames = [BurstFrame(image: square(red)), BurstFrame(image: square(red)), BurstFrame(image: square(blue)), BurstFrame(image: square(blue))]

        let data = try #require(generator.generateGIF(
            frames: frames, currentScale: 1, visibleRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            animator: StaticAnimator(), speed: 1, pauseDuration: 0.1,
            visualEffects: [], faceEffect: nil, textOverlay: nil
        ))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let count = CGImageSourceGetCount(source)
        #expect(count > 4)

        func redAt(_ index: Int) -> Int {
            let cg = CGImageSourceCreateImageAtIndex(source, index, nil)!
            let ci = CIImage(cgImage: cg)
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(ci, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 300, y: 300, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return Int(px[0])
        }
        #expect(redAt(0) > 180, "first frame should be red")
        #expect(redAt(count - 1) < 80, "last frame should be blue")
    }

    @Test func stillPathIsUnchangedByTheFramesOverload() throws {
        let generator = GIFGenerator()
        let img = CameraImageProcessor.centerSquareCrop(UIImage(cgImage: frame(0.3, side: 120)))
        let one = generator.generateGIF(frames: [BurstFrame(image: img)], currentScale: 1, visibleRect: CGRect(x: 0, y: 0, width: 1, height: 1), animator: StaticAnimator(), speed: 1, pauseDuration: 0.1, visualEffects: [], faceEffect: nil, textOverlay: nil)
        let still = generator.generateGIF(from: img, currentScale: 1, visibleRect: CGRect(x: 0, y: 0, width: 1, height: 1), animator: StaticAnimator(), speed: 1, pauseDuration: 0.1)
        #expect(one?.count == still?.count)
    }

    // MARK: - Device-pass regressions

    /// A hold that outlasts the burst used to freeze the viewfinder and go nowhere: the
    /// auto-stop took the frames, and the lift found nothing to do. The finished burst now
    /// waits for the lift, once.
    @MainActor
    @Test func aBurstTheAutoStopFinishesWaitsForTheLiftToHandOff() async throws {
        let camera = StubCamera()
        let vm = CameraViewModel(service: camera, authorizationStatus: { .authorized }, requestAccess: { true })
        vm.beginBurst(fps: 1000, duration: 0.25)
        for i in 0..<6 {
            camera.onPreviewFrame?(frame(CGFloat(i) / 6))
            try await Task.sleep(for: .milliseconds(8))
        }
        // Past the duration: the auto-stop task ends the burst on its own.
        try await Task.sleep(for: .milliseconds(450))
        #expect(!vm.isBursting)
        #expect(vm.capturedImage != nil)

        #expect(vm.burstHandoffToken == 1)
        let handed = vm.takePendingBurstHandoff()
        #expect(handed?.count == 6)
        #expect(vm.takePendingBurstHandoff() == nil, "consumed once")
    }

    /// A burst the lift ends is handed off the same way — the token bumps, not a callback.
    @MainActor
    @Test func aBurstTheLiftEndsBumpsTheHandoffTokenAndCountsFrames() async throws {
        let camera = StubCamera()
        let vm = CameraViewModel(service: camera, authorizationStatus: { .authorized }, requestAccess: { true })
        vm.beginBurst(fps: 1000, duration: 5)
        for i in 0..<5 {
            camera.onPreviewFrame?(frame(CGFloat(i) / 5))
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(vm.burstFrameCount == 5)
        #expect(vm.burstHandoffToken == 0)
        let frames = await vm.endBurst()
        #expect(frames?.count == 5)
        #expect(vm.burstHandoffToken == 1)
        #expect(vm.takePendingBurstHandoff()?.count == 5)
    }

    /// The live canvas plays the burst: with no effect it shows the raw frame under the
    /// index, and with an effect pending it holds frame 0's preview rather than flashing raw.
    @MainActor
    @Test func canvasImagePlaysTheBurstAndHoldsThePreviewWhileRendering() {
        let a = UIImage(cgImage: frame(0.1))
        let b = UIImage(cgImage: frame(0.5))
        let vm = EditorViewModel(content: .newImage(a))
        #expect(vm.canvasImage == nil, "a still with no effect draws the photo itself")

        vm.adoptBurst([a, b])
        #expect(vm.burstFrames?.count == 2)
        #expect(vm.canvasImage === a)

        vm.adoptBurst(nil)
        #expect(vm.burstFrames == nil)
        #expect(vm.canvasImage == nil)
    }

    /// The generator is handed a snapshot of the burst rather than reading the live arrays.
    @MainActor
    @Test func burstSourceFramesSnapshotCarriesEveryFrame() {
        let a = UIImage(cgImage: frame(0.1))
        let b = UIImage(cgImage: frame(0.5))
        let c = UIImage(cgImage: frame(0.9))
        let vm = EditorViewModel(content: .newImage(a))
        vm.adoptBurst([a, b, c])
        let snapshot = vm.burstSourceFrames
        #expect(snapshot?.count == 3)
        #expect(snapshot?[2].image === c)
    }
}
