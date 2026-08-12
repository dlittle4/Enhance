import SwiftUI
import UIKit

/// The three user-chosen colours of a gradient map: shadows, midtones, highlights.
///
/// Stored as SwiftUI `Color` so `ColorPicker` can bind to each slot directly, with
/// `resolved` converting to plain RGB triples for the Core Image pipeline.
struct GradientStops: Equatable {
    var dark: Color
    var mid: Color
    var light: Color

    static let `default` = GradientStops(
        dark: Color(red: 0.11, green: 0.03, blue: 0.24),
        mid: Color(red: 0.72, green: 0.16, blue: 0.35),
        light: Color(red: 1.00, green: 0.93, blue: 0.62)
    )

    /// The colours as clamped sRGB triples, plus their ramp locations.
    ///
    /// `ColorPicker` can hand back Display P3 colours whose sRGB components fall
    /// outside 0–1, so every channel is clamped before it reaches the colour cube.
    var resolved: [(location: CGFloat, rgb: RGB)] {
        [(0.0, Self.rgb(dark)), (0.5, Self.rgb(mid)), (1.0, Self.rgb(light))]
    }

    /// A canonical, hashable key for cube memoisation. Deliberately derived from the
    /// resolved RGB rather than the `Color` values, whose equality is opaque.
    var cacheKey: CubeKey { cacheKey(exponent: 1) }

    /// The cube is a function of the stop colours *and* the luminance gamma the effect
    /// applies before looking a colour up, so both belong in the key. See
    /// `GradientMapEffect.cube(for:exponent:)`.
    func cacheKey(exponent: Float) -> CubeKey {
        let stops = resolved
        return CubeKey(components: stops.flatMap { [Float($0.rgb.r), Float($0.rgb.g), Float($0.rgb.b)] } + [exponent])
    }

    /// The ramp colour at `t`, linearly interpolated between bracketing stops.
    func color(at t: CGFloat) -> RGB {
        let clamped = max(0, min(1, t))
        let stops = resolved

        guard let upperIndex = stops.firstIndex(where: { $0.location >= clamped }) else {
            return stops[stops.count - 1].rgb
        }
        guard upperIndex > 0 else { return stops[0].rgb }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = upper.location - lower.location
        guard span > 0 else { return upper.rgb }

        let f = (clamped - lower.location) / span
        return RGB(r: lower.rgb.r + (upper.rgb.r - lower.rgb.r) * f,
                   g: lower.rgb.g + (upper.rgb.g - lower.rgb.g) * f,
                   b: lower.rgb.b + (upper.rgb.b - lower.rgb.b) * f)
    }

    private static func rgb(_ color: Color) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(r: max(0, min(1, r)), g: max(0, min(1, g)), b: max(0, min(1, b)))
    }
}

struct RGB: Equatable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
}

/// Canonical cube cache key — the resolved RGB components of every stop.
struct CubeKey: Hashable {
    let components: [Float]
}
