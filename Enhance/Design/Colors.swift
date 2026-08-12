import SwiftUI
import UIKit

/// The app's colour tokens.
///
/// **Every token here is exactly equal to the literal it replaces.** Phase 1 of
/// [DESIGN_SYSTEM.md](../Docs/DESIGN_SYSTEM.md) is a 1:1 swap with *zero* intended visual change,
/// so the app must render pixel-identical before and after. Anything that changes a value belongs
/// in a later, deliberate commit — not here.
///
/// Tokens are named for the **role** they play, not for the colour they happen to be. That is what
/// makes themes (FEATURE-THEMES.md) possible: a theme reassigns roles, and a token named
/// `darkBrown` would have to be renamed or would start lying the moment it did.
///
/// Effect and shader colour maths under `Services/Animators/**` is deliberately **not** tokenised.
/// Those literals are image processing rather than design, and a theme must never move them.
extension Color {

    // MARK: - Accent

    /// Selection, active state, and confirm affordances throughout the editor.
    ///
    /// This value was previously written out in five places, in two different forms
    /// (`Color(red: 96/255, green: 255/255, blue: 168/255)` and `Color(hex: 0x60FFA8)`),
    /// plus a third in the `icon-check` asset's SVG fill. They all mean `#60FFA8`.
    static let enhanceMint = Color(hex: 0x60FFA8)

    /// Content drawn *on top of* the accent — the numeral inside a slider knob.
    ///
    /// Equal to `editorBackground` today, and that is a coincidence rather than a relationship:
    /// see the note on that token. Keeping them separate is what stops a future theme that
    /// darkens the editor from also darkening the text on every knob.
    static let onAccent = Color(hex: 0x120E0A)

    // MARK: - Surfaces

    /// The gallery and settings screen background.
    static let surfaceBase = Color(hex: 0x171717)

    /// The editor screen background — warmer and darker than `surfaceBase`.
    ///
    /// **The two screens genuinely differ**, which was not obvious before tokenising: the gallery
    /// is a neutral `0x171717` and the editor a warm `0x120E0A`. Written as
    /// `Color(red: 18/255, green: 14/255, blue: 10/255)` at the call site, so it did not even look
    /// like the same *kind* of value. Recorded here rather than "fixed" — matching them is a
    /// design decision, not a refactor.
    static let editorBackground = Color(hex: 0x120E0A)

    /// A raised pill or card sitting on a screen background. The most duplicated surface in the
    /// app — eight hand-rolled copies across the editor and gallery.
    static let surfaceRaised = Color(hex: 0x202020)

    /// The effect detail panel's background.
    static let surfacePanel = Color(hex: 0x1C1815)

    /// A selected/active cell, currently the effect card.
    static let surfaceActive = Color(hex: 0x323232)

    /// The one-pixel border on an inactive effect card. Opacity-based rather than a solid, so it
    /// works over any surface beneath it.
    static let hairline = Color.white.opacity(0.04)

    // MARK: - Controls

    /// The 1pt rule between sections in Settings.
    ///
    /// **Named `toggleTrack` in the migration plan, which was wrong** — there is no toggle
    /// anywhere in the app. Its only use is `SettingsView.divider`, a 1pt `Rectangle`. Caught by
    /// rebuilding the screen in Figma from the source, which is exactly the kind of error a spec
    /// sheet is for. Renamed before anything referenced it.
    ///
    /// It is also the app's only light-coloured element, which makes it the one token a light
    /// theme would have to *darken* rather than lighten.
    static let divider = Color(hex: 0xD9D9D9)

    /// The selected segment in `SegmentedBar`. Applied at `.opacity(0.7)` by that component, which
    /// is left at the call site because it is a compositing decision rather than the colour.
    static let segmentSelected = Color(red: 100 / 255, green: 148 / 255, blue: 122 / 255)

    /// The secondary (non-accent) button fill.
    static let buttonSecondary = Color(red: 0.20, green: 0.411, blue: 0.298)

    /// The GIF badge's fill, applied at `.opacity(0.8)` by that component.
    ///
    /// A third distinct green, and deliberately kept distinct: `segmentSelected`,
    /// `buttonSecondary` and this were each invented at their own call site and are *not* the same
    /// colour. Converging them is a design decision for a later commit — Phase 1 only moves them
    /// somewhere they can be compared.
    static let badgeGreen = Color(red: 0, green: 0.51, blue: 0.298)
}

extension UIColor {
    /// UIKit twin of `Color.enhanceMint`, for the UIKit-backed canvas overlays in
    /// `ImageCanvasView` where a `Color` can't be used.
    static let enhanceMint = UIColor(red: 96 / 255, green: 255 / 255, blue: 168 / 255, alpha: 1)
}
