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
        layer.addSublayer(bracketLayer)
        layer.addSublayer(labelLayer)

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
            lockOn()
        }
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
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 8 / effectiveScale).cgPath

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
        labelLayer.string = String(format: "FACE %02d", marker.index + 1)
        labelLayer.font = CTFontCreateWithName("Silkscreen-Regular" as CFString, size, nil)
        labelLayer.fontSize = size
        labelLayer.foregroundColor = marker.isTarget
            ? tint.cgColor
            : tint.withAlphaComponent(CGFloat(tuning.unselectedOpacity)).cgColor

        let height = size * 1.4
        labelLayer.frame = CGRect(
            x: rect.minX,
            y: rect.maxY + size * 0.4,
            width: rect.width,
            height: height
        )
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
