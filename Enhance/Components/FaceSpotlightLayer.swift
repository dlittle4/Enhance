import UIKit

/// Dims the photo everywhere except the chosen face.
///
/// **Canvas chrome, not an effect.** It lives on the scroll view's image view, which the GIF
/// generator never reads, so it cannot reach an exported frame — the same guarantee the face boxes
/// have always had. That is deliberate: this is how the app says *which face is selected*, and
/// baking a selection affordance into someone's GIF would be a bug, not a feature.
///
/// Two layers rather than one, because a single shape layer can only give a hard-edged hole and a
/// hard hole reads as a cutout:
///
/// - `dim` fills everything outside the spotlight ellipse, at full strength, via an even-odd path.
/// - `falloff` is a radial gradient occupying exactly that ellipse, running clear at the centre to
///   the same full strength at its edge.
///
/// They meet at the ellipse boundary at identical alpha, so the seam is invisible and the result
/// reads as light falling on a face.
final class FaceSpotlightLayer: CALayer {

    private let dim = CAShapeLayer()
    private let falloff = CAGradientLayer()

    /// Clips the falloff to the ellipse.
    ///
    /// Without it the gradient's own **corners** — everything past its radial extent — paint at
    /// full strength on top of the region `dim` has already darkened, so the two sum and the
    /// spotlight renders as a black rectangle with a hole in it. Caught on the simulator; it is
    /// invisible to every test in the suite, and to any reasoning that stops at "the gradient ends
    /// at the rim" without asking what it does outside it.
    private let falloffMask = CAShapeLayer()

    override init() {
        super.init()
        setUp()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        dim.fillRule = .evenOdd
        falloff.type = .radial
        // Normalized per axis, so this is an ellipse inscribed in the layer's own bounds rather
        // than a circle — which is what lets the spotlight take the shape of the face box.
        falloff.startPoint = CGPoint(x: 0.5, y: 0.5)
        falloff.endPoint = CGPoint(x: 1.0, y: 0.5)
        falloff.mask = falloffMask
        addSublayer(dim)
        addSublayer(falloff)
    }

    /// - Parameters:
    ///   - rect: the marker rect, in this layer's coordinate space, already inflated by
    ///     `FaceMarkerTuning.markerRect`.
    ///   - content: the full extent to dim — the image view's bounds.
    func update(spotlighting rect: CGRect, in content: CGRect, tuning: FaceMarkerTuning) {
        // Re-set on every scroll and zoom callback; the implicit quarter-second action would turn a
        // pinch into a lagging smear.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        isHidden = false
        frame = content

        let radiusScale = CGFloat(max(0.1, tuning.spotlightRadiusScale))
        let ellipse = CGRect(
            x: rect.midX - rect.width * radiusScale / 2,
            y: rect.midY - rect.height * radiusScale / 2,
            width: rect.width * radiusScale,
            height: rect.height * radiusScale
        )

        let alpha = CGFloat(max(0, min(1, tuning.spotlightDimming)))
        let solid = UIColor.black.withAlphaComponent(alpha).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor

        let outside = UIBezierPath(rect: CGRect(origin: .zero, size: content.size))
        outside.append(UIBezierPath(ovalIn: ellipse))
        dim.frame = CGRect(origin: .zero, size: content.size)
        dim.path = outside.cgPath
        dim.fillColor = solid

        let feather = CGFloat(max(0, min(1, tuning.spotlightFeather)))
        falloff.frame = ellipse
        falloffMask.frame = CGRect(origin: .zero, size: ellipse.size)
        falloffMask.path = UIBezierPath(ovalIn: falloffMask.bounds).cgPath
        falloff.colors = [clear, clear, solid]
        // A feather of 0 puts both clear stops at the rim: no gradient band at all, and the hard
        // cutout is then an honest thing to be able to compare against.
        falloff.locations = [0, NSNumber(value: Double(1 - feather)), 1]
    }

    func hide() {
        isHidden = true
    }
}
