import Foundation

/// Behaviour under evaluation, toggled from GENERAL SETTINGS.
///
/// Kept apart from the ordinary preferences (`autoPlayGifs`, `appTheme`, `selectedAppIcon`)
/// because these are not tastes the user is expected to hold a permanent opinion about — each one
/// is expected to either become unconditional or be deleted once it has been lived with. Having
/// them in one place is what makes that cleanup a single search rather than an archaeology
/// exercise across the view model, the settings sheet and `UserDefaults`.
///
/// Flags default **off** via `UserDefaults.bool(forKey:)` — except the adopted profile
/// registered in `EnhanceApp.init` *(user's call, 2026-08-26)*, which turns the lived-with set
/// on for fresh installs. An explicit toggle always wins over the registration domain.
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

    // MARK: - Button gradients
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

    /// Sweeps a soft band of light up and down inside each marker, so a face reads as being
    /// *scanned* rather than merely outlined.
    ///
    /// Independent of RETICLE rather than part of it, because the sweep is confined to the marker
    /// rect and therefore composes with any of the looks — though the viewfinder is what it was
    /// drawn for.
    ///
    /// **This is looping motion, which is what makes DEFAULT's pulse the worst thing about it.**
    /// The difference is meant to be that this one is quiet, opt-in, and bounded by a shape you are
    /// already looking at — but it is the same species of idea, so judge it against the pulse
    /// honestly. Under CALM it inherits the auto-hide and stops on its own.
    static let faceMarkersScanlineKey = "featureFaceMarkersScanline"

    static var faceMarkersScanline: Bool { UserDefaults.standard.bool(forKey: faceMarkersScanlineKey) }

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

    /// The pixel-dissolve a freshly saved GIF plays as it lands in the grid.
    static let motionSaveRevealKey = "featureMotionSaveReveal"
    static var motionSaveReveal: Bool { UserDefaults.standard.bool(forKey: motionSaveRevealKey) }

    /// The animation over the canvas while a GIF is being generated. Which of the four concepts
    /// plays is `MotionTuning.generatingStyle`; this only decides whether the editor reads it,
    /// so the shipped spinner survives the flag being off.
    static let motionGeneratingKey = "featureMotionGenerating"
    static var motionGenerating: Bool { UserDefaults.standard.bool(forKey: motionGeneratingKey) }

    /// Device-tilt parallax on the gallery grid. Note this one starts a `CMMotionManager`, so
    /// unlike the others it has a running cost while it is on.
    static let motionParallaxKey = "featureMotionParallax"
    static var motionParallax: Bool { UserDefaults.standard.bool(forKey: motionParallaxKey) }

    /// The shared-element zoom from a tapped gallery cell into the editor canvas.
    static let motionSharedZoomKey = "featureMotionSharedZoom"
    static var motionSharedZoom: Bool { UserDefaults.standard.bool(forKey: motionSharedZoomKey) }

    // MARK: - Button label text effects

    /// Animated, rotating text on the gallery's MAKE A GIF button.
    ///
    /// The label plays one of the photo text-effect entrances (`TextAnimationType`) and cycles
    /// through a set of phrases; which preset, which phrases and what rhythm are
    /// `ButtonLabelTuning`, edited live in BUTTON TEXT LAB. This flag only decides whether the
    /// gallery button reads that tuning — off, the button renders the plain `Text` label exactly
    /// as it always has, and the lab's preview keeps animating either way so the experiment can
    /// be judged without turning it on for the whole app.
    static let buttonTextEffectsKey = "featureButtonTextEffects"

    static var buttonTextEffects: Bool { UserDefaults.standard.bool(forKey: buttonTextEffectsKey) }

    // MARK: - Camera

    /// An in-app camera for shooting the photo a GIF starts from, instead of picking one.
    ///
    /// Gates the camera button beside MAKE A GIF and everything behind it: the viewfinder
    /// overlay above the gallery, and the captured photo's flight into the editor canvas. The
    /// flight is part of this experiment's choreography, not a second opinion to hold — it is
    /// deliberately **not** ANDed with `motionSharedZoom`, whose question (should tapping an
    /// existing GIF zoom?) is unrelated to whether a camera user sees the feature as designed.
    static let cameraCaptureKey = "featureCameraCapture"

    static var cameraCapture: Bool { UserDefaults.standard.bool(forKey: cameraCaptureKey) }

    /// The camera feed's pixel-resolve intro: the viewfinder arrives coarsely pixelated and
    /// sharpens to the live feed — the ENHANCE treatment as the feed's own loading state.
    ///
    /// Off, the feed keeps its plain opacity fade, and the frame tap that feeds the effect is
    /// never enabled — the video-data pipeline stays cold, so the flag removes the cost along
    /// with the look. The effect's two knobs (PIXEL SIZE, REVEAL TIME) live under this row in
    /// settings and write `MotionTuning.cameraRevealCell` / `.cameraRevealTime` — the same
    /// values MOTION LAB's camera section edits, one source of truth between the two.
    static let cameraRevealKey = "featureCameraReveal"

    static var cameraReveal: Bool { UserDefaults.standard.bool(forKey: cameraRevealKey) }

    // MARK: - Touch experiments
    //
    // Interactions where the photo or the preview answers to a finger directly. Tuned in CANVAS
    // LAB (`CanvasTuning`); each of these is its own switch so one can be lived with alone.

    /// A one-finger touch on the canvas aims LAZER EYES (see `LaserAim`). Registered on in
    /// `EnhanceApp.init` because it shipped before it was gated; off restores the classic flare
    /// and the one-finger pan under that filter.
    static let laserAimKey = "featureLaserAim"

    static var laserAim: Bool { UserDefaults.standard.bool(forKey: laserAimKey) }

    /// Drag across a finished GIF to scrub it; hold to freeze; lift to resume. Read by
    /// `GIFPreviewView`, which hands the preview a display-link player instead of
    /// `UIImageView`'s own animation so it can be paused on a frame.
    static let scrubPreviewKey = "featureScrubPreview"

    static var scrubPreview: Bool { UserDefaults.standard.bool(forKey: scrubPreviewKey) }

    /// Effect sliders keep going past their last dot, up to `CanvasTuning.overdriveMax`. The knob
    /// turns red and its readout glitches; effects receive the raw value and clamp — or not — on
    /// their own terms. See `EffectParameter.clampSlider`.
    static let sliderOverdriveKey = "featureSliderOverdrive"

    static var sliderOverdrive: Bool { UserDefaults.standard.bool(forKey: sliderOverdriveKey) }

    /// A PATH card on the ZOOM tab: draw a route on the photo and the GIF travels it, Ken Burns
    /// style. See `ZoomPath`, `PathAnimator` and the PATH section of CANVAS LAB.
    static let pathZoomKey = "featurePathZoom"

    static var pathZoom: Bool { UserDefaults.standard.bool(forKey: pathZoomKey) }

    /// SAVE and SHARE gain video options: the finished GIF is transcoded to an H.264 `.mp4` by
    /// `VideoExporter`, played `CanvasTuning.videoLoops` times. Videos save to the camera roll
    /// rather than the MY GIFS album, which stays GIF-only — the storage question ROADMAP §3
    /// parked stickers on is left parked.
    static let videoExportKey = "featureVideoExport"

    static var videoExport: Bool { UserDefaults.standard.bool(forKey: videoExportKey) }

    /// Hold the in-app camera's shutter to capture a burst of real frames; the GIF is built
    /// from them, effects on top, so a face filter rides a face that actually moves. Needs
    /// IN-APP CAMERA. See `CameraViewModel.beginBurst`, `BurstFrame`, and the burst knobs in
    /// Settings (`CanvasTuning.burstDuration` / `burstFPS`).
    static let burstCaptureKey = "featureBurstCapture"

    static var burstCapture: Bool { UserDefaults.standard.bool(forKey: burstCaptureKey) }

    // MARK: - Look

    /// Every corner radius in the app collapses to 0 *(user's ask, 2026-09-03)*. Read by
    /// `AppConstants.CornerRadius`, which every rounded shape goes through — so this is one
    /// switch rather than a hunt through the views. Circles stay circles; capsules become
    /// rectangles. Read at body time, so a screen already on the stack repaints on its next
    /// evaluation rather than the instant the toggle flips.
    static let squareCornersKey = "featureSquareCorners"

    static var squareCorners: Bool { UserDefaults.standard.bool(forKey: squareCornersKey) }

    // MARK: - Motion effects

    /// FEATURE-MOTION-EFFECTS.md: a burst is analysed for a subject mask per frame and for how
    /// the subject and camera moved, and effects that read that (FRAME ECHO and the
    /// motion-aware cards) appear on the IMAGE tab for bursts. Off, no analysis runs and the
    /// cards are hidden; the foundation costs nothing.
    static let motionEffectsKey = "featureMotionEffects"

    static var motionEffects: Bool { UserDefaults.standard.bool(forKey: motionEffectsKey) }
}
