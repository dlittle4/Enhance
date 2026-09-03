import Testing
import CoreGraphics
import UIKit
@testable import Enhance

/// STEERABLE ZOOM: the route model, the animator that travels it, and the editor session.
struct ZoomPathTests {

    private func route(_ pts: [(CGFloat, CGFloat)]) -> ZoomPath {
        ZoomPath(stops: pts.map { CGPoint(x: $0.0, y: $0.1) })
    }

    // MARK: - Model

    @Test func appendThinsPointsCloserThanSpacingAndClamps() {
        var path = ZoomPath()
        path.append(CGPoint(x: 0.1, y: 0.1), minimumSpacing: 0.05)
        path.append(CGPoint(x: 0.12, y: 0.1), minimumSpacing: 0.05)   // too close: dropped
        path.append(CGPoint(x: 0.3, y: 0.1), minimumSpacing: 0.05)
        path.append(CGPoint(x: 1.4, y: -0.2), minimumSpacing: 0.05)   // clamped to the edge
        #expect(path.stops.count == 3)
        #expect(path.stops.last == CGPoint(x: 1, y: 0))
    }

    @Test func arcLengthsAreNormalizedByDistanceNotStopCount() {
        let path = route([(0, 0), (0.1, 0), (1.0, 0)])
        let arcs = path.normalizedArcLengths
        #expect(arcs.count == 3)
        #expect(abs(arcs[1] - 0.1) < 1e-9)
        #expect(abs(arcs[2] - 1.0) < 1e-9)
    }

    @Test func pointTravelsTheLegsAtConstantSpeedWithoutDwell() {
        let path = route([(0, 0), (0.5, 0), (1, 0)])
        let quarter = path.point(at: 0.25, dwell: 0, smoothing: false)!
        let half = path.point(at: 0.5, dwell: 0, smoothing: false)!
        #expect(abs(quarter.x - 0.25) < 1e-9)
        #expect(abs(half.x - 0.5) < 1e-9)
        #expect(path.point(at: 0, dwell: 0, smoothing: false) == CGPoint(x: 0, y: 0))
        #expect(path.point(at: 1, dwell: 0, smoothing: false) == CGPoint(x: 1, y: 0))
    }

    @Test func dwellParksAtInteriorStops() {
        let path = route([(0, 0), (0.5, 0), (1, 0)])
        // 3 stops, one interior, dwell 0.2: legs take 0.4 each, the park is 0.4…0.6.
        let parked = path.point(at: 0.5, dwell: 0.2, smoothing: false)!
        #expect(abs(parked.x - 0.5) < 1e-9)
        let leaving = path.point(at: 0.7, dwell: 0.2, smoothing: false)!
        #expect(leaving.x > 0.5 && leaving.x < 1)
    }

    @Test func smoothingPassesThroughEveryStop() {
        let path = route([(0, 0), (0.5, 0.5), (1, 0)])
        let mid = path.point(at: 0.5, dwell: 0, smoothing: true)!
        #expect(abs(mid.x - 0.5) < 1e-6 && abs(mid.y - 0.5) < 1e-6)
    }

    @Test func singleStopHoldsAndEmptyIsNil() {
        #expect(route([(0.3, 0.7)]).point(at: 0.5, dwell: 0.1, smoothing: true) == CGPoint(x: 0.3, y: 0.7))
        #expect(ZoomPath().point(at: 0.5, dwell: 0, smoothing: true) == nil)
    }

    // MARK: - Animator

    private func context() -> GIFGenerator.DrawingContext {
        GIFGenerator.DrawingContext(
            normalizedImage: UIImage(),
            outputSize: CGSize(width: 600, height: 600),
            drawRect: CGRect(x: 0, y: 0, width: 600, height: 600),
            fullViewParams: .init(scale: 1, centerX: 300, centerY: 300),
            userZoomParams: .init(scale: 2, centerX: 400, centerY: 200),
            frameCount: 25, frameDelay: 0.04, pauseFrameCount: 1, pauseFrameDelay: 0.04
        )
    }

