import CoreText
import UIKit

/// One face's marker on the canvas.
///
/// Extracted from the private `FaceBoxView` that used to live inside `ImageCanvasView`, for two
/// reasons: the reticle variant is a good deal more drawing than a rounded rect, and FACE MARKER
/// LAB previews the *real* renderer rather than a mock-up of it — so what is tuned is what ships.
///
/// **Legacy is byte-for-byte the old view.** With `options.reticle` off, the corner radius, the two
/// stroke widths, both fill alphas and the infinite pulse are the values that were there before,
/// which is what makes the experiment a fair comparison rather than a redesign with a switch on it.
final class FaceMarkerView: UIView {

    private let borderLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let bracketLayer = CAShapeLayer()
    private let labelLayer = CATextLayer()

    /// The sweeping band. A gradient rather than a hard line so it reads as light passing over the
    /// face; a 1pt rule would read as a UI element sitting on top of it.
    private let scanLayer = CAGradientLayer()
    private var isScanning = false

    /// Whether the entrance's scan delay has elapsed, i.e. a plain `redraw` is allowed to start
    /// the sweep. `beginEntrance` clears it for staggered faces; the scheduled start sets it.
    private var scanArmed = true

    /// Whether a non-repeating scan has run its passes. Once true, a reconfigure — an effect
    /// landing, a selection change — must not start the sweep again.
    private var scanFinished = false

    private var onTap: ((Int) -> Void)?
    private var faceIndex = 0

    private var options = FaceMarkerOptions.legacy
    private var tuning = FaceMarkerTuning.default
    private var tint: UIColor = .white
    private var marker: FaceMarker?

    /// The scroll view's zoom. Chrome divides by it so a pinch does not fatten the strokes — the
    /// marker tracks the face (it is a subview of the zoomed image view) while its *decoration*
    /// stays a constant size on screen.
    private var contentScale: CGFloat = 1

    /// Only honoured under CALM, so the A/B compares like with like: today's overlay does scale its
    /// strokes with the zoom, and hiding that would flatter the new variant.
    private var effectiveScale: CGFloat { options.calm ? max(0.01, contentScale) : 1 }

    private var hasLockedOn = false
    private var lastTargetState: Bool?

    /// Work scheduled by the entrance choreography, held so a reconfigure can cancel it.
    ///
    /// These views are pooled and reused across photos. Without cancellation a marker could inherit
    /// the tail of the previous face's entrance and lock on at a moment that means nothing.
    private var entranceWork: [DispatchWorkItem] = []

    /// Whether the reticle has been revealed yet. Distinct from `hasLockedOn`, which only records
    /// that the animation has run once: under SCAN FIRST the brackets exist but are held invisible
    /// until the sweeps finish.
    private var reticleRevealed = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // The label sits below the marker box and the reticle brackets are drawn on an inflated
        // rect, so neither fits inside `bounds`.
        clipsToBounds = false

        layer.addSublayer(fillLayer)
        layer.addSublayer(borderLayer)
        // Under the brackets and the number, so the sweep passes behind the chrome rather than
        // washing over it.
        layer.addSublayer(scanLayer)
        layer.addSublayer(bracketLayer)
        layer.addSublayer(labelLayer)

        scanLayer.startPoint = CGPoint(x: 0.5, y: 0)
        scanLayer.endPoint = CGPoint(x: 0.5, y: 1)
        scanLayer.isHidden = true

        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = UIScreen.main.scale
        labelLayer.isHidden = true

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Configuration

    func configure(
        marker: FaceMarker,
        options: FaceMarkerOptions,
        tuning: FaceMarkerTuning,
        tint: UIColor,
        contentScale: CGFloat,
        onTap: @escaping (Int) -> Void
    ) {
        self.marker = marker
        self.faceIndex = marker.index
        self.options = options
        self.tuning = tuning
        self.tint = tint
        self.contentScale = contentScale
        self.onTap = onTap

        redraw()

        // A change of target is the only thing worth animating. Under CALM that is a single flash;
        // the legacy path keeps its infinite pulse, which is the behaviour being judged.
        let isTarget = marker.legacyIsSelected
        if options.calm {
            stopPulse()
            if let last = lastTargetState, last != isTarget, isTarget {
                flash()
            }
        } else {
            if isTarget && lastTargetState != true {
                startPulse()
            } else if !isTarget {
                stopPulse()
            }
        }
        lastTargetState = isTarget

        if options.reticle && !hasLockedOn {
            hasLockedOn = true
            beginEntrance(marker: marker)
        }
    }

    // MARK: - Entrance

