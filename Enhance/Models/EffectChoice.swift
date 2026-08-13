import Foundation

/// A browse-carousel entry: the "no effect" card, or one of the family's own effects.
///
/// Every carousel used to list only its effects, so choosing *nothing* was unreachable from the
/// gallery — a visual effect or face filter could only be cleared with undo or RESET, and a zoom
/// type could not be cleared at all (ROADMAP §3f, "Zoom is always on").
///
/// Wrapping the item type is what lets the one generic `EffectCarousel` carry the extra card
/// without each family inventing a `none` case inside its own enum. That alternative looks
/// cheaper and is not: `AnimatorType`, `VisualEffectType`, `FaceFilterType` and
/// `TextAnimationType` are all walked by `allCases` in the generator, the thumbnail passes and
/// the tests, and every one of those walks would then have to remember to skip a case that has
/// no effect behind it. The absence stays where it already is — a `nil` selection.
enum EffectChoice<Effect: Hashable & Identifiable>: Hashable, Identifiable {
    /// The photo as it is. Selecting it clears the category's selection.
    case original
    case effect(Effect)

    /// The value is its own identity, which is what lets the carousel scroll to a choice by
    /// value the same way it scrolled to a bare effect before.
    var id: Self { self }

    /// The wrapped effect, or `nil` for ORIGINAL.
    var effect: Effect? {
        guard case .effect(let effect) = self else { return nil }
        return effect
    }

    /// The card that should read as selected for a nil-able selection.
    init(_ selection: Effect?) {
        self = selection.map { .effect($0) } ?? .original
    }

    /// ORIGINAL **first**, then the family's own cards.
    ///
    /// Leading rather than trailing because it is where the carousel rests before any choice has
    /// been made, so the selected card is on screen at rest without the scroll having to chase
    /// it — and because it reads as the starting point rather than as an "off" switch tacked on
    /// the end of a list the user has to scroll to find.
    static func gallery(_ effects: [Effect]) -> [EffectChoice<Effect>] {
        [.original] + effects.map { .effect($0) }
    }
}
