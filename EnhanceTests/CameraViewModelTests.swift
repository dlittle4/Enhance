import Testing
import UIKit
import AVFoundation
@testable import Enhance

/// Records calls and hands back canned frames; no AVFoundation session behind it.
@MainActor
private final class StubCameraService: CameraServing {
    var state: CameraSessionState = .idle
    var position: CameraPosition = .back
    var zoomOptions: [CameraZoomOption] = CameraZoomLadder.make(switchOverFactors: [2, 6], maxZoomFactor: 16)
    var currentZoomIndex = 1
    var onStateChange: ((CameraSessionState) -> Void)?

    var startCallCount = 0
    var stopCallCount = 0
    var captureResult: UIImage?

    func makePreviewUIView() -> UIView { UIView() }

    func start() async {
        startCallCount += 1
        state = .running
    }

    func stop() {
        stopCallCount += 1
        state = .idle
    }

    func cycleZoom() {
        currentZoomIndex = (currentZoomIndex + 1) % zoomOptions.count
    }

    func flip() async {
        position = position == .back ? .front : .back
        zoomOptions = CameraZoomLadder.make(switchOverFactors: [], maxZoomFactor: 4)
        currentZoomIndex = CameraZoomLadder.defaultIndex(in: zoomOptions)
    }

    func capturePhoto() async throws -> UIImage {
        guard let captureResult else { throw CameraServiceError.captureFailed }
        return captureResult
    }
}

@MainActor
struct CameraViewModelTests {

    /// A landscape frame tagged `.right`, the shape hardware hands back.
    private func rawCapture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let raw = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        return UIImage(cgImage: raw.cgImage!, scale: 1, orientation: .right)
    }

    // MARK: - Permission

    @Test func deniedPermission_neverStartsTheSession() async {
        let stub = StubCameraService()
        let vm = CameraViewModel(
            service: stub,
            authorizationStatus: { .denied },
            requestAccess: { true }
        )

        await vm.openCamera()

        #expect(vm.permission == .denied)
        #expect(stub.startCallCount == 0)
    }

    @Test func undeterminedPermission_requestsAndHonorsTheAnswer() async {
        let stub = StubCameraService()
        let vm = CameraViewModel(
            service: stub,
            authorizationStatus: { .notDetermined },
            requestAccess: { false }
        )

        await vm.openCamera()

        #expect(vm.permission == .denied)
        #expect(stub.startCallCount == 0)
    }

    @Test func grantedPermission_startsAndMirrorsTheLadder() async {
        let stub = StubCameraService()
        let vm = CameraViewModel(
            service: stub,
            authorizationStatus: { .authorized },
            requestAccess: { false }
        )

        await vm.openCamera()

        #expect(vm.permission == .granted)
        #expect(stub.startCallCount == 1)
        #expect(vm.sessionState == .running)
        #expect(vm.zoomLabel == "1X")
    }

    // MARK: - Capture

    @Test func capture_publishesAnUprightSquareAndStopsTheSession() async {
        let stub = StubCameraService()
        stub.state = .running
        stub.captureResult = rawCapture()
        let vm = CameraViewModel(service: stub, authorizationStatus: { .authorized }, requestAccess: { false })

        await vm.capture()

        let image = vm.capturedImage
        #expect(image != nil)
        #expect(image?.imageOrientation == .up)
        // 40×20 raw tagged `.right` → 20×40 upright → 20×20 square.
        #expect(image?.cgImage?.width == 20)
        #expect(image?.cgImage?.height == 20)
        #expect(stub.stopCallCount == 1)
    }

    @Test func capture_whileNotRunning_isIgnored() async {
        let stub = StubCameraService()
        stub.state = .idle
        stub.captureResult = rawCapture()
        let vm = CameraViewModel(service: stub, authorizationStatus: { .authorized }, requestAccess: { false })

        await vm.capture()

        #expect(vm.capturedImage == nil)
    }

    @Test func secondCapture_cannotReplaceTheFirst() async {
        let stub = StubCameraService()
        stub.state = .running
        stub.captureResult = rawCapture()
        let vm = CameraViewModel(service: stub, authorizationStatus: { .authorized }, requestAccess: { false })

        await vm.capture()
        let first = vm.capturedImage
        stub.state = .running
        await vm.capture()

        #expect(vm.capturedImage === first)
    }

    @Test func failedCapture_keepsTheViewfinderLive() async {
        let stub = StubCameraService()
        stub.state = .running
        stub.captureResult = nil
        let vm = CameraViewModel(service: stub, authorizationStatus: { .authorized }, requestAccess: { false })

        await vm.capture()

        #expect(vm.capturedImage == nil)
        #expect(vm.isCapturing == false)
        #expect(stub.stopCallCount == 0)
    }

    // MARK: - Controls

    @Test func cycleZoom_advancesTheMirroredLabel() async {
        let stub = StubCameraService()
        let vm = CameraViewModel(service: stub, authorizationStatus: { .authorized }, requestAccess: { false })

        vm.cycleZoom()

        #expect(vm.zoomLabel == "3X")
    }

    @Test func flip_resetsZoomToTheNewLadderDefault() async {
        let stub = StubCameraService()
        let vm = CameraViewModel(service: stub, authorizationStatus: { .authorized }, requestAccess: { false })
        vm.cycleZoom()

        await vm.flip()

        #expect(vm.position == .front)
        #expect(vm.zoomLabel == "1X")
    }
}
