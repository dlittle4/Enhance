import Foundation

/// Behaviour under evaluation, toggled from GENERAL SETTINGS.
///
/// Kept apart from the ordinary preferences (`autoPlayGifs`, `appTheme`, `selectedAppIcon`)
/// because these are not tastes the user is expected to hold a permanent opinion about — each one
/// is expected to either become unconditional or be deleted once it has been lived with. Having
/// them in one place is what makes that cleanup a single search rather than an archaeology
/// exercise across the view model, the settings sheet and `UserDefaults`.
///
/// Every flag is **off by default**, which `UserDefaults.bool(forKey:)` gives for free on a key
/// that was never written: a flag nobody touches changes nothing.
enum FeatureFlags {

    /// Lets ENHANCE run before the user has pinched the canvas.
    ///
    /// Zoom is the app's one mandatory step — without it ENHANCE refuses and nags "Zoom in on the
    /// image first!". With this on the nag is lifted, and a zoom type with no pinch behind it
    /// generates against `ZoomFraming.fallback` rather than against a 1× canvas. That detail is
    /// load-bearing: at 1× the generator's two endpoint framings are identical, so ZOOM IN would
    /// interpolate between a framing and itself and silently produce a still. See
    /// `EditorViewModel.generationFraming`.
    static let zoomOptionalKey = "featureZoomOptional"

    static var zoomOptional: Bool { UserDefaults.standard.bool(forKey: zoomOptionalKey) }

    // MARK: - Face markers
    //
    // Three independent variants of the face-selection overlay, each isolating one complaint about
    // the current one. They compose rather than exclude — see `FaceMarkerOptions.resolve`, which
    // states the policy in one testable place. With all three off the overlay renders exactly as it
    // always has, which is what makes an A/B possible at all.

    /// Stops the markers behaving like an alarm.
    ///
    /// Four changes, all behavioural rather than cosmetic: nothing is drawn at all when there is
    /// only one face (there is no choice to make); the infinite opacity pulse is replaced by a
    /// one-shot flash when the target actually changes; the chrome is counter-scaled so a pinch
    /// does not fatten it; and the markers fade out once they have been ignored for
    /// `FaceMarkerTuning.autoHideDelay`, returning on the next canvas touch.
    ///
    /// The pulse is the load-bearing one. `EditorView.activeFaceOverlays` treats "no face selected"
    /// as *every* face selected, so the resting state of a group photo is currently every box
    /// blinking forever.
    static let faceMarkersCalmKey = "featureFaceMarkersCalm"

    static var faceMarkersCalm: Bool { UserDefaults.standard.bool(forKey: faceMarkersCalmKey) }

    /// Replaces the rounded rectangle with a viewfinder: four corner brackets, a one-shot lock-on,
    /// and a Silkscreen `FACE 01` chip under each face.
    ///
    /// Purely how the marker draws — it says nothing about when it appears, which is why it
    /// composes with CALM rather than competing with it. The chip is not only decoration: it gives
    /// faces an identity in a group photo, and it extends the tap target below a face that may be
    /// only a few points tall.
    static let faceMarkersReticleKey = "featureFaceMarkersReticle"

    static var faceMarkersReticle: Bool { UserDefaults.standard.bool(forKey: faceMarkersReticleKey) }

    /// Dims the photo outside the chosen face, so selection is visible in the content rather than
    /// only in the chrome.
    ///
    /// Canvas-only, and deliberately so: it is a selection affordance, not an effect, and it must
    /// never reach the generated GIF. It renders as layers on the canvas' image view, which the
    /// generator does not read — the same reason the existing face boxes are safe.
    ///
    /// Inert unless exactly one face is soloed. With no selection every face is a target, and
    /// dimming nothing is the honest answer.
    static let faceMarkersSpotlightKey = "featureFaceMarkersSpotlight"

    static var faceMarkersSpotlight: Bool { UserDefaults.standard.bool(forKey: faceMarkersSpotlightKey) }

    /// Draws no face markers at all.
    ///
    /// The state reached by unchecking DEFAULT with nothing else selected, and the reason DEFAULT
    /// is a real control rather than a label: without this, "no variants on" and "the current
    /// approach" are the same state and the list cannot say which it means.
    ///
    /// Faces stay tappable — the hit regions are not the drawing — so this is *no chrome*, not *no
    /// selection*. It is also the honest baseline for judging the other three: the question every
    /// variant is answering is how much of this you can get away with.
    static let faceMarkersHiddenKey = "featureFaceMarkersHidden"

    static var faceMarkersHidden: Bool { UserDefaults.standard.bool(forKey: faceMarkersHiddenKey) }
}
