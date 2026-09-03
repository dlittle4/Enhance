import SwiftUI
import UIKit

/// A zoomable/pannable image canvas backed by UIScrollView for
/// hardware-accelerated, 60fps pinch/zoom. Face markers are rendered as UIKit
/// subviews with tap recognizers — see `FaceMarkerView` for how they draw, and
/// `FaceMarkerOptions` for the experiments that change it.
struct ImageCanvasView: View {
    let image: UIImage
    /// BURST CAPTURE: frames for the canvas to cycle at `playbackFPS` in place of `image`.
    /// Played by the coordinator on its own timer so SwiftUI is never re-evaluated for a
    /// frame change. `image` still supplies the geometry and the still shown when nil.
    var playbackFrames: [UIImage]? = nil
    var playbackFPS: Double = 12
    @Binding var scale: CGFloat
    @Binding var visibleRect: CGRect
    var faceMarkers: [FaceMarker] = []

    /// Which face-marker experiments are on, and the knobs FACE MARKER LAB edits. Defaulted to the
    /// unchanged overlay so the zoom and text call sites need not care.
    ///
    /// Declared between the markers and the tap callback deliberately: the memberwise initialiser
    /// takes its order from here, and the editor's call site reads in this order.
    var markerOptions: FaceMarkerOptions = .legacy
    var markerTuning: FaceMarkerTuning = .default

    var onFaceSelected: ((Int) -> Void)? = nil

    /// The text overlay to render over the photo, and whether the TEXT category is active (so it
    /// is interactive rather than a static at-rest preview). Both default to inert, so the
    /// existing face-filter and zoom call sites are unchanged.
    var textOverlay: Binding<TextOverlay?> = .constant(nil)
    var isTextInteractive: Bool = false
    /// Gesture-session hooks — one undo entry and one regeneration per burst — and the double-tap
    /// that reopens the keyboard.
    var onTextGestureBegan: (() -> Void)? = nil
    var onTextGestureEnded: (() -> Void)? = nil
    var onRequestTextEditing: (() -> Void)? = nil

    /// Whether a one-finger touch on the photo aims the lazers, and where they currently point.
    /// Inert by default so every other call site is unchanged. While this is on, the photo pans
    /// with **two** fingers — one finger is the aim — and pinch-to-zoom is untouched.
    var isLaserAimInteractive: Bool = false
    var laserAim: Binding<LaserAim?> = .constant(nil)
    var onLaserAimBegan: (() -> Void)? = nil
    var onLaserAimEnded: (() -> Void)? = nil

    /// STEERABLE ZOOM: a one-finger touch lays down PATH stops. Shares the aim's recogniser and
    /// two-finger pan; the two modes are exclusive by construction (different tabs).
    var isZoomPathInteractive: Bool = false
    /// The route, for hit-testing a touch against its stops and legs while editing.
    var zoomPath: ZoomPath = ZoomPath()
    /// Fired on touch-down with what the finger landed on, in the photo's normalized space.
    var onZoomPathTouchDown: ((ZoomPathHit, CGPoint) -> Void)? = nil
    /// Normalized, top-left-origin — `visibleRect` space. Called on touch-down and every move.
    var onZoomPathPoint: ((CGPoint) -> Void)? = nil
    /// The region of the photo the scroll view is showing **right now**, kept honest through
    /// layout as well as scrolling. Distinct from `visibleRect`, which is the *framing* — an
    /// existing GIF opens with its saved 3× framing in that binding while the live canvas shows
    /// the whole photo at 1×, and `generationFraming` relies on the saved value surviving. An
    /// overlay that draws on the photo needs what is on screen, not what will be generated.
    var displayedRect: Binding<CGRect> = .constant(CGRect(x: 0, y: 0, width: 1, height: 1))
    var onZoomPathBegan: (() -> Void)? = nil
    var onZoomPathEnded: (() -> Void)? = nil

