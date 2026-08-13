import SwiftUI

/// The app's type roles. Silkscreen is a fixed-size bitmap font, so these are exact point sizes
/// rather than Dynamic Type styles — see DESIGN_SYSTEM.md for why accessibility scaling is a
/// separate, larger piece of work.
///
/// Every role below matches a size/weight pair that call sites were already writing inline.
/// Adding a role is how an inline `.custom("Silkscreen…")` gets retired; inventing a *new* size
/// is a design decision and does not belong in a token migration.
extension Font {
    static var silkscreenBody: Font { .custom("Silkscreen-Regular", size: 14) }
    static var silkscreenTitle: Font { .custom("Silkscreen-Regular", size: 24) }
    static var silkscreenHeadline: Font { .custom("Silkscreen-Bold", size: 14) }
    static var silkscreenSubheadline: Font { .custom("Silkscreen-Regular", size: 12) }
    static var silkscreenCaption: Font { .custom("Silkscreen-Regular", size: 12) }
    static var silkscreenButton: Font { .custom("Silkscreen-Bold", size: 18) }
    static var silkscreenButtonLabel: Font { .custom("Silkscreen-Regular", size: 16) }

    // MARK: - Added by the Phase 1 token migration

    /// Section headings — Bold 16.
    ///
    /// `silkscreenControl` (Regular 13) and `silkscreenControlEmphasis` (Bold 13) were retired
    /// on 2026-08-12 — their nine call sites now use `silkscreenBody` (Regular 14). That is a
    /// visible change: control labels grow a point, and the slider knob's numeral stops being
    /// bold.
    static var silkscreenSectionTitle: Font { .custom("Silkscreen-Bold", size: 16) }

    /// Field and row labels — Regular 16.
    static var silkscreenLabel: Font { .custom("Silkscreen-Regular", size: 16) }

    /// The numeral inside a slider knob — Regular 10, the smallest size in the app.
    ///
    /// Added for the 2026-08-12 panel design, which shrank the knob from 34pt to 24pt. The
    /// numeral had to come down with it or it would not fit inside the circle.
    static var silkscreenSmall: Font { .custom("Silkscreen-Regular", size: 10) }

}
