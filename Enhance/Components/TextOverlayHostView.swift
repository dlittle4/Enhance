import UIKit

/// The live, on-canvas representation of the text overlay: a sibling of the zooming photo, not a
/// subview of it, so the text stays frame-anchored while the photo pans beneath it (§8.2).
///
/// It renders through the shipped `TextTileCompositor` — the very code the exported GIF uses — so
/// the preview cannot drift from the result. A `CADisplayLink` drives the same `progress` the
/// generator feeds each frame, looping the chosen entrance so the effect is visible over the photo.
/// While a gesture is in flight the loop freezes to the settled state, so positioning is steady.
///
/// The raster (one Core Text layout) is prepared only when the text's *appearance* changes — string,
/// font, colour, decoration, size or angle. A pan changes only `center`, which is applied at
/// composite time, so dragging never re-runs Core Text (§7.5).
final class TextOverlayHostView: UIView {

    // MARK: - Configuration

    /// Side of the square canvas in points (325).
    var canvasSide: CGFloat = 325

    /// Whether the TEXT category is active. Off, the text holds at its settled state and is inert —
    /// no recognizers, no animation loop — matching how effects display under other categories.
    var isInteractive: Bool = false {
        didSet {
            guard isInteractive != oldValue else { return }
            recognizers.forEach { $0.isEnabled = isInteractive }
            updateAnimationLoop()
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
    /// Key of the appearance the current `raster` was built for, so we re-prepare only when it moves.
    private var rasterKey: String?

    private let contentLayer = CALayer()
    private let session = TextGestureSession()

    private var displayLink: CADisplayLink?
    private var loopStart: CFTimeInterval = 0
    private var isGesturing = false

    /// One entrance plus a hold, in seconds — the preview cadence, independent of the GIF's own
    /// frame timing. The entrance itself settles by 70% of the moving portion (`entranceWindow`).
    private let movingDuration: CFTimeInterval = 1.6
    private let holdDuration: CFTimeInterval = 1.1

    /// Tight text size in points at rest, for the routing hit region.
    private var restingTextSize: CGSize = .zero
    /// Live pinch factor during a gesture; baked into `fontSize` on release.
    private var liveScale: CGFloat = 1

    private lazy var recognizers: [UIGestureRecognizer] = []

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReduceMotionChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentLayer.frame = bounds
    }

    // MARK: - Public API

    func update(overlay newValue: TextOverlay?, canvasSide side: CGFloat) {
        canvasSide = side
        overlay = newValue

        guard let overlay = newValue, overlay.isActive else {
            raster = nil
            rasterKey = nil
            contentLayer.contents = nil
            updateAnimationLoop()
            return
        }

        prepareRasterIfNeeded(for: overlay)
        renderCurrentFrame()
        updateAnimationLoop()
    }

    /// The overlay's rotated touch target in canvas points, for the container's first-touch routing.
    var hitRegion: TextHitRegion? {
        guard let overlay, overlay.isActive, restingTextSize != .zero else { return nil }
        let live = CGSize(width: restingTextSize.width * liveScale,
                          height: restingTextSize.height * liveScale)
        return TextHitRegion(
            center: CGPoint(x: overlay.center.x * canvasSide, y: overlay.center.y * canvasSide),
            renderedSize: live,
            angle: overlay.angle
        )
    }

    // MARK: - Rasterizing and rendering

    private var screenScale: CGFloat { window?.screen.scale ?? UIScreen.main.scale }

    private func appearanceKey(for o: TextOverlay) -> String {
        // Everything the *raster* depends on. Notably not `center` — placement is composite-time.
        "\(o.text)|\(o.font.rawValue)|\(o.color.rawValue)|\(o.decoration.rawValue)"
            + "|\(o.alignment.rawValue)|\(o.fontSize)|\(o.angle)|\(o.animation.granularity)"
            + "|\(Int(canvasSide))|\(Int(screenScale))"
    }

    private func prepareRasterIfNeeded(for overlay: TextOverlay) {
        let key = appearanceKey(for: overlay)
        guard key != rasterKey else { return }
        let pixelSide = canvasSide * screenScale
        raster = TextRasterizer.prepare(overlay: overlay, pixelSide: pixelSide)
        rasterKey = raster == nil ? nil : key
        restingTextSize = raster.map(tightTextSize(in:)) ?? .zero
    }

    /// Composites the text over a transparent canvas at `progress`, exactly as the GIF generator
    /// does, and hands the result to the layer. Cheap enough to run per display-link frame.
    private func render(progress: CGFloat) {
        guard let overlay, let raster,
              let base = Self.transparentImage(side: Int((canvasSide * screenScale).rounded())) else {
            contentLayer.contents = nil
            return
        }
        // The pinch preview scales font size live without re-laying-out; fold it in here.
        var shown = overlay
        shown.fontSize = overlay.fontSize * liveScale
        let composited = TextTileCompositor.composite(raster, overlay: shown, progress: progress, over: base)

        CATransaction.begin()
        CATransaction.setDisableActions(true) // no implicit 0.25s crossfade between frames
        contentLayer.contents = composited
        contentLayer.contentsScale = screenScale
        contentLayer.frame = bounds
        CATransaction.commit()
    }

    /// Renders whatever the current moment calls for: the looping entrance while idle and
    /// interactive, or the settled state while gesturing, inert, or under Reduce Motion.
    private func renderCurrentFrame() {
        render(progress: currentProgress())
    }

    private func currentProgress() -> CGFloat {
        guard isInteractive, !isGesturing, !reduceMotion, displayLink != nil else { return 1 }
        let elapsed = CACurrentMediaTime() - loopStart
        let cycle = movingDuration + holdDuration
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        return t < movingDuration ? CGFloat(t / movingDuration) : 1
    }

    private func tightTextSize(in raster: RasterizedText) -> CGSize {
        let union = raster.tiles
            .filter { $0.origin == .cut }
            .map(\.pixelRect)
            .reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return .zero }
        let toPoints = canvasSide / (raster.pixelSide * raster.supersample)
        return CGSize(width: union.width * toPoints, height: union.height * toPoints)
    }

