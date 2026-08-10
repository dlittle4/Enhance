import CoreImage

/// Builds a soft-edged alpha mask for a face region, fitted to a rectangle in image
/// coordinates. The mask is an ellipse inscribed in the (padded) source bounds: opaque
/// white in the core, fading to transparent at the edge so the copied feature blends into
/// the destination instead of showing a hard crop seam.
///
/// The graph is entirely lazy Core Image (a radial gradient, a transform, a crop) — no
/// `CIContext`, no `createCGImage`. The compositor transforms this mask with the identical
/// matrix it applies to the sampled source, so the two never separate under scale/rotation.
enum FaceRegionMaskBuilder {

    /// - Parameters:
    ///   - bounds: padded source bounds in image coordinates. The ellipse is inscribed here.
    ///   - feather: fraction of the ellipse radius spent fading from opaque to transparent,
    ///     in `0...1`. Larger is softer; a value near 0 is a hard-edged ellipse.
    /// - Returns: a mask `CIImage` whose extent equals `bounds`, or `nil` if `bounds` is
    ///   degenerate or non-finite.
    static func ellipticalMask(bounds: CGRect, feather: CGFloat) -> CIImage? {
        guard bounds.hasFiniteComponents, bounds.width >= 1, bounds.height >= 1 else { return nil }

        let rx = bounds.width / 2
        let ry = bounds.height / 2
        let clampedFeather = max(0.02, min(1.0, feather))

        // A unit-radius radial gradient centred at the origin: opaque white core out to
        // (1 - feather), transparent at 1. White RGB with a falling alpha keeps the fringe
        // colour-neutral under premultiplication.
        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputRadius0": 1.0 - clampedFeather,
            "inputRadius1": 1.0,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        ])?.outputImage else { return nil }

        // Scale the unit circle into an ellipse of radii (rx, ry), then move it to the
        // rectangle's centre. Crop to the exact bounds so the mask extent matches the crop.
        let transform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .scaledBy(x: rx, y: ry)

        return gradient
            .transformed(by: transform)
            .cropped(to: bounds)
    }
}
