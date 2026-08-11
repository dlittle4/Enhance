import UIKit

/// The live, on-canvas representation of the text overlay: a sibling of the zooming photo, not a
/// subview of it, so the text stays frame-anchored while the photo pans beneath it (§8.2).
///
/// Two rules keep this cheap and out of the photo's way.
///
/// **It is transparent to touches outside the text.** `point(inside:)` answers only for the text's
/// own rotated box, so although the view covers the whole canvas, every other touch falls straight
/// through to the scroll view underneath and the photo pans and zooms exactly as it always has.
///
/// **Gestures are layer transforms, not re-renders.** Dragging and pinching move and scale the
/// rendered layer; the text is re-composited once, on release. Re-running Core Text and a
/// full-canvas composite per gesture frame is the per-frame work LEARNINGS 2026-03-13 records as
/// having killed the old canvas, and it reads as jank.
///
/// The editor always shows the text **settled** — the entrance animation belongs to the exported
/// GIF, not to the editing surface, where motion under a finger just makes placement harder.
final class TextOverlayHostView: UIView {

    // MARK: - Configuration

    /// Side of the square canvas in points (325).
    var canvasSide: CGFloat = 325

    /// Whether the TEXT category is active. Off, the text still shows at rest but is inert: the
    /// recognizers are disabled and `point(inside:)` refuses every touch, so the photo owns the
    /// whole canvas exactly as under the other categories.
    var isInteractive: Bool = false {
        didSet {
            guard isInteractive != oldValue else { return }
            recognizers.forEach { $0.isEnabled = isInteractive }
        }
    }

    // MARK: - Callbacks

    var onOverlayChanged: ((TextOverlay) -> Void)?
    var onGestureBegan: (() -> Void)?
    var onGestureEnded: (() -> Void)?
    var onRequestEditing: (() -> Void)?

    // MARK: - State

    private(set) var overlay: TextOverlay?
    private var raster: RasterizedText?
    /// Identifies the appearance the current `raster` was built for, so it is rebuilt only when
    /// something that changes the *pixels* moves — never on a pure drag.
    private var rasterKey: String?

    private let contentLayer = CALayer()
    private let session = TextGestureSession()

    /// In-flight gesture deltas, applied as a layer transform and baked into the model on release.
    private var liveTranslation: CGPoint = .zero
    private var liveScale: CGFloat = 1

    /// Tight text size in points at rest, for the touch region.
    private var restingTextSize: CGSize = .zero

    private lazy var recognizers: [UIGestureRecognizer] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentLayer.contentsGravity = .center
        layer.addSublayer(contentLayer)

