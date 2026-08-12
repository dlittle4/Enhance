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
    static var silkscreenControl: Font { .custom("Silkscreen-Regular", size: 13) }

    // MARK: - Added by the Phase 1 token migration

    /// Section headings — Bold 16. The most-written inline pair in the app, tied with
    /// `silkscreenLabel` at six call sites each.
    static var silkscreenSectionTitle: Font { .custom("Silkscreen-Bold", size: 16) }

    /// Field and row labels — Regular 16.
    static var silkscreenLabel: Font { .custom("Silkscreen-Regular", size: 16) }

    /// The numeral inside a slider knob — **Bold** 13.
    ///
    /// Deliberately separate from `silkscreenControl`, which is *Regular* 13. The migration plan
    /// listed `ParameterSliderRow`'s knob as a `silkscreenControl` swap with a note to "verify
    /// Bold vs Regular"; it is Bold, so that swap would have quietly de-emphasised the one number
    /// the user is actually reading while dragging. One call site, and worth its own role.
    static var silkscreenControlEmphasis: Font { .custom("Silkscreen-Bold", size: 13) }
}
