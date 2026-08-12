import SwiftUI

/// Named animation curves.
///
/// Each is exactly a curve that call sites were already writing inline — Phase 1 of
/// DESIGN_SYSTEM.md is a 1:1 move with no intended change to how anything feels.
///
/// **These are not interchangeable, and the plan originally assumed they were.** It proposed a
/// single `carousel` spring of `(0.35, 0.85)` to cover every 0.35-response animation. Measuring
/// found three genuinely different ones, including two different *curve types* — an
/// `interactiveSpring` for the pinch-driven grid and a plain `spring` elsewhere. Collapsing them
/// would have changed how the gallery responds under a finger, which is precisely the kind of
/// regression a "no visual change" refactor is supposed to be incapable of.
enum Motion {

    /// Button press and release. `ButtonModifiers` ×2, `AppButton` ×1.
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// Panels and sheets moving in or out, and the gallery's select-mode chrome. Six call sites,
    /// the most-used curve in the app.
    static let panel = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// The showcase carousel advancing.
    static let carousel = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// The gallery grid reflowing under a pinch.
    ///
    /// `interactiveSpring`, not `spring` — it is driven by a gesture in flight, and that variant
    /// is tuned to stay responsive while the finger is still down. The damping is 0.86 rather
    /// than the carousel's 0.85; small, but it is what the grid was tuned to.
    static let gridReflow = Animation.interactiveSpring(response: 0.35, dampingFraction: 0.86)
}