    /// Runs the arrival sequence described by `FaceMarkerTuning.entranceTimeline(faceIndex:)`.
    ///
    /// The timeline itself is computed there, and is pure — this method only schedules against it.
    /// That split is deliberate: the arithmetic is where a choreography goes wrong, and arithmetic
    /// is testable in a way that "did it look right" is not.
    private func beginEntrance(marker: FaceMarker) {
        cancelEntrance()

        let timeline = tuning.entranceTimeline(faceIndex: marker.index)

        // Held invisible rather than unbuilt, so the geometry is already correct when it is
        // revealed and the reveal cannot flash a half-laid-out reticle.
        reticleRevealed = timeline.reticleStart <= 0
        bracketLayer.opacity = reticleRevealed ? 1 : 0
        labelLayer.opacity = reticleRevealed ? 1 : 0

        if reticleRevealed {
            lockOn()
        } else {
            schedule(after: timeline.reticleStart) { [weak self] in
                guard let self else { return }
                self.reticleRevealed = true
                self.bracketLayer.opacity = 1
                self.labelLayer.opacity = 1
                self.lockOn()
            }
        }

        // The scan's own start is handled by `updateScanline`; this only has to nudge it once the
        // delay has elapsed.
        scanFinished = false
        if timeline.scanStart > 0 {
            // Stop, don't just hide: `configure` redraws before this runs, and that first redraw
            // can have started the sweep already. Hiding the layer leaves the animation attached
            // and `isScanning` true, so the delayed start below would unhide a band mid-sweep
            // instead of adding a fresh one from the top.
            stopScanning()
            scanArmed = false
            schedule(after: timeline.scanStart) { [weak self] in
                guard let self, let marker = self.marker else { return }
                self.scanArmed = true
                self.updateScanline(marker: marker, force: true)
            }
        } else {
            // No delay: start (or refresh) the sweep now rather than waiting for a redraw that
            // may not come — after a replay's `resetEntrance` the configure's own redraw has
            // already run, disarmed, and hidden the band.
            scanArmed = true
            updateScanline(marker: marker, force: true)
        }

        if let stop = timeline.scanStop {
            schedule(after: stop) { [weak self] in
                self?.scanFinished = true
                self?.stopScanning()
            }
        }
    }

    private func schedule(after delay: Double, _ body: @escaping () -> Void) {
        let work = DispatchWorkItem(block: body)
        entranceWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func cancelEntrance() {
        entranceWork.forEach { $0.cancel() }
        entranceWork.removeAll()
    }

    private func stopScanning() {
        scanLayer.removeAnimation(forKey: "scan")
        scanLayer.isHidden = true
        isScanning = false
    }

    deinit {
        entranceWork.forEach { $0.cancel() }
    }

    /// Re-arms the entrance so it plays again on the next `configure`.
    ///
    /// Needed because these views are **pooled**: a marker survives a selection change, so
    /// `hasLockedOn` stays true and the choreography would never run twice. In the editor the views
    /// are rebuilt on entering the face tab, which re-arms it naturally; the lab has no such moment,
    /// which is what REPLAY ENTRANCE is for.
    func resetEntrance() {
        cancelEntrance()
        hasLockedOn = false
        reticleRevealed = false
        scanArmed = false
        scanFinished = false
        stopScanning()
        bracketLayer.opacity = 0
        labelLayer.opacity = 0
    }

    /// Cheap path for a pinch: only the counter-scaled geometry changes, so nothing re-evaluates
    /// selection or re-runs an animation.
    func updateContentScale(_ scale: CGFloat) {
        guard options.calm, abs(contentScale - scale) > 0.001 else { return }
        contentScale = scale
        redraw()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    // MARK: - Drawing

    private func redraw() {
        guard let marker else { return }

        // Layer geometry must not animate implicitly: these are re-set on every scroll callback,
        // and the default quarter-second action turns a pinch into a smear.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for sublayer in [fillLayer, borderLayer, bracketLayer] {
            sublayer.frame = bounds
        }

        updateScanline(marker: marker)

        // **Every variant has to be recognisable at a glance.** CALM and SPOTLIGHT originally fell
        // through to the legacy box, which made them indistinguishable from DEFAULT in a still and
        // the whole comparison pointless *(user-reported)*. The order below is a precedence, not a
        // set of independent switches: RETICLE is the loudest statement about how a marker draws,
        // SPOTLIGHT's is that the chrome should get out of the way, and CALM's sits between them.
        if options.reticle {
            drawReticle(marker: marker)
        } else if options.spotlight {
            drawSpotlightMarker(marker: marker)
        } else if options.calm {
            drawQuietBox(marker: marker)
        } else {
            drawLegacyBox(marker: marker)
        }
    }

    /// The overlay exactly as it was before the experiments — see the note on this class.
    private func drawLegacyBox(marker: FaceMarker) {
        bracketLayer.path = nil
        labelLayer.isHidden = true

        let isSelected = marker.legacyIsSelected
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: AppConstants.CornerRadius.standard / effectiveScale).cgPath

        borderLayer.path = path
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = isSelected
            ? tint.cgColor
            : tint.withAlphaComponent(0.6).cgColor
        borderLayer.lineWidth = (isSelected ? 3 : 2) / effectiveScale

        fillLayer.path = path
        fillLayer.fillColor = tint.withAlphaComponent(isSelected ? 0.15 : 0.05).cgColor
        fillLayer.strokeColor = UIColor.clear.cgColor
    }

