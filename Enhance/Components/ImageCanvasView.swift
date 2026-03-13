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

    private let canvasSize: CGFloat = 325

    var body: some View {
        ZStack {
            ScrollableCanvasView(
                image: image,
                scale: $scale,
                visibleRect: $visibleRect,
                faceOverlays: faceOverlays,
                onFaceSelected: onFaceSelected,
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
    let canvasSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
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

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        guard let imageView = coordinator.imageView else { return }

        if imageView.image !== image {
            imageView.image = image
        }

        coordinator.updateFaceBoxes(on: imageView)
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
        var canvasSize: CGFloat = 325

        private var faceBoxViews: [FaceBoxView] = []

        private let mintGreen = UIColor(red: 96/255, green: 255/255, blue: 168/255, alpha: 1)

        init(parent: ScrollableCanvasView) {
            self.parent = parent
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
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

            guard contentW > 0, contentH > 0 else { return }

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
