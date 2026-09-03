import UIKit

/// The filmstrip that appears under a finger scrubbing the preview: every frame as a thumb in
/// a row, the current one centred under a mint bracket, sliding as the finger moves. A cue for
/// *where in the loop* the hold is, which a frozen frame alone cannot say.
///
/// UIKit, owned by `AnimatedGifView`'s coordinator, for the same reason the scrub is: it
/// updates on every frame change and must never re-evaluate SwiftUI. The thumbs are the
/// decoded frames themselves in image views — they share the frames' backing, so a 250-frame
/// GIF costs 250 layers, not 250 decodes.
final class ScrubFilmstripView: UIView {

    /// Thumb side in points. Frames are square, so this is width and height.
    var thumbSide: CGFloat = 40 { didSet { setNeedsLayout() } }
    /// Gap between thumbs.
    static let gap: CGFloat = 2

    private let strip = UIView()
    private var thumbs: [UIImageView] = []
    private let bracket = CAShapeLayer()
    private let counter = UILabel()
    private var currentIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true

        addSubview(strip)

        bracket.fillColor = nil
        bracket.strokeColor = UIColor.enhanceMint.cgColor
        bracket.lineWidth = 2
        layer.addSublayer(bracket)

        counter.font = UIFont(name: "Silkscreen-Regular", size: 9) ?? UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        counter.textColor = .white
        counter.textAlignment = .center
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
            view.layer.cornerRadius = 3
            strip.addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    /// Centres `index` under the bracket. Animated briefly so a fast scrub reads as the strip
    /// sliding rather than jumping.
    func show(index: Int, animated: Bool) {
        currentIndex = index
        counter.text = String(format: "%02d / %02d", index + 1, thumbs.count)
        let update = { self.layoutStrip() }
        if animated {
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveLinear, .beginFromCurrentState], animations: update)
        } else {
            update()
        }
    }

    func setVisible(_ visible: Bool) {
        UIView.animate(withDuration: visible ? 0.15 : 0.25, delay: 0, options: [.beginFromCurrentState]) {
            self.alpha = visible ? 1 : 0
        }
    }

    /// Height the strip wants for a given thumb side: the thumbs, the counter above, padding.
    static func height(forThumb side: CGFloat) -> CGFloat { side + 26 }

    /// Where the strip's content sits so that `index` is centred in `width`. Pure, for tests.
    static func contentOffset(forIndex index: Int, thumb: CGFloat, width: CGFloat) -> CGFloat {
        let pitch = thumb + gap
        return width / 2 - (CGFloat(index) * pitch + thumb / 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        counter.frame = CGRect(x: 0, y: 4, width: bounds.width, height: 14)
        let pitch = thumbSide + Self.gap
        for (i, thumb) in thumbs.enumerated() {
            thumb.frame = CGRect(x: CGFloat(i) * pitch, y: 0, width: thumbSide, height: thumbSide)
        }
        let y = bounds.height - thumbSide - 4
        strip.frame = CGRect(x: 0, y: y, width: CGFloat(thumbs.count) * pitch, height: thumbSide)
        let bx = bounds.width / 2 - thumbSide / 2 - 2
        bracket.path = UIBezierPath(
            roundedRect: CGRect(x: bx, y: y - 2, width: thumbSide + 4, height: thumbSide + 4),
            cornerRadius: 4
        ).cgPath
        layoutStrip()
    }

    private func layoutStrip() {
        let x = Self.contentOffset(forIndex: currentIndex, thumb: thumbSide, width: bounds.width)
        strip.frame.origin.x = x
        // Thumbs fade with distance from the centre so the edges read as "more this way"
        // rather than a hard cut.
        let half = bounds.width / 2
        for (i, thumb) in thumbs.enumerated() {
            let centre = x + CGFloat(i) * (thumbSide + Self.gap) + thumbSide / 2
            let distance = abs(centre - half) / max(1, half)
            thumb.alpha = i == currentIndex ? 1 : max(0.25, 1 - distance * 0.9)
        }
    }
}
