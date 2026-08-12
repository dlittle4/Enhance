import SwiftUI

/// Named animation curves.
///
/// **The app's chrome moves on one curve** — `spring(response: 0.3, dampingFraction: 0.6)`,
/// applied to presses, panels and the carousel on the user's call 2026-08-12. Three different
/// springs used to do that job for no reason anyone could name.
///
/// **`gridReflow` is deliberately excluded** *(user's call, 2026-08-12)*. Directly-manipulated
/// motion is not the same problem as chrome animating itself: a pinch is still under the finger,
/// so the curve has to keep up with a gesture rather than play a transition. That is why it is an
/// `interactiveSpring` and not a `spring` — a different curve *type*, not just different numbers.
/// Consistency across the chrome is worth having; forcing it onto a gesture is not.
///
/// The names are kept rather than collapsed into one `Motion.standard` because they say *what is
/// moving*. If another of them needs to diverge later, that is a one-line change here instead of
/// a search across call sites — exactly as `gridReflow` just demonstrated.
enum Motion {

    /// Button press and release.
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// Panels and sheets moving in or out, and the gallery's select-mode chrome.
    static let panel = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// The showcase carousel advancing.
    static let carousel = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// The gallery grid reflowing under a pinch.
    ///
    /// `interactiveSpring`, and 0.86 damping rather than the chrome's 0.6 — this is the value the
    /// grid was tuned to while someone had a finger on it. See the note above for why it does not
    /// follow the others.
    static let gridReflow = Animation.interactiveSpring(response: 0.35, dampingFraction: 0.86)
}