    /// Fired the first time — and every time — the user works the canvas by hand.
    ///
    /// Driven from the scroll view's `willBegin` delegate callbacks rather than from
    /// `scale` or `visibleRect` changing, because those two are also written
    /// *programmatically*: an existing GIF restores its saved zoom on open, and the
    /// ENHANCE nag bounces the scale to hint at pinching. Neither is the user touching
    /// the photo, and a value-based signal cannot tell the difference.
    var onInteraction: (() -> Void)? = nil

    /// Fired when a canvas gesture settles. Separate from `onInteraction` because some
    /// work should happen once the framing is final rather than on every delegate
    /// callback under the user's fingers.
    var onInteractionEnded: (() -> Void)? = nil

    /// Side of the square canvas. A parameter rather than a constant since the editor sizes the
    /// canvas from the screen's 24pt margins *(2026-08-15)*; the default keeps previews and any
    /// fixed-size call site working.
    var canvasSize: CGFloat = 325

    var body: some View {
        ZStack {
            ScrollableCanvasView(
                image: image,
                playbackFrames: playbackFrames,
                playbackFPS: playbackFPS,
                scale: $scale,
                visibleRect: $visibleRect,
                faceMarkers: faceMarkers,
                markerOptions: markerOptions,
                markerTuning: markerTuning,
                onFaceSelected: onFaceSelected,
                onInteraction: onInteraction,
                onInteractionEnded: onInteractionEnded,
                textOverlay: textOverlay,
                isTextInteractive: isTextInteractive,
                onTextGestureBegan: onTextGestureBegan,
                onTextGestureEnded: onTextGestureEnded,
                onRequestTextEditing: onRequestTextEditing,
                isLaserAimInteractive: isLaserAimInteractive,
                laserAim: laserAim,
                onLaserAimBegan: onLaserAimBegan,
                onLaserAimEnded: onLaserAimEnded,
                isZoomPathInteractive: isZoomPathInteractive,
                zoomPath: zoomPath,
                onZoomPathTouchDown: onZoomPathTouchDown,
                onZoomPathPoint: onZoomPathPoint,
                onZoomPathBegan: onZoomPathBegan,
                onZoomPathEnded: onZoomPathEnded,
                displayedRect: displayedRect,
                canvasSize: canvasSize
            )

            ZoomFrameOverlay(image: image, visibleRect: visibleRect, scale: scale)
                .frame(width: canvasSize, height: canvasSize)
                .allowsHitTesting(false)
        }
        .frame(width: canvasSize, height: canvasSize)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous))
    }
}

// MARK: - UIScrollView-backed canvas

