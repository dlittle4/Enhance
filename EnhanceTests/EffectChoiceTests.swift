import Testing
@testable import Enhance

/// `EffectChoice` is what puts an ORIGINAL card in front of every effect carousel without
/// adding a `none` case to the four effect enums — see the type's own doc comment for why that
/// alternative was rejected.
struct EffectChoiceTests {

    /// ORIGINAL leads, and nothing is dropped or reordered behind it. The position is not
    /// cosmetic: it is where the carousel rests before a choice is made, so a trailing ORIGINAL
    /// would start every session scrolled away from the selected card.
    @Test func gallery_putsOriginalFirstAndKeepsTheEffectOrder() {
        let gallery = EffectChoice.gallery(AnimatorType.allCases)

        #expect(gallery.count == AnimatorType.allCases.count + 1)
        #expect(gallery.first == .original)
        #expect(gallery.dropFirst().compactMap(\.effect) == AnimatorType.allCases)
    }

    /// The carousel highlights and scrolls by value, so a nil selection has to resolve to the
    /// ORIGINAL card rather than to nothing at all.
    @Test func initFromSelection_mapsNilToOriginal() {
        #expect(EffectChoice<VisualEffectType>(nil) == .original)
        #expect(EffectChoice(VisualEffectType.dither) == .effect(.dither))
    }

    @Test func effect_isNilOnlyForOriginal() {
        #expect(EffectChoice<FaceFilterType>.original.effect == nil)
        #expect(EffectChoice.effect(FaceFilterType.lazerEyes).effect == .lazerEyes)
    }

    /// The choice is its own `id`, so two entries that hash alike would collide in the
    /// carousel's `ForEach` and in its scroll-to-selection.
    @Test func everyEntryInAGalleryHasADistinctIdentity() {
        let gallery = EffectChoice.gallery(TextAnimationType.allCases)
        #expect(Set(gallery).count == gallery.count)
    }
}
