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
}
