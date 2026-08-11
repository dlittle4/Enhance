import UIKit

/// The live, on-canvas representation of the text overlay: a sibling of the zooming photo, not a
/// subview of it, so the text stays frame-anchored while the photo pans beneath it (§8.2).
///
/// Placement is deliberately split so gestures stay cheap. The text is rendered once, **centred and
/// upright**, into `contentLayer`; the overlay's real centre, angle and live pinch are then applied
/// as the layer's `position` and `transform`. So a pan is a position write and a rotate is a
/// transform write — neither re-runs Core Text — and only a font-size change (a pinch, committed on
/// release) re-rasterizes. That is exactly the split §7.5 prescribes to keep the old per-frame
/// re-layout regression from returning.
///
/// The renderer itself is the shipped `TextTileCompositor`, so the preview cannot drift from the
/// exported GIF — they are the same code, differing only in raster size.
final class TextOverlayHostView: UIView {

    // MARK: - Configuration

    /// Side of the square canvas in points (325).
    var canvasSide: CGFloat = 325

    /// Whether the TEXT category is active. Off, the text still shows at rest but is inert — no
    /// recognizers, no selection outline — matching how effects display under other categories.
    var isInteractive: Bool = false {
        didSet {
            guard isInteractive != oldValue else { return }
            recognizers.forEach { $0.isEnabled = isInteractive }
            if !isInteractive { setSelected(false) }
            refreshSelectionLayer()
        }
    }

    // MARK: - Callbacks

    /// A live mutation from a gesture. The SwiftUI layer writes it straight back to the view model's
    /// `textOverlay`, so the model and the on-screen layer never disagree.
    var onOverlayChanged: ((TextOverlay) -> Void)?
    /// First recognizer of a session began — routed through `TextGestureSession` to
    /// `viewModel.beginTextGesture`.
    var onGestureBegan: (() -> Void)?
    /// Last recognizer of a session ended — routed to `viewModel.endTextGesture`, which records one
    /// undo entry and one regeneration for the whole burst.
    var onGestureEnded: (() -> Void)?
    /// Double-tap on the text — reopen the keyboard (phase 1).
    var onRequestEditing: (() -> Void)?

    // MARK: - State

    private(set) var overlay: TextOverlay?
    private var raster: RasterizedText?

    private let contentLayer = CALayer()
    private let selectionLayer = CAShapeLayer()
    private let session = TextGestureSession()

    private var isSelected = false
    /// Live pinch factor, applied as a transform until the gesture ends and it is baked into
    /// `fontSize`. 1 at rest, so the resting layer transform is exact.
    private var liveScale: CGFloat = 1
    /// Live rotation delta, applied on top of `overlay.angle` until the gesture ends.
    private var liveAngleDelta: CGFloat = 0

    /// Tight text size in points at rest (no live scale), for the selection outline and hit region.
    private var restingTextSize: CGSize = .zero

    private lazy var recognizers: [UIGestureRecognizer] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        contentLayer.contentsGravity = .center
        layer.addSublayer(contentLayer)

        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.strokeColor = UIColor.enhanceMint.cgColor
        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [4, 3]
        selectionLayer.isHidden = true
        layer.addSublayer(selectionLayer)

        setUpGestures()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Public API

    /// Updates the overlay and re-renders. Re-rasterizes only when the text's *appearance* changed
    /// (string, font, colour, decoration, size); a pure move or rotate just re-places the layer.
    func update(overlay newValue: TextOverlay?, canvasSide side: CGFloat) {
        let sideChanged = side != canvasSide
        canvasSide = side

        let old = overlay
        overlay = newValue

        guard let overlay = newValue, overlay.isActive else {
            raster = nil
            contentLayer.contents = nil
            selectionLayer.isHidden = true
            return
        }

        if sideChanged || old == nil || Self.appearanceChanged(from: old, to: overlay) {
            rebuildRaster()
        }
        placeLayers()
    }

    /// Whether this overlay's rotated touch target contains a canvas-space point. The container's
    /// `hitTest` calls this to route the first touch of a sequence (§8.3).
    var hitRegion: TextHitRegion? {
        guard let overlay, overlay.isActive, restingTextSize != .zero else { return nil }
        let live = CGSize(width: restingTextSize.width * liveScale,
                          height: restingTextSize.height * liveScale)
        return TextHitRegion(
            center: CGPoint(x: overlay.center.x * canvasSide, y: overlay.center.y * canvasSide),
            renderedSize: live,
            angle: overlay.angle + liveAngleDelta,
            selected: isSelected
        )
    }

    // MARK: - Rendering

    private static func appearanceChanged(from a: TextOverlay?, to b: TextOverlay) -> Bool {
        guard let a else { return true }
        return a.text != b.text || a.font != b.font || a.color != b.color
            || a.decoration != b.decoration || a.alignment != b.alignment
            || a.fontSize != b.fontSize || a.animation.granularity != b.animation.granularity
    }

    private var screenScale: CGFloat { window?.screen.scale ?? UIScreen.main.scale }

    /// Rasterizes the text centred and upright, so all placement is a layer transform.
    private func rebuildRaster() {
        guard var flat = overlay, flat.isActive else { raster = nil; return }
        flat.center = CGPoint(x: 0.5, y: 0.5)
        flat.angle = 0

        let pixelSide = canvasSide * screenScale
        guard let prepared = TextRasterizer.prepare(overlay: flat, pixelSide: pixelSide),
              let base = Self.transparentImage(side: Int(prepared.pixelSide.rounded())) else {
            raster = nil
            contentLayer.contents = nil
            restingTextSize = .zero
            return
        }
        raster = prepared

        // The settled composite over a transparent canvas: text at resting size, centred, upright.
        let composed = TextTileCompositor.composite(prepared, overlay: flat, progress: 1, over: base)
        contentLayer.contents = composed
        contentLayer.contentsScale = screenScale
        contentLayer.frame = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)