        setUpGestures()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if session.isActive == false { resetLayerGeometry() }
    }

    // MARK: - Touch transparency

    /// **The rule that keeps the photo working.** This view is a full-canvas sibling sitting on top
    /// of the scroll view, so if it claimed its whole bounds it would swallow every touch and the
    /// photo could never be panned or zoomed again. It answers only for the text itself.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isInteractive, let region = hitRegion else { return false }
        return region.contains(point)
    }

    // MARK: - Public API

    func update(overlay newValue: TextOverlay?, canvasSide side: CGFloat) {
        canvasSide = side
        overlay = newValue

        guard let overlay = newValue, overlay.isActive else {
            raster = nil
            rasterKey = nil
            restingTextSize = .zero
            contentLayer.contents = nil
            return
        }

        prepareRasterIfNeeded(for: overlay)
        render()
    }

    /// The overlay's rotated touch target in canvas points, including any in-flight gesture, so the
    /// region tracks the text while it is being moved or scaled.
    var hitRegion: TextHitRegion? {
        guard let overlay, overlay.isActive, restingTextSize != .zero else { return nil }
        let live = CGSize(width: restingTextSize.width * liveScale,
                          height: restingTextSize.height * liveScale)
        return TextHitRegion(
            center: CGPoint(x: overlay.center.x * canvasSide + liveTranslation.x,
                            y: overlay.center.y * canvasSide + liveTranslation.y),
            renderedSize: live,
            angle: overlay.angle
        )
    }

    // MARK: - Rasterizing and rendering

    private var screenScale: CGFloat { window?.screen.scale ?? UIScreen.main.scale }

    private func appearanceKey(for o: TextOverlay) -> String {
        // Everything the raster depends on. Notably not `center`: placement happens at composite
        // time, so dragging never invalidates the raster.
        "\(o.text)|\(o.font.rawValue)|\(o.color.rawValue)|\(o.decoration.rawValue)"
            + "|\(o.alignment.rawValue)|\(o.fontSize)|\(o.angle)|\(o.animation.granularity)"
            // The fill is baked into the master, so both parts of it must invalidate the cache.
            // Omitting them left the canvas showing the old colour while the panel said otherwise —
            // the raster was correct, it just was never rebuilt.
            + "|\(o.fillMode.rawValue)|\(o.gradient.start)|\(o.gradient.mid)|\(o.gradient.end)"
            + "|\(Int(canvasSide))|\(Int(screenScale))"
    }

    private func prepareRasterIfNeeded(for overlay: TextOverlay) {
        let key = appearanceKey(for: overlay)
        guard key != rasterKey else { return }
        raster = TextRasterizer.prepare(overlay: overlay, pixelSide: canvasSide * screenScale)
        rasterKey = raster == nil ? nil : key
        restingTextSize = raster.map(tightTextSize(in:)) ?? .zero
    }

    /// Composites the settled text over a transparent canvas, through the same compositor the GIF
    /// generator uses, so the preview cannot drift from the export.
    private func render() {
        guard let overlay, let raster,
              let base = Self.transparentImage(side: Int((canvasSide * screenScale).rounded())) else {
            contentLayer.contents = nil
            return
        }
        let composited = TextTileCompositor.composite(raster, overlay: overlay, progress: 1, over: base)

        CATransaction.begin()
        CATransaction.setDisableActions(true) // implicit CALayer animations would smear this
        contentLayer.contents = composited
        contentLayer.contentsScale = screenScale
        resetLayerGeometry()
        CATransaction.commit()
    }

    /// Back to the plain full-canvas layer: the composited image already carries the text's
    /// position, so at rest the layer is identity.
    private func resetLayerGeometry() {
        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentLayer.setAffineTransform(.identity)
    }

    /// Moves and scales the already-rendered layer for an in-flight gesture. The anchor is moved to
    /// the text's own position first, so a pinch grows the text about itself rather than about the
    /// middle of the canvas.
    private func applyLiveTransform() {
        guard let overlay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.anchorPoint = CGPoint(x: overlay.center.x, y: overlay.center.y)
        contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        contentLayer.position = CGPoint(
            x: overlay.center.x * canvasSide + liveTranslation.x,
            y: overlay.center.y * canvasSide + liveTranslation.y
        )
        contentLayer.setAffineTransform(CGAffineTransform(scaleX: liveScale, y: liveScale))
        CATransaction.commit()
    }

    /// The text's own size in points, from the layout's ink bounds.
    ///
    /// **Not** from the tiles: a `.whole`-granularity preset (POP, RISE, FLICKER) is cut as a single
    /// tile spanning the entire raster, so measuring tiles reported the whole canvas as "the text".
    /// The touch region then covered everything, every touch in the TEXT category routed to the
    /// overlay, and the photo could not be pinched or panned at all.
    ///
    /// `inkBounds` is in the layout's own pixel space, whose side is `raster.pixelSide`, so one
    /// factor converts it to canvas points regardless of granularity or supersampling.
    private func tightTextSize(in raster: RasterizedText) -> CGSize {
        let ink = raster.layout.inkBounds
        guard ink.width > 0, ink.height > 0, raster.pixelSide > 0 else { return .zero }
        let toPoints = canvasSide / raster.pixelSide
        return CGSize(width: ink.width * toPoints, height: ink.height * toPoints)
    }

    private static func transparentImage(side: Int) -> CGImage? {
        guard side > 0, let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    // MARK: - Gestures

    private func setUpGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        [pan, pinch, rotate].forEach { $0.delegate = self }
        recognizers = [pan, pinch, rotate, doubleTap]
        recognizers.forEach {
            $0.isEnabled = isInteractive
            addGestureRecognizer($0)
        }
    }

    private func beginGesture() { session.begin { self.onGestureBegan?() } }

    /// Bakes whatever the gesture produced into the model, re-renders once, and closes the session
    /// on the last recognizer to lift.
    private func endGesture() {
        session.end {
            guard var current = self.overlay else { self.onGestureEnded?(); return }

            if self.liveTranslation != .zero {
                current.center.x = min(1, max(0, current.center.x + self.liveTranslation.x / self.canvasSide))
                current.center.y = min(1, max(0, current.center.y + self.liveTranslation.y / self.canvasSide))
            }
            if self.liveScale != 1 {
                let lineCount = self.raster?.layout.lineCount ?? 1
                let maxSize = TextLayoutLimits.maxFontSize(lineCount: lineCount)
                current.fontSize = min(maxSize, max(TextLayoutLimits.minFontSize,
                                                    current.fontSize * self.liveScale))
            }

            self.liveTranslation = .zero
            self.liveScale = 1
            self.overlay = current
            self.prepareRasterIfNeeded(for: current)
            self.render()
            self.onOverlayChanged?(current)
            self.onGestureEnded?()
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            beginGesture()
        case .changed:
            liveTranslation = g.translation(in: self)
            applyLiveTransform()
        case .ended, .cancelled, .failed:
            endGesture()
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            beginGesture()
        case .changed:
            liveScale = g.scale
            applyLiveTransform()
        case .ended, .cancelled, .failed:
            endGesture()
        default: break
        }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard var current = overlay else { return }
        switch g.state {
        case .began:
            beginGesture()
        case .changed:
            // Rotation changes the raster (the glyphs are drawn at the resting angle), so it is
            // committed continuously rather than transformed — it is also the rarest gesture.
            current.angle += g.rotation
            g.rotation = 0
            overlay = current
            prepareRasterIfNeeded(for: current)
            render()
        case .ended, .cancelled, .failed:
            current.angle = TextLayoutLimits.snapAngle(current.angle, current: nil).angle
            overlay = current
            prepareRasterIfNeeded(for: current)
            render()
            onOverlayChanged?(current)
            endGesture()
        default: break
        }
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        onRequestEditing?()
    }

    @objc private func handleResignActive() {
        session.abort {
            self.liveTranslation = .zero
            self.liveScale = 1
            self.render()
            self.onGestureEnded?()
        }
    }
}

extension TextOverlayHostView: UIGestureRecognizerDelegate {
    /// Pan, pinch and rotate on the text run together — the sticker idiom of dragging while pinching.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizers.contains(g) && recognizers.contains(other)
    }
}