    @Test func pathAnimatorHoldsThePinchedScaleAndTravelsTheRoute() {
        let animator = PathAnimator(path: route([(0.3, 0.3), (0.7, 0.7)]), ease: 0, dwell: 0, smoothing: false)
        let start = animator.animationParameters(for: 0, in: context())
        let end = animator.animationParameters(for: 1, in: context())
        #expect(start.scale == 2 && end.scale == 2)
        #expect(abs(start.centerX - 180) < 1e-9 && abs(start.centerY - 180) < 1e-9)
        #expect(abs(end.centerX - 420) < 1e-9 && abs(end.centerY - 420) < 1e-9)
    }

    @Test func routeIsClampedSoTheFrameStaysInsideThePhoto() {
        // At 2× on a 600 square, the viewport is 300 wide: centres live in 0.25…0.75.
        let animator = PathAnimator(path: route([(0, 0), (1, 1)]), ease: 0, dwell: 0, smoothing: false)
        let start = animator.animationParameters(for: 0, in: context())
        let end = animator.animationParameters(for: 1, in: context())
        #expect(abs(start.centerX - 150) < 1e-9 && abs(start.centerY - 150) < 1e-9)
        #expect(abs(end.centerX - 450) < 1e-9 && abs(end.centerY - 450) < 1e-9)
        // At 1× the whole photo fits, so every stop centres.
        let c = PathAnimator.clampedCenter(CGPoint(x: 0.1, y: 0.9), scale: 1, drawRect: CGRect(x: 0, y: 0, width: 600, height: 600), outputSize: CGSize(width: 600, height: 600))
        #expect(c == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func pathAnimatorRampsScaleWhenAsked() {
        let animator = PathAnimator(path: route([(0, 0), (1, 1)]), ease: 0, dwell: 0, smoothing: false, scaleRamp: 1)
        #expect(abs(animator.animationParameters(for: 0, in: context()).scale - 1) < 1e-9)
        #expect(abs(animator.animationParameters(for: 1, in: context()).scale - 2) < 1e-9)
    }

    @Test func emptyPathDegradesToZoomIn() {
        let animator = PathAnimator(path: ZoomPath())
        let zoomIn = ZoomInAnimator()
        for p: CGFloat in [0, 0.3, 1] {
            let a = animator.animationParameters(for: p, in: context())
            let b = zoomIn.animationParameters(for: p, in: context())
            #expect(abs(a.scale - b.scale) < 1e-9 && abs(a.centerX - b.centerX) < 1e-9)
        }
    }

    @Test func pathCardIsHiddenUntilTheFlagIsOn() {
        let key = FeatureFlags.pathZoomKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(false, forKey: key)
        #expect(!AnimatorType.selectable.contains(.path))
        UserDefaults.standard.set(true, forKey: key)
        #expect(AnimatorType.selectable.contains(.path))
        #expect(AnimatorType.allCases.contains(.path))
    }

    // MARK: - Editor session

    @MainActor
    @Test func strokeRecordsOneUndoEntryAndClearIsUndoable() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.selectedAnimatorType = .path

        vm.beginZoomPathStroke()
        vm.extendZoomPath(to: CGPoint(x: 0.1, y: 0.1), minimumSpacing: 0.02)
        vm.extendZoomPath(to: CGPoint(x: 0.5, y: 0.5), minimumSpacing: 0.02)
        #expect(vm.isZoomPathActive)
        vm.endZoomPathStroke()
        #expect(!vm.isZoomPathActive)
        #expect(vm.zoomPath.stops.count == 2)
        #expect(vm.canUndo)

        vm.clearZoomPath()
        #expect(vm.zoomPath.isEmpty)
        vm.undo()
        #expect(vm.zoomPath.stops.count == 2)
        vm.undo()
        #expect(vm.zoomPath.isEmpty)
    }

    @MainActor
    @Test func activeAnimatorIsAPathAnimatorForThePathCard() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.selectedAnimatorType = .path
        #expect(vm.activeAnimator is PathAnimator)
        vm.selectedAnimatorType = .zoomIn
        #expect(vm.activeAnimator is ZoomInAnimator)
    }
}
