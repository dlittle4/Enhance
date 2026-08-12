import SwiftUI

/// Named animation curves.
///
/// **All four are the same curve as of 2026-08-12** — `spring(response: 0.3, dampingFraction: 0.6)`,
/// the press curve, applied everywhere on the user's call. The app previously used four different
/// springs; one consistent motion is the decision.
///
/// The names are kept rather than collapsed into a single `Motion.standard` because they say
/// *what is moving*, and that is what lets one of them be retuned later without hunting call
/// sites. If they are still identical when something needs to differ, that will be a one-line
/// change here instead of a search across the app.
///
/// One thing this gave up, recorded so it is a choice rather than an accident: `gridReflow` was an
/// `interactiveSpring`, a different curve *type* tuned to stay responsive while a pinch is still
/// in progress. It is a plain spring now. Nothing reads it yet — `GalleryView` still uses inline
/// literals until Phase 2 migrates it — so the change is not yet visible, but it will be the
/// moment that migration lands. If the pinch-to-reflow grid feels sluggish afterwards, this is
/// the first place to look.
enum Motion {

    /// Button press and release.
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// Panels and sheets moving in or out, and the gallery's select-mode chrome.
    static let panel = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// The showcase carousel advancing.
    static let carousel = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// The gallery grid reflowing under a pinch. See the note above — this was an
    /// `interactiveSpring` before the consolidation.
    static let gridReflow = Animation.spring(response: 0.3, dampingFraction: 0.6)
}
