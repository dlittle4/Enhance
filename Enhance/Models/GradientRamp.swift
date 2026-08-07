import SwiftUI
import CoreImage

/// A multi-stop colour ramp for `GradientMapEffect`, which maps image luminance
/// onto the ramp — shadows take the first stop, highlights the last.
///
/// Multi-stop is the point: a two-stop ramp is just `DuotoneEffect`, which was
/// retired for being too flat to be interesting. Three or four stops give the
/// midtones somewhere to go, which is where the character comes from.
enum GradientRamp: String, CaseIterable, Identifiable, Hashable {
    case sunset = "SUNSET"
    case ice    = "ICE"
    case toxic  = "TOXIC"
    case ember  = "EMBER"
    case violet = "VIOLET"
    case mint   = "MINT"

    var id: String { rawValue }

    /// Colour stops in ascending location order. The first is always at 0 and the
    /// last always at 1, so a luminance in [0,1] is always bracketed.
    var stops: [(location: CGFloat, rgb: (r: CGFloat, g: CGFloat, b: CGFloat))] {
        switch self {
        case .sunset:
            return [(0.0,  (0.11, 0.03, 0.24)),
                    (0.40, (0.72, 0.16, 0.35)),
                    (0.75, (0.98, 0.53, 0.18)),
                    (1.0,  (1.00, 0.93, 0.62))]
        case .ice:
            return [(0.0,  (0.02, 0.05, 0.16)),
                    (0.45, (0.10, 0.42, 0.68)),
                    (0.78, (0.42, 0.83, 0.94)),
                    (1.0,  (0.92, 0.99, 1.00))]
        case .toxic:
            return [(0.0,  (0.04, 0.06, 0.03)),
                    (0.42, (0.06, 0.42, 0.20)),
                    (0.76, (0.55, 0.87, 0.15)),
                    (1.0,  (0.90, 1.00, 0.55))]
        case .ember:
            return [(0.0,  (0.05, 0.02, 0.02)),
                    (0.38, (0.48, 0.08, 0.06)),
                    (0.72, (0.95, 0.42, 0.08)),
                    (1.0,  (1.00, 0.92, 0.75))]
        case .violet:
            return [(0.0,  (0.06, 0.03, 0.16)),
                    (0.42, (0.36, 0.13, 0.61)),
                    (0.76, (0.85, 0.32, 0.78)),
                    (1.0,  (1.00, 0.85, 0.95))]
        case .mint:
            // Keyed off the app's mint accent (96, 255, 168).
            return [(0.0,  (0.02, 0.10, 0.09)),
                    (0.44, (0.06, 0.45, 0.36)),
                    (0.78, (0.376, 1.00, 0.659)),
                    (1.0,  (0.94, 1.00, 0.92))]
        }
    }

    /// Stop colours for the picker swatch, in ramp order.
    var swiftUIColors: [Color] {
        stops.map { Color(red: $0.rgb.r, green: $0.rgb.g, blue: $0.rgb.b) }
    }

    /// The ramp colour at `t`, linearly interpolated between the bracketing stops.
    ///
    /// Done in Swift rather than via `CGGradient` deliberately: this is a 1-D
    /// lookup, so drawing into a bitmap would add a top-left/bottom-left origin
    /// hazard (see LEARNINGS 2026-03-10) for no benefit, and this stays
    /// deterministic and unit-testable.
    func color(at t: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let clamped = max(0, min(1, t))
        let s = stops

        guard let upperIndex = s.firstIndex(where: { $0.location >= clamped }) else {
            return s[s.count - 1].rgb
        }
        guard upperIndex > 0 else { return s[0].rgb }

        let lower = s[upperIndex - 1]
        let upper = s[upperIndex]
        let span = upper.location - lower.location
        guard span > 0 else { return upper.rgb }

        let f = (clamped - lower.location) / span
        return (lower.rgb.r + (upper.rgb.r - lower.rgb.r) * f,
                lower.rgb.g + (upper.rgb.g - lower.rgb.g) * f,
                lower.rgb.b + (upper.rgb.b - lower.rgb.b) * f)
    }
}
