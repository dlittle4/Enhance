import SwiftUI

/// One chrome element's arrival: rise, grow and fade, delayed by its position in the cascade.
///
/// Shared by `EditorView` and MOTION LAB's preview rather than written twice, so the lab cannot
/// drift into staggering differently from the thing it is tuning — the same rule
/// `FaceMarkerLabView` states for its own preview.
///
/// With `motion == nil` this collapses to the plain opacity gate the editor has always used, so
/// the experiment being off is not a different code path, just different values.
struct ChromeEntrance: ViewModifier {

    /// What the entrance needs to know. `nil` means "no entrance" — today's flat fade.
    struct Motion: Equatable {
        var stagger: Double
        var scale: Double
        var offsetY: Double
        var curve: MotionCurve
    }

    let motion: Motion?

    /// The editor's `showControls`, or the lab's replay state.
    let shown: Bool

    /// Position in the cascade. Multiplied by `stagger` to get this element's delay.
    let index: Int

    /// Decorative motion holds its settled state when the system asks for less of it — the rule
    /// `EditorView` already applies to looping card previews. The fade survives; the travel does
    /// not, and neither does the stagger, so nothing is left waiting its turn.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let stagger = reduceMotion ? 0 : (motion?.stagger ?? 0)
        let scale = reduceMotion ? 1 : (motion?.scale ?? 1)
        let rise = reduceMotion ? 0 : (motion?.offsetY ?? 0)

        return content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : scale)
            .offset(y: shown ? 0 : rise)
            .animation(
                motion?.curve.animation.delay(Double(index) * stagger),
                value: shown
            )
    }
}

extension View {
    func chromeEntrance(_ motion: ChromeEntrance.Motion?, shown: Bool, index: Int) -> some View {
        modifier(ChromeEntrance(motion: motion, shown: shown, index: index))
    }
}