private struct ScrollableCanvasView: UIViewRepresentable {
    let image: UIImage
    var playbackFrames: [UIImage]?
    var playbackFPS: Double
    @Binding var scale: CGFloat
    @Binding var visibleRect: CGRect
    var faceMarkers: [FaceMarker]
    var markerOptions: FaceMarkerOptions
    var markerTuning: FaceMarkerTuning
    var onFaceSelected: ((Int) -> Void)?
    var onInteraction: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    var textOverlay: Binding<TextOverlay?>
    var isTextInteractive: Bool
    var onTextGestureBegan: (() -> Void)?
    var onTextGestureEnded: (() -> Void)?
    var onRequestTextEditing: (() -> Void)?
    var isLaserAimInteractive: Bool
    var laserAim: Binding<LaserAim?>
    var onLaserAimBegan: (() -> Void)?
    var onLaserAimEnded: (() -> Void)?
    var isZoomPathInteractive: Bool
    var zoomPath: ZoomPath
    var onZoomPathTouchDown: ((ZoomPathHit, CGPoint) -> Void)?
    var onZoomPathPoint: ((CGPoint) -> Void)?
    var onZoomPathBegan: (() -> Void)?
    var onZoomPathEnded: (() -> Void)?
    var displayedRect: Binding<CGRect>
    let canvasSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // One representable, two siblings inside a container: routing needs a common ancestor that
    // sees a touch before either sibling does (§8.2). The scroll view keeps its exact
    // configuration — moved verbatim — because `updateUIView` must not disturb its scroll state.
    func makeUIView(context: Context) -> CanvasContainerView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = AppConstants.Zoom.maxScale
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        configureContentSize(scrollView: scrollView, imageView: imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // The aim: a long press with no minimum duration, which is UIKit's "track the finger
        // from touch-down" recognizer — one recogniser covers both a tap and a drag, and it
        // begins on contact rather than after a movement threshold, so the beams swing the
        // instant the photo is touched. Disabled until LAZER EYES asks for it.
        let aim = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleAim(_:)))
        aim.minimumPressDuration = 0
        aim.allowableMovement = .greatestFiniteMagnitude
        aim.numberOfTouchesRequired = 1
        aim.delegate = context.coordinator
        aim.isEnabled = false
        scrollView.addGestureRecognizer(aim)
        context.coordinator.aimRecognizer = aim

        context.coordinator.canvasSize = canvasSize

        let textHost = TextOverlayHostView()
        textHost.canvasSide = canvasSize
        textHost.onOverlayChanged = { [weak coordinator = context.coordinator] o in
            coordinator?.parent.textOverlay.wrappedValue = o
        }
        textHost.onGestureBegan = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTextGestureBegan?()
        }
        textHost.onGestureEnded = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTextGestureEnded?()
        }
        textHost.onRequestEditing = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRequestTextEditing?()
        }
        context.coordinator.textHost = textHost

        let container = CanvasContainerView(scrollView: scrollView, textHost: textHost)
        container.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.publishDisplayedRect(scrollView)
        }
        return container
    }

    func updateUIView(_ container: CanvasContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if let imageView = coordinator.imageView {
            coordinator.updatePlayback(frames: playbackFrames, fps: playbackFPS, still: image, on: imageView)
            coordinator.updateFaceMarkers(on: imageView)
        }

        if let textHost = coordinator.textHost {
            textHost.isInteractive = isTextInteractive
            textHost.update(overlay: textOverlay.wrappedValue, canvasSide: canvasSize)
        }

        coordinator.setTouchInteractive(isLaserAimInteractive || isZoomPathInteractive, in: container)
    }

    private func configureContentSize(scrollView: UIScrollView, imageView: UIImageView) {
        let fillScale = max(canvasSize / image.size.width, canvasSize / image.size.height)
        let contentW = image.size.width * fillScale
        let contentH = image.size.height * fillScale
        imageView.frame = CGRect(x: 0, y: 0, width: contentW, height: contentH)
        scrollView.contentSize = CGSize(width: contentW, height: contentH)

        let offsetX = max(0, (contentW - canvasSize) / 2)
        let offsetY = max(0, (contentH - canvasSize) / 2)
        if scrollView.zoomScale <= 1.0 {
            scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ScrollableCanvasView
        weak var imageView: UIImageView?
        weak var textHost: TextOverlayHostView?
        weak var aimRecognizer: UILongPressGestureRecognizer?
        var canvasSize: CGFloat = 325

        /// Set once a second finger joins an aim. From then on the touch is a pinch, and the
        /// target must not chase the recogniser's (now averaged) location.
        private var aimSurrenderedToPinch = false

        // MARK: Burst playback

        private var playbackFrames: [UIImage] = []
        private var playbackIndex = 0
        private var playbackTimer: Timer?

        /// Shows `still`, or cycles `frames` at `fps`. A new stack (a different first frame or
        /// count) restarts from its first frame; the same stack keeps its place, so SwiftUI
        /// re-evaluating the canvas for an unrelated reason does not stutter the playback.
        func updatePlayback(frames: [UIImage]?, fps: Double, still: UIImage, on imageView: UIImageView) {
            guard let frames, frames.count > 1 else {
                if playbackTimer != nil {
                    playbackTimer?.invalidate()
                    playbackTimer = nil
                    playbackFrames = []
                    playbackIndex = 0
                }
                if imageView.image !== still { imageView.image = still }
                return
            }
            let sameStack = frames.count == playbackFrames.count && frames.first === playbackFrames.first
            if sameStack, playbackTimer != nil { return }
            playbackTimer?.invalidate()
            playbackFrames = frames
            playbackIndex = min(playbackIndex, frames.count - 1)
            imageView.image = frames[playbackIndex]
            let interval = 1 / max(1, fps)
            playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self, weak imageView] _ in
                guard let self, let imageView, !self.playbackFrames.isEmpty else { return }
                self.playbackIndex = (self.playbackIndex + 1) % self.playbackFrames.count
                imageView.image = self.playbackFrames[self.playbackIndex]
            }
        }

        private var faceMarkerViews: [FaceMarkerView] = []
        private let spotlight = FaceSpotlightLayer()

        /// Fires once the markers have been up, untouched, for `autoHideDelay`. Invalidated and
        /// restarted by any canvas touch, so the countdown measures *inattention* rather than time
        /// on screen.
        private var autoHideTimer: Timer?

        private let mintGreen = UIColor.enhanceMint

        deinit {
            autoHideTimer?.invalidate()
            playbackTimer?.invalidate()
        }

        init(parent: ScrollableCanvasView) {
            self.parent = parent
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            parent.onInteraction?()
            revealMarkers()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onInteraction?()
            revealMarkers()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
            syncBindings(scrollView)
            refreshMarkerScale()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            syncBindings(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            syncBindings(scrollView)
            parent.onInteractionEnded?()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            // Deferred to `didEndDecelerating` when the pan is still coasting, so the
            // framing is only published once it has actually come to rest.
            if !decelerate { parent.onInteractionEnded?() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            parent.onInteractionEnded?()
        }

        // MARK: Bindings

        private func syncBindings(_ scrollView: UIScrollView) {
            let zoom = scrollView.zoomScale
            if abs(parent.scale - zoom) > 0.001 {
                parent.scale = zoom
            }

            let contentW = scrollView.contentSize.width
            let contentH = scrollView.contentSize.height
            let viewW = scrollView.bounds.width
            let viewH = scrollView.bounds.height

            // **Bounds too, not just content.** A delegate callback can arrive while the scroll
            // view is still being laid out, when `bounds` is `.zero` — and the arithmetic below
            // then yields a rect of zero size whose origin is the at-rest centring offset. Its
            // *centre* is what the generator reads, and for a portrait photo that centre came out
            // around (0, 0.12) instead of (0.5, 0.5), which the generator renders as a translation
            // right and down. Visible only without a zoom type, because `StaticAnimator` uses that
            // framing for every frame while the zoom animators start from the full view.
            guard contentW > 0, contentH > 0, viewW > 0, viewH > 0 else { return }

            let normalizedX = scrollView.contentOffset.x / contentW
            let normalizedY = scrollView.contentOffset.y / contentH
            let normalizedW = min(1.0, viewW / contentW)
            let normalizedH = min(1.0, viewH / contentH)

            let newRect = CGRect(
                x: max(0, min(1 - normalizedW, normalizedX)),
                y: max(0, min(1 - normalizedH, normalizedY)),
                width: normalizedW,
                height: normalizedH
            )

            if !rectsAreClose(parent.visibleRect, newRect) {
                parent.visibleRect = newRect
            }
            if !rectsAreClose(parent.displayedRect.wrappedValue, newRect) {
                parent.displayedRect.wrappedValue = newRect
            }
        }

        /// What the scroll view shows, published without touching `visibleRect`. Called from the
        /// container's layout, which is the one moment the framing binding must *not* follow the
        /// scroll view (see `ImageCanvasView.displayedRect`).
        func publishDisplayedRect(_ scrollView: UIScrollView) {
            let contentW = scrollView.contentSize.width
            let contentH = scrollView.contentSize.height
            let viewW = scrollView.bounds.width
            let viewH = scrollView.bounds.height
            guard contentW > 0, contentH > 0, viewW > 0, viewH > 0 else { return }
            let w = min(1.0, viewW / contentW)
            let h = min(1.0, viewH / contentH)
            let rect = CGRect(
                x: max(0, min(1 - w, scrollView.contentOffset.x / contentW)),
                y: max(0, min(1 - h, scrollView.contentOffset.y / contentH)),
                width: w, height: h
            )
            guard !rectsAreClose(parent.displayedRect.wrappedValue, rect) else { return }
            // Off the layout pass: writing SwiftUI state from inside layoutSubviews is a
            // state-modified-during-update warning waiting to happen.
            DispatchQueue.main.async { [weak self] in
                self?.parent.displayedRect.wrappedValue = rect
            }
        }

        private func rectsAreClose(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.origin.x - b.origin.x) < 0.001 &&
            abs(a.origin.y - b.origin.y) < 0.001 &&
            abs(a.width - b.width) < 0.001 &&
            abs(a.height - b.height) < 0.001
        }

        private func centerContent(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let boundsSize = scrollView.bounds.size
            let contentsSize = imageView.frame.size

            let horizontalInset = max(0, (boundsSize.width - contentsSize.width) / 2)
            let verticalInset = max(0, (boundsSize.height - contentsSize.height) / 2)

            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset, left: horizontalInset,
                bottom: verticalInset, right: horizontalInset
            )
        }

        // MARK: Lazer aim

        /// Turns the one-finger canvas touch (aim or path) on or off, and moves the photo's pan
        /// to two fingers while it is on.
        ///
        /// The pan's touch count is the only scroll-view setting touched, and it is restored
        /// the moment the mode ends, so every other category keeps the one-finger pan it has
        /// always had. Pinch is a separate recogniser and is never changed.
        func setTouchInteractive(_ interactive: Bool, in container: CanvasContainerView) {
            guard let aimRecognizer, aimRecognizer.isEnabled != interactive else { return }
            aimRecognizer.isEnabled = interactive
            container.scrollView.panGestureRecognizer.minimumNumberOfTouches = interactive ? 2 : 1
        }

        @objc func handleAim(_ recognizer: UILongPressGestureRecognizer) {
            guard let imageView else { return }
            if parent.isZoomPathInteractive { handlePath(recognizer, in: imageView); return }

            switch recognizer.state {
            case .began:
                // Nothing is published yet. Two fingers rarely land in the same frame, so a
                // pinch arrives here as one finger first — publishing now would flick the
                // target to wherever that finger was before the second one surrendered the
                // gesture. The first single-finger move or the lift publishes instead, which
                // a finger cannot tell apart from touch-down.
                aimSurrenderedToPinch = false
                parent.onInteraction?()
                revealMarkers()
                parent.onLaserAimBegan?()
                HapticService.light()
            case .changed:
                guard !aimSurrenderedToPinch else { return }
                if recognizer.numberOfTouches > 1 {
                    aimSurrenderedToPinch = true
                    return
                }
                publishAim(recognizer.location(in: imageView), in: imageView)
            case .ended:
                if !aimSurrenderedToPinch {
                    publishAim(recognizer.location(in: imageView), in: imageView)
                    // The "fire": heavier than the touch-down, so lifting off feels like a trigger.
                    HapticService.medium()
                }
                parent.onLaserAimEnded?()
            case .cancelled, .failed:
                parent.onLaserAimEnded?()
            default:
                break
            }
        }

        /// The PATH stroke. Unlike the aim, touch-down publishes immediately: a tap is a stop,
        /// and a stop under the first finger of a pinch is one undo away rather than a flicked
        /// target. A second finger still surrenders the rest of the stroke to the pinch.
        private func handlePath(_ recognizer: UILongPressGestureRecognizer, in imageView: UIImageView) {
            func normalized() -> CGPoint? {
                let size = imageView.bounds.size
                guard size.width > 0, size.height > 0 else { return nil }
                let p = recognizer.location(in: imageView)
                return CGPoint(x: p.x / size.width, y: p.y / size.height)
            }
            switch recognizer.state {
            case .began:
                aimSurrenderedToPinch = false
                parent.onInteraction?()
                parent.onZoomPathBegan?()
                HapticService.light()
                if let p = normalized() {
                    // Hit-tested in the image view's own coordinates, where a screen point is
                    // `1 / zoom` of a content point — so the 22pt target stays 22pt on screen
                    // however far the photo is pinched.
                    let size = imageView.bounds.size
                    let tolerance = 22 / max(0.01, currentZoomScale)
                    let hit = parent.zoomPath.hitTest(
                        recognizer.location(in: imageView),
                        map: { CGPoint(x: $0.x * size.width, y: $0.y * size.height) },
                        tolerance: tolerance
                    )
                    parent.onZoomPathTouchDown?(hit, p)
                }
            case .changed:
                guard !aimSurrenderedToPinch else { return }
                if recognizer.numberOfTouches > 1 { aimSurrenderedToPinch = true; return }
                if let p = normalized() { parent.onZoomPathPoint?(p) }
            case .ended:
                if !aimSurrenderedToPinch { HapticService.medium() }
                parent.onZoomPathEnded?()
            case .cancelled, .failed:
                parent.onZoomPathEnded?()
            default:
                break
            }
        }

        private func publishAim(_ location: CGPoint, in imageView: UIImageView) {
            guard let aim = LaserAim.from(canvasPoint: location, in: imageView.bounds.size) else { return }
            if parent.laserAim.wrappedValue != aim {
                parent.laserAim.wrappedValue = aim
            }
        }

        // MARK: UIGestureRecognizerDelegate

        /// A touch that lands on a face marker is a face selection, not an aim. Refusing it here
        /// — rather than ordering the recognisers — keeps the marker's own tap exactly as fast as
        /// it is under every other filter.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === aimRecognizer else { return true }
            var view = touch.view
            while let current = view {
                if current is FaceMarkerView { return false }
                view = current.superview
            }
            return true
        }

        /// The aim runs alongside the pinch (so two fingers landing mid-aim still zoom) and the
        /// double-tap (so double-tap-to-zoom survives; it also aims, which is harmless).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gestureRecognizer === aimRecognizer || other === aimRecognizer
        }

        // MARK: Double-tap

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            parent.onInteraction?()

            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let location = recognizer.location(in: imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / 2.0,
                    height: scrollView.bounds.height / 2.0
                )
                let rect = CGRect(
                    x: location.x - size.width / 2,
                    y: location.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

        // MARK: Face Markers

        func updateFaceMarkers(on imageView: UIImageView) {
            let markers = parent.faceMarkers
            let options = parent.markerOptions
            let tuning = parent.markerTuning
            let contentW = imageView.bounds.width
            let contentH = imageView.bounds.height

            while faceMarkerViews.count > markers.count {
                faceMarkerViews.removeLast().removeFromSuperview()
            }
            while faceMarkerViews.count < markers.count {
                let view = FaceMarkerView()
                imageView.addSubview(view)
                faceMarkerViews.append(view)
            }

            for (index, marker) in markers.enumerated() {
                let view = faceMarkerViews[index]
                view.frame = frame(for: marker.rect, contentW: contentW, contentH: contentH)
                view.configure(
                    marker: marker,
                    options: options,
                    tuning: tuning,
                    tint: mintGreen,
                    contentScale: currentZoomScale,
                    onTap: { [weak self] idx in
                        self?.parent.onFaceSelected?(idx)
                    }
                )
            }

            updateSpotlight(on: imageView)
            revealMarkers()
        }

        /// Vision's rect is normalized with a **bottom-left** origin; UIKit's is top-left. The flip
        /// is why this is a named function rather than four lines inlined — it was the one piece of
        /// the old `updateFaceBoxes` worth keeping verbatim.
        private func frame(for normalized: CGRect, contentW: CGFloat, contentH: CGFloat) -> CGRect {
            let topY = 1.0 - normalized.origin.y - normalized.height
            return CGRect(
                x: normalized.origin.x * contentW,
                y: topY * contentH,
                width: normalized.width * contentW,
                height: normalized.height * contentH
            )
        }

        /// The spotlight sits under every marker, so brackets and the index chip stay legible over
        /// the dimmed region.
        private func updateSpotlight(on imageView: UIImageView) {
            guard let rect = FaceMarkerPlan.spotlightRect(in: parent.faceMarkers, options: parent.markerOptions) else {
                spotlight.hide()
                return
            }

            if spotlight.superlayer !== imageView.layer {
                imageView.layer.insertSublayer(spotlight, at: 0)
            }

            let content = CGRect(origin: .zero, size: imageView.bounds.size)
            let markerRect = parent.markerTuning.markerRect(
                for: frame(for: rect, contentW: imageView.bounds.width, contentH: imageView.bounds.height)
            )
            spotlight.update(spotlighting: markerRect, in: content, tuning: parent.markerTuning)
        }

        private var currentZoomScale: CGFloat {
            (imageView?.superview as? UIScrollView)?.zoomScale ?? 1
        }

        /// Keeps the chrome a constant size on screen through a pinch. Deliberately does not
        /// re-run `configure` — that would re-evaluate selection and restart animations on every
        /// frame of the gesture.
        private func refreshMarkerScale() {
            let scale = currentZoomScale
            for view in faceMarkerViews {
                view.updateContentScale(scale)
            }
            if let imageView {
                updateSpotlight(on: imageView)
            }
        }

        // MARK: Auto-hide

        /// Brings the markers back and restarts the countdown. Called on every canvas touch, which
        /// is the signal that the user is looking at the photo again.
        func revealMarkers() {
            autoHideTimer?.invalidate()

            let delay = parent.markerTuning.autoHideDelay
            guard parent.markerOptions.calm, delay > 0, !faceMarkerViews.isEmpty else {
                setMarkerAlpha(1)
                return
            }

            setMarkerAlpha(1)
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                let resting = CGFloat(max(0, min(1, self.parent.markerTuning.restingOpacity)))
                UIView.animate(withDuration: 0.35) {
                    self.setMarkerAlpha(resting)
                }
            }
        }

        /// Alpha only — the views stay in the hierarchy and stay tappable. A marker that has faded
        /// out has stopped *asking* for attention, which is not the same as being gone: tapping the
        /// face it covers still selects that face.
        private func setMarkerAlpha(_ alpha: CGFloat) {
            for view in faceMarkerViews {
                view.alpha = alpha
            }
        }
    }
}

