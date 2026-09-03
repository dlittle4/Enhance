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

    /// Drawing is a mode: PATH enters it, DONE leaves it (handing the canvas to the pinch and
    /// the GIF), EDIT PATH or the card again re-enters it, and another card leaves it.
    @MainActor
    @Test func pathDrawingIsAModeEnteredByTheCardAndLeftByDone() {
        let key = FeatureFlags.pathZoomKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)

        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.selectedEffectCategory = .zoomEffects
        vm.selectAnimator(.path)
        #expect(vm.isEditingZoomPath)
        #expect(vm.wantsZoomPath)
        #expect(vm.wantsLiveCanvas, "the photo stays up while drawing")

        vm.finishZoomPath()
        #expect(!vm.isEditingZoomPath)
        #expect(vm.showsZoomPathOverlay, "the route stays drawn")
        #expect(!vm.wantsZoomPath, "the finger goes back to the pinch")
        #expect(!vm.wantsLiveCanvas, "ENHANCE can show its GIF")

        vm.editZoomPath()
        #expect(vm.isEditingZoomPath)

        vm.selectAnimator(.zoomIn)
        #expect(!vm.isEditingZoomPath)
        #expect(!vm.showsZoomPathOverlay)

        vm.selectAnimator(.path)
        #expect(vm.isEditingZoomPath, "the card again re-enters drawing")
    }

    @MainActor
    @Test func doneHintShowsOnceARouteExistsUntilFinished() {
        let key = FeatureFlags.pathZoomKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)

        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.showControls = true
        vm.selectAnimator(.path)
        #expect(vm.showsZoomPathHint)
        #expect(!vm.showsZoomPathDoneHint)

        vm.beginZoomPathStroke()
        vm.extendZoomPath(to: CGPoint(x: 0.2, y: 0.2), minimumSpacing: 0.02)
        vm.extendZoomPath(to: CGPoint(x: 0.6, y: 0.6), minimumSpacing: 0.02)
        vm.endZoomPathStroke()
        #expect(!vm.showsZoomPathHint)
        #expect(vm.showsZoomPathDoneHint)

        vm.finishZoomPath()
        #expect(!vm.showsZoomPathDoneHint)
        vm.editZoomPath()
        #expect(!vm.showsZoomPathDoneHint, "retired for good once finished once")
    }

    // MARK: - Stop editing

    @Test func hitTestPrefersAStopThenTheRouteThenNothing() {
        let path = ZoomPath(stops: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)])
        let map: (CGPoint) -> CGPoint = { CGPoint(x: $0.x * 100, y: $0.y * 100) }
        #expect(path.hitTest(CGPoint(x: 12, y: 51), map: map, tolerance: 8) == .stop(0))
        #expect(path.hitTest(CGPoint(x: 88, y: 49), map: map, tolerance: 8) == .stop(1))
        if case .segment(let i, let f) = path.hitTest(CGPoint(x: 50, y: 52), map: map, tolerance: 8) {
            #expect(i == 0)
            #expect(abs(f - 0.5) < 0.05)
        } else {
            Issue.record("expected a segment hit")
        }
        #expect(path.hitTest(CGPoint(x: 50, y: 90), map: map, tolerance: 8) == .none)
    }

    @Test func insertPutsTheNewStopOnTheRouteAndRemoveTakesItOut() {
        var path = ZoomPath(stops: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)])
        let index = path.insert(onSegment: 0, f: 0.5)
        #expect(index == 1)
        #expect(path.stops.count == 3)
        #expect(abs(path.stops[1].x - 0.5) < 1e-6)
        path.move(stop: 1, to: CGPoint(x: 0.5, y: 0.3))
        #expect(path.stops[1] == CGPoint(x: 0.5, y: 0.3))
        path.remove(stop: 1)
        #expect(path.stops.count == 2)
        path.remove(stop: 7)
        #expect(path.stops.count == 2, "out of range is a no-op")
    }

    @MainActor
    @Test func touchingTheRouteInsertsAndSelectsAndDeleteIsUndoable() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.selectedAnimatorType = .path
        vm.zoomPath = ZoomPath(stops: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)])

        vm.beginZoomPathTouch(.segment(0, f: 0.5), at: CGPoint(x: 0.5, y: 0), minimumSpacing: 0.02)
        #expect(vm.zoomPath.stops.count == 3)
        #expect(vm.selectedZoomStop == 1)
        vm.moveZoomPathTouch(to: CGPoint(x: 0.5, y: 0.4), minimumSpacing: 0.02)
        vm.endZoomPathTouch()
        #expect(vm.zoomPath.stops[1] == CGPoint(x: 0.5, y: 0.4))
        #expect(vm.canUndo)

        vm.deleteSelectedZoomStop()
        #expect(vm.zoomPath.stops.count == 2)
        #expect(vm.selectedZoomStop == nil)
        vm.undo()
        #expect(vm.zoomPath.stops.count == 3)

        // A touch on empty photo deselects and draws, as before.
        vm.beginZoomPathTouch(.none, at: CGPoint(x: 0.2, y: 0.9), minimumSpacing: 0.02)
        #expect(vm.selectedZoomStop == nil)
        #expect(vm.zoomPath.stops.count == 4)
        vm.endZoomPathTouch()
    }

    // MARK: - Stop pause

    @Test func stopPauseLengthensTheGIFRatherThanEatingTheTravel() {
        // No interior stops: nothing to park at, speed passes through.
        let two = ZoomPathTiming.resolve(speed: 1, stopPause: 0.5, stopCount: 2)
        #expect(two.speed == 1 && two.dwell == 0)

        // 1s of travel plus two stops at 0.5s: a 2s GIF, a quarter of it parked at each stop.
        let four = ZoomPathTiming.resolve(speed: 1, stopPause: 0.5, stopCount: 4)
        #expect(abs(four.speed - 0.5) < 1e-9)
        #expect(abs(four.dwell - 0.25) < 1e-9)

        // Past the generator's 4s ceiling the pauses shrink to fit.
        let long = ZoomPathTiming.resolve(speed: 0.5, stopPause: 1.0, stopCount: 6)
        #expect(abs(long.speed - 0.25) < 1e-9)
        #expect(abs(long.dwell - (2.0 / 4) / 4) < 1e-9)
    }

    @MainActor
    @Test func stopPauseRidesTheSnapshotAndCountsAsAChange() {
        let vm = EditorViewModel(content: .newImage(UIImage()))
        vm.selectAnimator(.path)
        #expect(vm.isStopPauseAtDefault)
        vm.pushUndo()
        vm.stopPause = 0.8
        #expect(vm.hasNonDefaultSettings)
        #expect(abs(vm.generationSpeed - vm.playbackSpeed) < 1e-9, "no interior stops yet, so no lengthening")
        vm.undo()
        #expect(vm.isStopPauseAtDefault)
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
