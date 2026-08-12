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

    /// Content drawn *on top of* the accent — the slider knob's numeral, and every button label
    /// sitting on the mint gradient.
    ///
    /// **Resolved 2026-08-12 in favour of the AppButton literal.** Two values were doing this job:
    /// `0x120E0A` on the knob and `Color(red: 0.09, …)` on buttons. The button value won because
    /// it is the majority — five call sites against one.
    ///
    /// Note it rounds to `0x171717`, which is `surfaceBase`. They are the same colour under two
    /// names, kept apart because they answer different questions: one is "what is behind
    /// everything", the other "what is legible on mint".
    static let onAccent = Color(red: 0.09, green: 0.09, blue: 0.09)

    // MARK: - Surfaces

    /// Every screen's background.
    ///
    /// **The editor's warm `0x120E0A` was retired 2026-08-12** in favour of one neutral
    /// background everywhere. That is a deliberate visual change, not a refactor — the editor
    /// gets slightly lighter and loses its warm cast.
    static let surfaceBase = Color(hex: 0x171717)


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

    /// The app's one secondary green: the selected segment in `SegmentedBar`, the secondary
    /// button fill, and the GIF badge.
    ///
    /// **`buttonSecondary` and `badgeGreen` were retired into this 2026-08-12.** Three greens had
    /// been invented at three call sites and were never the same colour; seeing them side by side
    /// in the Figma spec sheet is what settled it. Call sites keep their own opacity — 0.7 on the
    /// segment, 0.8 on the badge — because that is compositing, not colour.
    static let segmentSelected = Color(red: 100 / 255, green: 148 / 255, blue: 122 / 255)

    // MARK: - Content

    /// Default text and glyph colour.
    ///
    /// Closes the gap the spec sheet made obvious: 83 raw `.white` calls with no token, which is
    /// what would have made light mode impossible. **Selected** text uses `enhanceMint` directly
    /// rather than an alias — one value, one name.
    ///
    /// Secondary text is still untokenised. `.white` at 0.5 / 0.4 / 0.3 / 0.25 opacity all appear
    /// in the app and no single one is canonical; picking a scale is its own decision.
    static let textPrimary = Color.white

    /// An icon that is present but not available — the dimmest of the three icon states.
    ///
    /// The other two reuse existing tokens by design: an ordinary icon is `textPrimary`, a
    /// selected one is `enhanceMint`. Note the shipped assets bake their fill into the SVG, so
    /// these only apply where the icon is template-rendered.
    static let iconInactive = Color(hex: 0xD1D1D1)


}

extension UIColor {
    /// UIKit twin of `Color.enhanceMint`, for the UIKit-backed canvas overlays in
    /// `ImageCanvasView` where a `Color` can't be used.
    static let enhanceMint = UIColor(red: 96 / 255, green: 255 / 255, blue: 168 / 255, alpha: 1)
}