    /// A hairline outline, no fill, square corners.
    ///
    /// CALM's argument is that the overlay should state where the faces are and then stop asking for
    /// attention — so its marker is the lightest mark that still reads as a target. The rounded
    /// corners and the translucent fill both go: they are what make DEFAULT read as a *panel* laid
    /// over the photo rather than as an annotation on it.
    private func drawQuietBox(marker: FaceMarker) {
        bracketLayer.path = nil
        labelLayer.isHidden = true
        fillLayer.path = nil

        borderLayer.path = UIBezierPath(rect: tuning.markerRect(for: bounds)).cgPath
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = CGFloat(max(0.5, tuning.quietStroke)) / effectiveScale
        borderLayer.strokeColor = marker.isTarget
            ? tint.cgColor
            : tint.withAlphaComponent(CGFloat(tuning.unselectedOpacity)).cgColor
    }

    /// The chosen face gets **no chrome at all** — the dimming around it is the selection.
    ///
    /// That is SPOTLIGHT's entire thesis: show the choice in the content rather than in an overlay.
    /// Drawing a box on top of the lit face would be the worst of both, which is what it did before.
    ///
    /// The faces that are *not* chosen keep a hairline, because they are still the controls you tap
    /// to switch, and an unlit face with no mark on it is indistinguishable from background.
    private func drawSpotlightMarker(marker: FaceMarker) {
        bracketLayer.path = nil
        labelLayer.isHidden = true
        fillLayer.path = nil

        guard !marker.isSoloed else {
            borderLayer.path = nil
            return
        }

        borderLayer.path = UIBezierPath(rect: tuning.markerRect(for: bounds)).cgPath
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = CGFloat(max(0.5, tuning.quietStroke)) / effectiveScale
        borderLayer.strokeColor = tint.withAlphaComponent(CGFloat(tuning.unselectedOpacity)).cgColor
    }

    /// Four corner brackets plus the index chip.
    ///
    /// Brackets rather than a closed rectangle because a rectangle around a face is the shape of a
    /// detection debug view — the thing this variant exists to stop looking like.
    private func drawReticle(marker: FaceMarker) {
        borderLayer.path = nil
        fillLayer.path = nil

        let rect = tuning.markerRect(for: bounds)
        let arm = tuning.bracketArm(forSide: min(rect.width, rect.height)) / effectiveScale
        let path = UIBezierPath()

        // Each corner is two strokes meeting at a right angle. Square ends and no join radius: the
        // app's whole visual language is a bitmap font and pixel borders, and a rounded reticle
        // would be the only soft corner on the screen.
        func corner(_ point: CGPoint, dx: CGFloat, dy: CGFloat) {
            path.move(to: CGPoint(x: point.x + dx * arm, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + dy * arm))
        }
        corner(CGPoint(x: rect.minX, y: rect.minY), dx: 1, dy: 1)
        corner(CGPoint(x: rect.maxX, y: rect.minY), dx: -1, dy: 1)
        corner(CGPoint(x: rect.minX, y: rect.maxY), dx: 1, dy: -1)
        corner(CGPoint(x: rect.maxX, y: rect.maxY), dx: -1, dy: -1)

        bracketLayer.path = path.cgPath
        bracketLayer.fillColor = UIColor.clear.cgColor
        bracketLayer.lineCap = .butt
        bracketLayer.lineJoin = .miter
        bracketLayer.lineWidth = CGFloat(tuning.bracketThickness) / effectiveScale
        bracketLayer.strokeColor = marker.isTarget
            ? tint.cgColor
            : tint.withAlphaComponent(CGFloat(tuning.unselectedOpacity)).cgColor

        layoutLabel(marker: marker, under: rect)
    }

    private func layoutLabel(marker: FaceMarker, under rect: CGRect) {
        guard tuning.showsIndexLabel else {
            labelLayer.isHidden = true
            return
        }

        let size = CGFloat(max(4, tuning.labelSize)) / effectiveScale
        labelLayer.isHidden = false
        // Just the number *(user's call)*. `FACE 01` is seven glyphs of a fixed-width bitmap font,
        // which needs roughly 42pt — wider than a face in any group photo, so it clipped exactly
        // when an index label is most useful.
        labelLayer.string = "\(marker.index + 1)"
        labelLayer.font = CTFontCreateWithName("Silkscreen-Regular" as CFString, size, nil)
        labelLayer.fontSize = size
        labelLayer.foregroundColor = marker.isTarget
            ? tint.cgColor
            : tint.withAlphaComponent(CGFloat(tuning.unselectedOpacity)).cgColor

        // Centred on the marker and free to be **wider than it**, rather than inheriting the
        // marker's width — that inheritance was the clipping. `clipsToBounds` is off on this view
        // for the same reason, so a digit under a 20pt face still draws in full.
        let height = size * 1.4
        let width = max(rect.width, size * 4)
        labelLayer.frame = CGRect(
            x: rect.midX - width / 2,
            y: rect.maxY + size * 0.4,
            width: width,
            height: height
        )
    }

