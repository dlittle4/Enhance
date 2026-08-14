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

    /// Quantizes every button gradient to two colours, thresholded by animated random noise.
    ///
    /// The `MeshGradient` underneath is still drawn but never shown: `staticDither` reads its
    /// luminance as a density field and throws the colours away, so the mesh supplies the falloff
    /// across a button while the two visible colours come from `GradientTuning`'s poles. Off, the
    /// gradient renders exactly as it always has. See `ButtonGradientStyle.resolve`.
    static let staticGradientKey = "featureStaticGradient"

    static var staticGradient: Bool { UserDefaults.standard.bool(forKey: staticGradientKey) }

    /// The same two-colour quantization driven by an ordered Bayer matrix instead of noise.
    ///
    /// Independent of `staticGradient` rather than exclusive with it, because both are weights on
    /// one shader: with both on the thresholds sum into a jittered ordered dither. The difference
    /// to look for is motion — the Bayer matrix is a function of position alone, so its texture
    /// holds still and shimmers as the colours pulse, where noise boils.
    static let ditherGradientKey = "featureDitherGradient"

    static var ditherGradient: Bool { UserDefaults.standard.bool(forKey: ditherGradientKey) }

    /// Adds the animated ring around gradient buttons, with the static treatment on it.
    ///
    /// Drawn by `ButtonGradientBackground` rather than by `CircleButton`, whose border was the
    /// obvious home until it turned out that component is referenced by nothing but its own
    /// previews.
    static let staticBorderKey = "featureStaticBorder"

    static var staticBorder: Bool { UserDefaults.standard.bool(forKey: staticBorderKey) }
}
