import SwiftUI
import UIKit

/// The single text layer a user can place over a photo.
///
/// Every spatial quantity is **normalized against the output frame**, never points or pixels:
/// `center` is `0…1` of each side with `(0, 0)` at top-left, and `fontSize` is a fraction of the
/// frame's height. The live canvas is 325pt and the export is 600px, so one value resolved
/// against each side is what keeps preview and GIF in agreement — see FEATURE-TEXT-EFFECTS.md §7.8.
///
/// Deliberately a value type with no `SwiftUI.Color` anywhere in it. `GradientStops` stores
/// `Color`s so `ColorPicker` can bind to them, and LEARNINGS 2026-08-07 records the bill: opaque
/// equality that forced `commitEditing` to push undo entries unconditionally, a cache key derived
/// from resolved RGB instead of the stored value, and no `Codable`/`Hashable` for persistence.
/// Colour here is a semantic enum with projections, exactly as `LaserColor` does it.
struct TextOverlay: Equatable, Sendable {

    /// Capped at `maxGraphemeClusters` by the editor, in extended grapheme clusters — never
    /// `count` on `utf16`, which would cut a family emoji in half.
    var text: String

    /// Normalized `0…1` of the output frame, top-left origin.
    var center: CGPoint

    /// Normalized against the output frame's height.
    var fontSize: CGFloat

    /// Resting orientation in radians, normalized to `(−π, π]`. Entrance presets animate on top
    /// of this rather than replacing it.
    var angle: CGFloat

    var font: TextFont
    var color: TextColorChoice
    var alignment: TextAlign
    var decoration: TextDecoration
    var animation: TextAnimationType

    /// Stable per overlay, so FLICKER is deterministic.
    ///
    /// Stored rather than derived from the frame index because preview and export must agree and
    /// two generations of the same overlay must be byte-identical. Calling a random API inside the
    /// frame loop would break both, quietly.
    var seed: UInt64

    /// The editor's input cap. Three rendered lines is a field-sizing guideline, not a renderer
    /// constraint — the layout engine will wrap to as many lines as the size demands.
    static let maxGraphemeClusters = 120

    /// Whitespace-only text is not an overlay. Guards generation gating, `hasNonDefaultSettings`,
    /// and the rasterizer, which would otherwise produce an empty master and zero tiles.
    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Grapheme-cluster length, which is the only length the editor's cap may be measured in.
    var characterCount: Int { text.count }

    /// A centred overlay at a comfortable default size, for the moment a preset card is tapped.
    static func makeDefault(animation: TextAnimationType,
                            text: String = "",
                            seed: UInt64 = UInt64.random(in: .min ... .max)) -> TextOverlay {
        TextOverlay(
            text: text,
            center: CGPoint(x: 0.5, y: 0.5),
            fontSize: 0.12,
            angle: 0,
            font: .silkscreenBold,
            color: .white,
            alignment: .center,
            decoration: .shadow,
            animation: animation,
            seed: seed
        )
    }
}

// MARK: - Font

/// Typeface choices for a text overlay.
///
/// All five cases ship in the model and resolve to a real `UIFont`, but V1 exposes no picker and
/// defaults to Silkscreen Bold — the app is entirely Silkscreen, so one face is a coherent V1
/// rather than a gap. Adding the picker later is then a UI change with no model migration.
enum TextFont: String, CaseIterable, Identifiable, Hashable, Sendable {
    case silkscreenRegular = "SILK"
    case silkscreenBold    = "SILK BOLD"
    case systemRounded     = "ROUND"
    case systemSerif       = "SERIF"
    case systemCondensed   = "NARROW"

    var id: String { rawValue }

    /// Whether this face is a bitmap-style pixel font.
    ///
    /// Drives two rendering decisions that are wrong for a vector face: nearest-neighbour
    /// magnification during a live pinch, so the transient reads as blocky rather than mushy;
    /// and extra care with non-integer downscales, which turn Silkscreen to porridge.
    var isPixelFont: Bool {
        self == .silkscreenRegular || self == .silkscreenBold
    }

    /// Resolves to a concrete font at a point size already in the raster's coordinate space.
    ///
    /// Silkscreen is registered at runtime through CoreText by `FontRegistration`, not through
    /// `UIAppFonts`, so `UIFont(name:size:)` can legitimately fail if that ever regresses —
    /// hence the explicit system fallback rather than a force-unwrap.
    func resolved(pointSize: CGFloat) -> UIFont {
        switch self {
        case .silkscreenRegular:
            return UIFont(name: "Silkscreen-Regular", size: pointSize)
                ?? .systemFont(ofSize: pointSize)
        case .silkscreenBold:
            return UIFont(name: "Silkscreen-Bold", size: pointSize)
                ?? .boldSystemFont(ofSize: pointSize)
        case .systemRounded:
            return Self.systemFont(pointSize: pointSize, design: .rounded)
        case .systemSerif:
            return Self.systemFont(pointSize: pointSize, design: .serif)
        case .systemCondensed:
            return UIFont.systemFont(ofSize: pointSize, weight: .bold, width: .condensed)
        }
    }