    // MARK: - Scanline

    /// A soft band travelling up and down inside the marker.
    ///
    /// Confined to `markerRect` by construction rather than by a mask: the band is as wide as the
    /// marker, and its travel is clamped so its own half-height never leaves the rect. That keeps
    /// the sweep inside the shape you are already looking at, which is what stops it reading as an
    /// effect applied to the whole photo.
    ///
    /// Only the *targets* scan. A face the user has deselected is not being examined, and sweeping
    /// every face at once turns a scanner into a disco.
    private func updateScanline(marker: FaceMarker, force: Bool = false) {
        // The scheduled start runs outside `redraw`'s transaction, and an implicit quarter-second
        // action on the frame or the unhide reads as the band lurching into place.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Two states in which a plain `redraw` must not start the sweep: the entrance delay has
        // not elapsed (`force` is how the scheduled work item says it has), and a non-repeating
        // scan has already run its passes — a reconfigure is not a reason to scan again.
        //
        // Both flags are only maintained by the entrance, which only runs under RETICLE, so the
        // check is gated on it: without that, a replay under scanline-without-reticle would leave
        // `scanArmed` false with nothing to ever set it back.
        if !force, !isScanning, options.reticle, !scanArmed || scanFinished {
            scanLayer.isHidden = true
            return
        }

        guard options.scanline, marker.isTarget else {
            scanLayer.isHidden = true
            scanLayer.removeAnimation(forKey: "scan")
            isScanning = false
            return
        }

        let rect = tuning.markerRect(for: bounds)
        let band = max(2, rect.height * CGFloat(max(0.02, min(1, tuning.scanlineHeight))))
        let alpha = CGFloat(max(0, min(1, tuning.scanlineOpacity)))

        scanLayer.isHidden = false
        scanLayer.frame = CGRect(x: rect.minX, y: 0, width: rect.width, height: band)
        scanLayer.colors = [
            tint.withAlphaComponent(0).cgColor,
            tint.withAlphaComponent(alpha).cgColor,
            tint.withAlphaComponent(0).cgColor
        ]

        let top = rect.minY + band / 2
        let bottom = max(top, rect.maxY - band / 2)
        scanLayer.position = CGPoint(x: rect.midX, y: top)

        // Re-added only when it is not already running: `redraw` fires on every scroll callback,
        // and restarting the animation each time would freeze the band at the top of the sweep.
        guard !isScanning else { return }
        isScanning = true

        let sweep = CABasicAnimation(keyPath: "position.y")
        sweep.fromValue = top
        sweep.toValue = bottom
        sweep.duration = max(0.2, tuning.scanlineDuration)
        // Bounces rather than wrapping — a hard jump back to the top reads as a dropped frame, and
        // easing at each end is what makes it look mechanical rather than like a marquee.
        sweep.autoreverses = true
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLayer.add(sweep, forKey: "scan")
    }

    // MARK: - Animation

    /// The legacy blink: infinite, and the single biggest reason the overlay reads as an alarm.
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

    /// One shot, on the change itself. Motion that means "this just became the target" rather than
    /// motion that means "something is wrong here, permanently".
    private func flash() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.3
        anim.toValue = 1.0
        anim.duration = max(0.05, tuning.flashDuration)
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "flash")
    }

    /// Brackets settling onto the face, once, when they first appear.
    private func lockOn() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = max(1.0, tuning.lockOnScale)
        scale.toValue = 1.0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = max(0.05, tuning.lockOnDuration)
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "lockOn")
    }

    // MARK: - Hit testing

    /// A face in a group photo can be a handful of points across, and the drawn box is currently
    /// the entire tap target. Under CALM the target is grown to `minimumTapTarget` **on screen**,
    /// which is why it divides by the zoom: at 3× the same 44pt needs only a third of the space in
    /// this view's own coordinates.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard options.calm else { return super.point(inside: point, with: event) }

        let minimum = CGFloat(tuning.minimumTapTarget) / max(0.01, contentScale)
        let dx = max(0, (minimum - bounds.width) / 2)
        let dy = max(0, (minimum - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }

    @objc private func tapped() {
        onTap?(faceIndex)
    }
}
