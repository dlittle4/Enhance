import UIKit

/// The filmstrip that appears under a finger scrubbing the preview: every frame as a thumb in
/// a row, the current one centred, largest and ringed in mint, the rest shrinking and tilting
/// away toward the edges so the strip reads as a shallow arc rather than a flat row. It rises
/// in from the bottom on touch-down and sinks back on lift *(user's design, 2026-09-03)*.
///
/// UIKit, owned by `AnimatedGifView`'s coordinator, for the same reason the scrub is: it
/// updates on every frame change and must never re-evaluate SwiftUI. The thumbs are the
/// decoded frames themselves in image views — they share the frames' backing, so a 250-frame
/// GIF costs 250 layers, not 250 decodes. No backdrop: it sits straight on the picture.
final class ScrubFilmstripView: UIView {

    /// Side of the centred thumb in points. Frames are square, so this is width and height.
    var thumbSide: CGFloat = 40 { didSet { setNeedsLayout() } }
    /// Gap between thumbs at full size; scales with the thumbs.
    static let gap: CGFloat = 3
    /// How much smaller each step from the centre gets, and the floor.
    static let falloffPerStep: CGFloat = 0.11
    static let minimumScale: CGFloat = 0.5
    /// Tilt of the side thumbs, in radians per step, capped — the "3D" is a hint, not a carousel.
    static let tiltPerStep: CGFloat = 0.14
    static let maximumTilt: CGFloat = 0.6
    /// How far the strip rises on entrance, in points.
    static let entranceRise: CGFloat = 18

    private let strip = UIView()
    private var thumbs: [UIImageView] = []
    private let ring = CAShapeLayer()
    private let counter = UILabel()
    private var currentIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: Self.entranceRise)

        // Perspective for the tilt, on the strip so every thumb shares one vanishing point.
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 600
        strip.layer.sublayerTransform = perspective
        addSubview(strip)

        ring.fillColor = nil
        ring.strokeColor = UIColor.enhanceMint.cgColor
        ring.lineWidth = 2
        ring.shadowColor = UIColor.black.cgColor
        ring.shadowOpacity = 0.6
        ring.shadowRadius = 3
        ring.shadowOffset = .zero
        layer.addSublayer(ring)

        counter.font = UIFont(name: "Silkscreen-Regular", size: 9) ?? UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        counter.textColor = .white
        counter.textAlignment = .center
        counter.layer.shadowColor = UIColor.black.cgColor
        counter.layer.shadowOpacity = 0.9
        counter.layer.shadowRadius = 2
        counter.layer.shadowOffset = .zero
        addSubview(counter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Hands the strip the frames. Rebuilt only when the stack changes identity, so repeated
    /// holds on one GIF reuse the image views.
    func setFrames(_ frames: [UIImage]) {
        guard frames.count != thumbs.count || frames.first !== thumbs.first?.image else { return }
        thumbs.forEach { $0.removeFromSuperview() }
        thumbs = frames.map { image in
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.layer.cornerRadius = AppConstants.CornerRadius.chip
            view.layer.borderWidth = 0.5
            view.layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
            strip.addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    /// Centres `index`. Animated briefly so a fast scrub reads as the strip sliding and the
    /// thumbs swelling into the middle rather than jumping.
    func show(index: Int, animated: Bool) {
        currentIndex = index
        counter.text = String(format: "%02d / %02d", index + 1, thumbs.count)
        let update = { self.layoutStrip() }
        if animated {
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: update)
        } else {
            update()
        }
    }

    /// Rises and fades in on touch-down; sinks and fades out on lift.
    func setVisible(_ visible: Bool) {
        if visible {
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.6, options: [.beginFromCurrentState]) {
                self.alpha = 1
                self.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
                self.alpha = 0
                self.transform = CGAffineTransform(translationX: 0, y: Self.entranceRise * 0.7)
            }
        }
    }

    /// Height the strip wants for a given thumb side: the thumb, the counter above, padding.
    static func height(forThumb side: CGFloat) -> CGFloat { side + 26 }

    // MARK: - Geometry

    /// Scale of a thumb `steps` away from the centre: 1 at the centre, shrinking each step to
    /// a floor. Pure, for tests.
    static func scale(forDistance steps: Int) -> CGFloat {
        max(minimumScale, 1 - falloffPerStep * CGFloat(abs(steps)))
    }

    /// Where every thumb's centre sits along the strip for `index` centred in `width`, given the
    /// per-thumb scales — each thumb abuts its neighbour at their scaled widths, so the row
    /// packs tighter toward the edges. Pure, for tests.
    static func centres(count: Int, index: Int, thumb: CGFloat, width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        var centres = [CGFloat](repeating: 0, count: count)
        let mid = width / 2
        centres[min(max(index, 0), count - 1)] = mid
        // Rightward.
        var edge = mid + thumb / 2
        if index + 1 < count {
            for i in (index + 1)..<count {
                let s = scale(forDistance: i - index)
                let w = thumb * s
                edge += gap * s
                centres[i] = edge + w / 2
                edge += w
            }
        }
        // Leftward.
        edge = mid - thumb / 2
        if index > 0 {
            for i in stride(from: index - 1, through: 0, by: -1) {
                let s = scale(forDistance: index - i)
                let w = thumb * s
                edge -= gap * s
                centres[i] = edge - w / 2
                edge -= w
            }
        }
        return centres
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        counter.frame = CGRect(x: 0, y: 2, width: bounds.width, height: 14)
        strip.frame = CGRect(x: 0, y: bounds.height - thumbSide - 4, width: bounds.width, height: thumbSide)
        layoutStrip()
    }

    private func layoutStrip() {
        let count = thumbs.count
        guard count > 0 else { ring.path = nil; return }
        let index = min(max(currentIndex, 0), count - 1)
        let centres = Self.centres(count: count, index: index, thumb: thumbSide, width: bounds.width)
        let baseline = thumbSide  // bottoms align, so smaller thumbs sit on the same floor
        for (i, thumb) in thumbs.enumerated() {
            let steps = i - index
            let s = Self.scale(forDistance: steps)
            let side = thumbSide * s
            let cx = centres[i]
            // Off-strip thumbs are hidden rather than laid out: at 250 frames that is most.
            let visible = cx > -side && cx < bounds.width + side
            thumb.isHidden = !visible
            guard visible else { continue }
            thumb.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            thumb.center = CGPoint(x: cx, y: baseline - side / 2)
            // Tilt away from the centre, growing with distance; the far edge recedes.
            let tilt = min(Self.maximumTilt, Self.tiltPerStep * CGFloat(abs(steps)))
            thumb.layer.transform = steps == 0
                ? CATransform3DIdentity
                : CATransform3DMakeRotation(steps > 0 ? -tilt : tilt, 0, 1, 0)
            thumb.alpha = steps == 0 ? 1 : max(0.35, 1 - CGFloat(abs(steps)) * 0.08)
            thumb.layer.zPosition = steps == 0 ? 1 : -CGFloat(abs(steps))
        }
        let ringRect = CGRect(
            x: bounds.width / 2 - thumbSide / 2 - 2,
            y: strip.frame.minY - 2,
            width: thumbSide + 4, height: thumbSide + 4
        )
        ring.path = UIBezierPath(roundedRect: ringRect, cornerRadius: AppConstants.CornerRadius.chip + 1).cgPath
    }
}