    private static func transparentImage(side: Int) -> CGImage? {
        guard side > 0, let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    // MARK: - Animation loop

    private var shouldAnimate: Bool {
        isInteractive && !isGesturing && !reduceMotion
            && (overlay?.isActive ?? false) && raster != nil
    }

    private func updateAnimationLoop() {
        if shouldAnimate {
            if displayLink == nil {
                loopStart = CACurrentMediaTime()
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
            renderCurrentFrame() // settle
        }
    }

    @objc private func tick() { render(progress: currentProgress()) }

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

    private func beginGesture() {
        session.begin { self.onGestureBegan?() }
        if !isGesturing { isGesturing = true; updateAnimationLoop() }
    }

    private func endGesture() {
        session.end { self.onGestureEnded?() }
        if session.isActive == false, isGesturing {
            isGesturing = false
            updateAnimationLoop() // resume the entrance loop, restarting from the top
            loopStart = CACurrentMediaTime()
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard var current = overlay else { return }
        switch g.state {
        case .began:
            beginGesture()
        case .changed:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            current.center.x = min(1, max(0, current.center.x + t.x / canvasSide))
            current.center.y = min(1, max(0, current.center.y + t.y / canvasSide))
            overlay = current
            render(progress: 1)
            onOverlayChanged?(current)
        case .ended, .cancelled, .failed:
            endGesture()
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard var current = overlay else { return }
        switch g.state {
        case .began:
            beginGesture()
        case .changed:
            liveScale = g.scale
            render(progress: 1) // live font scale folded into render, no re-layout
        case .ended, .cancelled, .failed:
            let lineCount = raster?.layout.lineCount ?? 1
            let maxSize = TextLayoutLimits.maxFontSize(lineCount: lineCount)
            current.fontSize = min(maxSize, max(TextLayoutLimits.minFontSize,
                                                current.fontSize * liveScale))
            liveScale = 1
            overlay = current
            prepareRasterIfNeeded(for: current)
            render(progress: 1)
            onOverlayChanged?(current)
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
            current.angle = g.rotation + (overlay?.angle ?? 0)
            // Re-prepare so the composite reflects the new angle; short strings make this cheap.
            overlay = current
            prepareRasterIfNeeded(for: current)
            render(progress: 1)
            g.rotation = 0
            onOverlayChanged?(current)
        case .ended, .cancelled, .failed:
            let snapped = TextLayoutLimits.snapAngle(current.angle, current: nil).angle
            current.angle = snapped
            overlay = current
            prepareRasterIfNeeded(for: current)
            render(progress: 1)
            onOverlayChanged?(current)
            endGesture()
        default: break
        }
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        onRequestEditing?()
    }

    @objc private func handleResignActive() {
        session.abort { self.onGestureEnded?() }
        liveScale = 1
        isGesturing = false
        updateAnimationLoop()
    }

    @objc private func handleReduceMotionChange() { updateAnimationLoop() }
}

extension TextOverlayHostView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizers.contains(g) && recognizers.contains(other)
    }
}
