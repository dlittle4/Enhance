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

    // MARK: - View transitions (MOTION LAB)

    /// One key per animation rather than one umbrella, because these are four unrelated visual
    /// changes in unrelated parts of the UI — closer to a set of independent experiments than to
    /// a single feature. Grading them together would block shipping one while another is still
    /// being tuned. `MotionTuning` holds the values; these decide who reads them.

    /// Staggered chrome entrance when the editor opens.
    static let motionEntranceKey = "featureMotionEntrance"
    static var motionEntrance: Bool { UserDefaults.standard.bool(forKey: motionEntranceKey) }

    /// Scale-and-fade on the effect card gallery when the category changes.
    static let motionCategorySwitchKey = "featureMotionCategorySwitch"
    static var motionCategorySwitch: Bool { UserDefaults.standard.bool(forKey: motionCategorySwitchKey) }

    /// The selected category tab's capsule growing in rather than fading in place.
    static let motionTabScaleKey = "featureMotionTabScale"
    static var motionTabScale: Bool { UserDefaults.standard.bool(forKey: motionTabScaleKey) }

    /// Press feedback on the effect cards, which have none today.
    static let motionTilePressKey = "featureMotionTilePress"
    static var motionTilePress: Bool { UserDefaults.standard.bool(forKey: motionTilePressKey) }
}