    private static func systemFont(pointSize: CGFloat,
                                   design: UIFontDescriptor.SystemDesign) -> UIFont {
        let base = UIFont.systemFont(ofSize: pointSize, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Colour

/// The overlay's fill colour.
///
/// A semantic enum with UIKit and SwiftUI projections, the same shape as `LaserColor`. The palette
/// leads with white and black because a title over a photograph needs contrast before it needs
/// personality; mint is the app's own accent, defined once in `Design/Colors.swift`.
enum TextColorChoice: String, CaseIterable, Identifiable, Hashable, Sendable {
    case white  = "WHITE"
    case black  = "BLACK"
    case mint   = "MINT"
    case pink   = "PINK"
    case yellow = "YELLOW"
    case blue   = "BLUE"

    var id: String { rawValue }

    /// Straight RGB, `0…1`. The single definition the two projections below are derived from,
    /// so a swatch in the editor and a glyph in the GIF cannot drift apart.
    var rgb: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .white:  return (1.0, 1.0, 1.0)
        case .black:  return (0.0, 0.0, 0.0)
        case .mint:   return (96 / 255, 255 / 255, 168 / 255)
        case .pink:   return (1.0, 0.133, 0.6)
        case .yellow: return (1.0, 0.9, 0.0)
        case .blue:   return (0.0, 0.4, 1.0)
        }
    }

    /// For the rasterizer and any UIKit-backed canvas chrome.
    var uiColor: UIColor {
        let c = rgb
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    /// For editor swatches.
    var swiftUIColor: Color {
        let c = rgb
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// The colour decoration should use behind or around this fill.
    ///
    /// Black text needs a white plate and white text a black one, or BLOCK and OUTLINE vanish
    /// against the very colour they exist to separate the glyphs from. Derived from relative
    /// luminance rather than case-by-case, so adding a colour cannot forget to answer this.
    var contrastingColor: UIColor {
        let c = rgb
        let luminance = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        return luminance > 0.5 ? UIColor.black : UIColor.white
    }
}

// MARK: - Decoration

/// Separation between the glyphs and the photograph behind them.
///
/// Rendered into the one master raster in a fixed order — BLOCK fill, SHADOW, glyph fill, OUTLINE
/// stroke — so decoration is continuous across tile seams by construction rather than by each
/// tile redrawing its own share of it. See FEATURE-TEXT-EFFECTS.md §7.1.
enum TextDecoration: String, CaseIterable, Identifiable, Hashable, Sendable {
    case none    = "NONE"
    case shadow  = "SHADOW"
    case block   = "BLOCK"
    case outline = "OUTLINE"

    var id: String { rawValue }

    /// Whether this decoration draws a filled plate behind the whole block.
    ///
    /// BLOCK is the one decoration that cannot be cut up with the glyphs: sliced across word
    /// tiles under a staggered reveal it becomes a ladder of abutting rectangles. It gets its own
    /// tile and moves as a unit.
    var drawsBackgroundPlate: Bool { self == .block }

    /// Padding around the ink for the plate, as a multiple of the resolved point size.
    var platePadding: CGFloat { self == .block ? 0.22 : 0 }

    /// Stroke width for `outline`, as a multiple of the resolved point size.
    var outlineWidth: CGFloat { self == .outline ? 0.08 : 0 }

    /// Shadow offset and blur, as multiples of the resolved point size.
    var shadowOffset: CGSize { self == .shadow ? CGSize(width: 0.05, height: 0.05) : .zero }
    var shadowBlur: CGFloat { self == .shadow ? 0.04 : 0 }
}

// MARK: - Alignment

/// Horizontal alignment within the wrapped block.
///
/// Named `TextAlign` rather than `TextAlignment` to avoid colliding with SwiftUI's type of that
/// name, which this file's `import SwiftUI` would otherwise make ambiguous at every use site.
enum TextAlign: String, CaseIterable, Identifiable, Hashable, Sendable {
    case leading  = "LEFT"
    case center   = "CENTER"
    case trailing = "RIGHT"

    var id: String { rawValue }

    /// `natural` is deliberate for `leading`: it resolves to the paragraph's own base direction,
    /// so an Arabic string aligns right without the editor having to detect the language.
    var nsAlignment: NSTextAlignment {
        switch self {
        case .leading:  return .natural
        case .center:   return .center
        case .trailing: return .right
        }
    }
}