        restingTextSize = tightTextSize(in: prepared)
        refreshSelectionLayer()
    }

    /// Tight text bounds in points, from the union of the cut tiles' pixel rects.
    private func tightTextSize(in raster: RasterizedText) -> CGSize {
        let union = raster.tiles
            .filter { $0.origin == .cut }
            .map(\.pixelRect)
            .reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return .zero }
        // pixelRect is in supersampled master pixels; convert to points.
        let toPoints = canvasSide / (raster.pixelSide * raster.supersample)
        return CGSize(width: union.width * toPoints, height: union.height * toPoints)
    }

    /// Places `contentLayer` and the selection outline from the overlay's centre, angle and live
    /// pinch. No Core Text here — this is the cheap path a drag or rotate runs every frame.
    private func placeLayers() {
        guard let overlay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true) // implicit 0.25s CALayer animations would smear this

        let center = CGPoint(x: overlay.center.x * canvasSide, y: overlay.center.y * canvasSide)
        contentLayer.position = center
        let t = CGAffineTransform(rotationAngle: overlay.angle + liveAngleDelta)
            .scaledBy(x: liveScale, y: liveScale)
        contentLayer.setAffineTransform(t)

        placeSelectionLayer(center: center, transform: t)
        CATransaction.commit()
    }

    private func placeSelectionLayer(center: CGPoint, transform: CGAffineTransform) {
        guard isSelected, restingTextSize != .zero else { selectionLayer.isHidden = true; return }
        selectionLayer.isHidden = false
        let inset: CGFloat = 6
        let box = CGRect(x: -restingTextSize.width / 2 - inset,
                         y: -restingTextSize.height / 2 - inset,
                         width: restingTextSize.width + inset * 2,
                         height: restingTextSize.height + inset * 2)
        selectionLayer.path = UIBezierPath(roundedRect: box, cornerRadius: 4).cgPath
        selectionLayer.position = center
        selectionLayer.setAffineTransform(transform)
    }

    private func refreshSelectionLayer() {
        guard let overlay else { return }
        let center = CGPoint(x: overlay.center.x * canvasSide, y: overlay.center.y * canvasSide)
        let t = CGAffineTransform(rotationAngle: overlay.angle + liveAngleDelta)
            .scaledBy(x: liveScale, y: liveScale)
        placeSelectionLayer(center: center, transform: t)
    }

    private static func transparentImage(side: Int) -> CGImage? {
        guard side > 0, let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    // MARK: - Selection

    private func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        refreshSelectionLayer()
    }

    // MARK: - Gestures

    private func setUpGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        [pan, pinch, rotate].forEach { $0.delegate = self }
        recognizers = [pan, pinch, rotate, tap, doubleTap]
        recognizers.forEach {
            $0.isEnabled = isInteractive
            addGestureRecognizer($0)
        }
    }

    private func beginSessionIfNeeded() { session.begin { self.onGestureBegan?() } }
    private func endSession() { session.end { self.onGestureEnded?() } }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard var current = overlay else { return }
        switch g.state {
        case .began:
            beginSessionIfNeeded()
            setSelected(true)
        case .changed:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            current.center.x = min(1, max(0, current.center.x + t.x / canvasSide))
            current.center.y = min(1, max(0, current.center.y + t.y / canvasSide))
            overlay = current
            placeLayers()
            onOverlayChanged?(current)
        case .ended, .cancelled, .failed:
            endSession()
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard var current = overlay else { return }
        switch g.state {
        case .began:
            beginSessionIfNeeded()
            setSelected(true)
        case .changed:
            liveScale = g.scale
            placeLayers()
        case .ended, .cancelled, .failed:
            let lineCount = raster?.layout.lineCount ?? 1
            let maxSize = TextLayoutLimits.maxFontSize(lineCount: lineCount)
            current.fontSize = min(maxSize, max(TextLayoutLimits.minFontSize,
                                                current.fontSize * liveScale))
            liveScale = 1
            overlay = current
            rebuildRaster()   // bake the new size at full resolution
            placeLayers()
            onOverlayChanged?(current)
            endSession()
        default: break
        }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard var current = overlay else { return }
        switch g.state {
        case .began:
            beginSessionIfNeeded()
            setSelected(true)
        case .changed:
            liveAngleDelta = g.rotation
            placeLayers()
        case .ended, .cancelled, .failed:
            let raw = current.angle + liveAngleDelta
            let snapped = TextLayoutLimits.snapAngle(raw, current: nil).angle
            current.angle = snapped
            liveAngleDelta = 0
            overlay = current
            rebuildRaster()   // angle can cross the axis-aligned supersample boundary
            placeLayers()
            onOverlayChanged?(current)
            endSession()
        default: break
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        // Idempotent select — never deselects, so a double-tap's first tap is harmless feedback.
        setSelected(true)
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        setSelected(true)
        onRequestEditing?()
    }

    @objc private func handleResignActive() {
        session.abort { self.onGestureEnded?() }
        liveScale = 1
        liveAngleDelta = 0
    }
}

extension TextOverlayHostView: UIGestureRecognizerDelegate {
    /// Pan, pinch and rotate on the text run together — the sticker idiom of dragging while pinching.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizers.contains(g) && recognizers.contains(other)
    }
}
