import SwiftUI
import UIKit

/// The app's colour tokens.
///
/// **These mirror the Figma variable set exported as `Default.tokens.json`** (2026-08-12). Names
/// follow that export rather than the app's earlier invented ones, so a value can be traced from
/// design to code without a translation table. `Tools/export-tokens.swift --diff` checks the two
/// still agree.
///
/// Tokens are named for the **role** they play, not the colour they happen to be — that is what
/// makes themes possible: a theme reassigns roles, and a token named `darkGrey` would start lying
/// the moment it did.
///
/// Effect and shader colour maths under `Services/Animators/**` is deliberately **not** tokenised.
/// Those literals are image processing rather than design, and a theme must never move them.
extension Color {

    // MARK: - Accent

    /// Selection, active state, and confirm affordances throughout the editor.
    static let enhanceMint = Color(hex: 0x60FFA8)

    /// The accent at 30%, used as the *fill* behind a selected segment while the mint itself
    /// draws the border. New in the 2026-08-12 design: selection is now a tinted well plus a
    /// 2pt outline rather than an outline alone.
    static let mintDim = Color(hex: 0x60FFA8).opacity(0.3)

    // MARK: - Surfaces
    //
    // Three levels, named primary → card → control rather than by depth. They got materially
    // lighter in the 2026-08-12 pass; the old set was 0x171717 / 0x202020 / 0x323232 and sat much
    // closer together.

    /// Every screen's background.
    static let surfacePrimary = Color(hex: 0x171717)

    /// A card, pill, or the effect detail panel.
    ///
    /// **The panel used to have its own warmer colour** (`surfacePanel`, `0x1C1815`). It now
    /// shares this one — one raised surface, not two.
    static let surfaceCard = Color(hex: 0x353535)

    /// The track behind a segmented control, and a selected cell.
    ///
    /// Exported as `#3D3D3D`. The panel spec's generated code carries a `#454545` fallback, which
    /// is stale — the token file wins.
    static let surfaceControl = Color(hex: 0x3D3D3D)

    /// The one-pixel border on an inactive effect card.
    ///
    /// Not part of the exported token set. Kept because `EffectCardView` and `SegmentedBar` still
    /// use it and nothing in the new design replaces it — flagged for the next design pass rather
    /// than given an invented value.
    static let hairline = Color.white.opacity(0.04)

    // MARK: - Content

    /// Default text and glyph colour, including anything unselected.
    static let textPrimary = Color.white

    /// Text or a glyph that is present but unavailable.
    ///
    /// **Back to an opacity of white** (50%) in the 2026-08-12 design, from the flat `#D1D1D1`
    /// chosen the day before. An opacity composites against whatever surface is behind it, which
    /// is what the three new surface levels need.
    static let textInactive = Color.white.opacity(0.5)

    /// Content drawn on the mint gradient — a button label, or the numeral inside a slider knob.
    ///
    /// **Pure black** as of 2026-08-12, from `0x171717`. Named for the gradient rather than for
    /// the accent because that is what the design calls it and where it is actually used.
    static let textOnGradient = Color.black

    // MARK: - Lines and overlays

    /// The rule between sections in Settings. Now **15% alpha**, so it sits on whatever surface is
    /// behind it rather than being a solid light bar.
    static let divider = Color(hex: 0xD9D9D9).opacity(0.15)

    /// Drop shadow beneath raised elements. Not yet used — exported by the design for the next
    /// component pass.
    static let shadow = Color.black.opacity(0.15)

    /// Dimming behind a modal or sheet. Not yet used — same.
    static let scrim = Color.black.opacity(0.4)
}

extension UIColor {
    /// UIKit twin of `Color.enhanceMint`, for the UIKit-backed canvas overlays in
    /// `ImageCanvasView` where a `Color` can't be used.
    static let enhanceMint = UIColor(red: 96 / 255, green: 255 / 255, blue: 168 / 255, alpha: 1)
}
