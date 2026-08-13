import SwiftUI
import UIKit

/// A zoomable/pannable image canvas backed by UIScrollView for
/// hardware-accelerated, 60fps pinch/zoom. Face bounding boxes
/// are rendered as UIKit subviews with tap recognizers.
struct ImageCanvasView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var visibleRect: CGRect
    var faceOverlays: [(id: UUID, rect: CGRect, isSelected: Bool)] = []
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

    private let canvasSize: CGFloat = 325

    var body: some View {
        ZStack {
            ScrollableCanvasView(
                image: image,
                scale: $scale,
                visibleRect: $visibleRect,
                faceOverlays: faceOverlays,
                onFaceSelected: onFaceSelected,
                onInteraction: onInteraction,
                onInteractionEnded: onInteractionEnded,
                textOverlay: textOverlay,
                isTextInteractive: isTextInteractive,
                onTextGestureBegan: onTextGestureBegan,
                onTextGestureEnded: onTextGestureEnded,
                onRequestTextEditing: onRequestTextEditing,
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
    @Binding var scale: CGFloat
    @Binding var visibleRect: CGRect
    var faceOverlays: [(id: UUID, rect: CGRect, isSelected: Bool)]
    var onFaceSelected: ((Int) -> Void)?
    var onInteraction: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    var textOverlay: Binding<TextOverlay?>
    var isTextInteractive: Bool
    var onTextGestureBegan: (() -> Void)?
    var onTextGestureEnded: (() -> Void)?
    var onRequestTextEditing: (() -> Void)?
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

        return CanvasContainerView(scrollView: scrollView, textHost: textHost)
    }

    func updateUIView(_ container: CanvasContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if let imageView = coordinator.imageView {
            if imageView.image !== image {
                imageView.image = image
            }
            coordinator.updateFaceBoxes(on: imageView)
        }

        if let textHost = coordinator.textHost {
            textHost.isInteractive = isTextInteractive
            textHost.update(overlay: textOverlay.wrappedValue, canvasSide: canvasSize)
        }
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

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ScrollableCanvasView
        weak var imageView: UIImageView?
        weak var textHost: TextOverlayHostView?
        var canvasSize: CGFloat = 325

        private var faceBoxViews: [FaceBoxView] = []

        private let mintGreen = UIColor.enhanceMint

        init(parent: ScrollableCanvasView) {
            self.parent = parent
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            parent.onInteraction?()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onInteraction?()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
            syncBindings(scrollView)
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

        // MARK: Face Boxes

        func updateFaceBoxes(on imageView: UIImageView) {
            let overlays = parent.faceOverlays
            let contentW = imageView.bounds.width
            let contentH = imageView.bounds.height

            while faceBoxViews.count > overlays.count {
                faceBoxViews.removeLast().removeFromSuperview()
            }
            while faceBoxViews.count < overlays.count {
                let box = FaceBoxView()
                imageView.addSubview(box)
                faceBoxViews.append(box)
            }

            for (index, overlay) in overlays.enumerated() {
                let box = faceBoxViews[index]
                let bb = overlay.rect
                let faceTopY = 1.0 - bb.origin.y - bb.height

                let x = bb.origin.x * contentW
                let y = faceTopY * contentH
                let w = bb.width * contentW
                let h = bb.height * contentH

                box.frame = CGRect(x: x, y: y, width: w, height: h)
                box.configure(
                    isSelected: overlay.isSelected,
                    tintColor: mintGreen,
                    index: index,
                    onTap: { [weak self] idx in
                        self?.parent.onFaceSelected?(idx)
                    }
                )
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
    private let scrollView: UIScrollView
    private let textHost: TextOverlayHostView
    private var router = TextTouchRouter()

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

// MARK: - FaceBoxView

private class FaceBoxView: UIView {
    private var onTap: ((Int) -> Void)?
    private var faceIndex: Int = 0
    private var currentlySelected: Bool?
    private let borderLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        layer.addSublayer(fillLayer)
        layer.addSublayer(borderLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insetBounds = bounds
        let path = UIBezierPath(roundedRect: insetBounds, cornerRadius: 8).cgPath
        borderLayer.path = path
        fillLayer.path = path
        borderLayer.frame = bounds
        fillLayer.frame = bounds
    }

    func configure(isSelected: Bool, tintColor: UIColor, index: Int, onTap: @escaping (Int) -> Void) {
        self.faceIndex = index
        self.onTap = onTap

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = isSelected ? tintColor.cgColor : tintColor.withAlphaComponent(0.6).cgColor
        borderLayer.lineWidth = isSelected ? 3 : 2

        fillLayer.fillColor = isSelected ? tintColor.withAlphaComponent(0.15).cgColor : tintColor.withAlphaComponent(0.05).cgColor
        fillLayer.strokeColor = UIColor.clear.cgColor

        if isSelected && currentlySelected != true {
            startPulse()
        } else if !isSelected {
            stopPulse()
        }
        currentlySelected = isSelected
    }

    private func startPulse() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.4
        anim.duration = 0.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        borderLayer.add(anim, forKey: "pulse")
    }

    private func stopPulse() {
        borderLayer.removeAnimation(forKey: "pulse")
        borderLayer.opacity = 1.0
    }

    @objc private func tapped() {
        onTap?(faceIndex)
    }
}