// MARK: - CanvasContainerView

/// Root of the canvas representable: holds the scroll view and the text host as siblings and
/// arbitrates the first touch of every sequence between them (§8.2, §8.3).
///
/// The scroll view's recognizers are **never disabled** — the photo pans and zooms exactly as under
/// every other category. Routing happens here, in `hitTest`, by deciding once on the first touch of
/// a sequence and holding that decision until every touch lifts. Holding it is the whole point: a
/// two-finger pinch with one finger on the text and one off it would otherwise split, and neither
/// recognizer would ever see two touches.
final class CanvasContainerView: UIView {
    let scrollView: UIScrollView
    private let textHost: TextOverlayHostView
    private var router = TextTouchRouter()
    /// Fired after the scroll view has its frame, so the displayed region can be published.
    var onLayout: (() -> Void)?

    init(scrollView: UIScrollView, textHost: TextOverlayHostView) {
        self.scrollView = scrollView
        self.textHost = textHost
        super.init(frame: .zero)
        addSubview(scrollView)
        addSubview(textHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        textHost.frame = bounds
        onLayout?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Everything that is not a live text gesture goes to the photo, explicitly.
        //
        // Never fall through to `super.hitTest` here. The text host is the topmost full-canvas
        // subview, so the default reverse-order search would hand it every touch and the photo
        // would stop panning and zooming entirely — in *all* categories, not just TEXT.
        guard textHost.isInteractive,
              let region = textHost.hitRegion,
              let touches = event?.allTouches else {
            return photoTarget(for: point, with: event)
        }

        // A fresh sequence — the first (and only) touch just beginning — re-arms the decision. A
        // second finger landing later leaves the lock intact, so it joins the same route.
        let active = touches.filter {
            $0.phase == .began || $0.phase == .moved || $0.phase == .stationary
        }
        if active.count <= 1 { router = TextTouchRouter() }

        switch router.route(firstTouchAt: point, region: region) {
        case .text:
            return textHost
        case .photo:
            return photoTarget(for: point, with: event)
        }
    }

    private func photoTarget(for point: CGPoint, with event: UIEvent?) -> UIView? {
        let inScroll = convert(point, to: scrollView)
        return scrollView.hitTest(inScroll, with: event) ?? scrollView
    }
}
