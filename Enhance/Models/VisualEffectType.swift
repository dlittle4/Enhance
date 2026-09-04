import Foundation

/// Which picker row an effect wants below its sliders. Effects that need no
/// secondary selection return nil from `colorPickerKind`.
enum EffectPickerKind {
    case tintColor
    case gradientStops
}

/// Secondary inputs to `VisualEffectType.effect(intensity:options:)`. Bundled into
/// a struct because the factory was heading for five positional parameters, and
/// every new one otherwise touches all three call sites. Every member is defaulted
/// so `type.effect()` stays valid.
struct EffectOptions {
    var size: Double = 0.5
    /// Third slider slot — see `EffectParameter.tertiaryID`. Only effects declaring three
    /// sliders read it.
    var tertiary: Double = 0.5
    /// Fourth and fifth slider slots — see `EffectParameter.quaternaryID`. CAUSTIC reads
    /// `quaternary`; RISO is the only effect so far that needs all five.
    var quaternary: Double = 0.5
    var quinary: Double = 0.5
    var tintColor: LaserColor = .red
    var gradientStops: GradientStops = .default
    var pixelShape: PixelShape = .square

    init(size: Double = 0.5,
         tertiary: Double = 0.5,
         quaternary: Double = 0.5,
         quinary: Double = 0.5,
         tintColor: LaserColor = .red,
         gradientStops: GradientStops = .default,
         pixelShape: PixelShape = .square) {
        self.size = size
        self.tertiary = tertiary
        self.quaternary = quaternary
        self.quinary = quinary
        self.tintColor = tintColor
        self.gradientStops = gradientStops
        self.pixelShape = pixelShape
    }
}

enum VisualEffectType: String, CaseIterable, Identifiable, Hashable, ParameterizedEffect {
    static let parameterNamespace = "visual"

    case chromaShift   = "CHROMA SHIFT"
    case lensDistortion = "LENS"
    case halftone      = "HALFTONE"
    case fisheye       = "FISHEYE"
    case swirl         = "SWIRL"
    case pixelate      = "PIXELATE"
    case rainbow       = "RAINBOW"
    case heatHaze      = "HEAT HAZE"
    case motionBlur    = "MOTION BLUR"
    case gradientMap   = "GRADIENT"
    case coloredEdges  = "EDGES"
    case dither        = "DITHER"
    case sliceShift    = "SLICE SHIFT"
    case risoPrint     = "RISO"
    case caustic       = "CAUSTIC"
    case stretch       = "STRETCH"
    /// ROADMAP §2f — outlines of the segmented subject radiating outward from it.
    case subjectEcho   = "ECHO"
    /// FRAME ECHO (FEATURE-MOTION-EFFECTS.md §2): earlier burst frames' subject cut-outs
    /// behind the current one. **Burst-only** — see `VisualEffectType.burstOnly` and
    /// `EditorViewModel.carouselVisualEffects`; on a still the effect is the identity.
    case frameEcho     = "FRAME ECHO"
    /// MOTION TRAIL: FRAME ECHO with each echo smeared along the motion. Burst-only.
    case motionTrail   = "MOTION TRAIL"
    /// SPEED LINES: comic streaks behind the moving subject. Burst-only.
    case speedLines    = "SPEED LINES"
    /// ROADMAP §2b — 1-bit clustered-dot halftone in two spot colours.
    case bitmap        = "BITMAP"
    // The twelve SwiftUIShaders looks starred in SHADER LAB, graduated 2026-09-02 as Core Image
    // kernels — see `PackShaderEffect` and `Shaders/CI/ShaderPack.ci.metal`.
    case thermal       = "THERMAL"
    case chromaticSplit = "CHROMATIC SPLIT"
    case datamosh      = "DATAMOSH"
    case heatShimmer   = "HEAT SHIMMER"
    case liveRipple    = "LIVE RIPPLE"
    case melt          = "MELT"
    case neonEdge      = "NEON EDGE"
    case pixelateStorm = "PIXEL STORM"
    case shockwave     = "SHOCKWAVE"
    case solarize      = "SOLARIZE"
    case wavePool      = "WAVE POOL"
    /// The twelfth SHADER LAB star. Lives on the **ZOOM** tab as HEART BEAT — its beat reads as
    /// a zoom — with this effect's own controls in place of SPEED / PAUSE / MOTION; retired
    /// from the IMAGE carousel so it appears once. `EditorViewModel.activeVisualEffectList`
    /// appends it while `AnimatorType.heartBeat` is selected.
    case pulse         = "HEART BEAT"

    // MARK: - Retired
    // Hidden from the picker but kept compiled and tested — see `retired` below.

    case monotone      = "MONOTONE"
    case duotone       = "DUOTONE"
    case bloom         = "BLOOM"
    case inversion     = "INVERSION"
    case vintageGrain  = "VINTAGE GRAIN"
    case popArt        = "POP ART"

    var id: String { rawValue }

    /// Effects withdrawn from the UI on 2026-08-07 without deleting their
    /// implementations. They stay compiled, so they cannot silently rot, and the
    /// test suite still exercises them via `allCases`.
    ///
    /// To bring one back, delete it from this set — nothing else is needed.
    static let retired: Set<VisualEffectType> = [
        .monotone, .duotone, .bloom, .inversion, .vintageGrain, .popArt,
        // Withdrawn 2026-08-12 on the user's call — the look was not wanted. Kept compiled
        // rather than deleted, per this set's purpose: it is the only custom-kernel effect
        // besides RISO, so it is also the working second example of the CIKernel path.
        .caustic,
        // Withdrawn 2026-09-02 from EFFECTS LAB (user's call).
        .stretch,
        // Not withdrawn — *hosted elsewhere*. HEART BEAT is the ZOOM tab's card (see the case);
        // retiring it here is what keeps it off the IMAGE carousel. EFFECTS LAB can still window
        // it, and switching it on there would show it on both tabs.
        .pulse
    ]

    /// The effects the picker offers, in carousel order. Everything that walks the
    /// effect list for the *user* should use this; `allCases` still returns all of
    /// them and is what keeps retired effects under test.
    static var selectable: [VisualEffectType] {
        allCases.filter { !retired.contains($0) }
    }

    /// See `ParameterizedEffect.declaredDefault`. Keep in step with `parameters`.
    func declaredDefault(_ paramID: String) -> Double {
        switch (self, paramID) {
        case (.frameEcho, EffectParameter.tertiaryID): return 0
        case (.frameEcho, EffectParameter.quinaryID), (.motionTrail, EffectParameter.quinaryID), (.speedLines, EffectParameter.quinaryID): return 0
        // Strobe by default: every echo, fully opaque, never fading (user's call, 2026-09-03).
        case (.frameEcho, EffectParameter.quaternaryID), (.motionTrail, EffectParameter.quaternaryID): return 1
        case (.frameEcho, EffectParameter.intensityID), (.motionTrail, EffectParameter.intensityID): return 1
        case (.frameEcho, EffectParameter.sizeID), (.motionTrail, EffectParameter.sizeID): return 1
        default: return 0.5
        }
    }

    /// Effects that need a burst's frames to draw anything. Shown in the carousel only while
    /// the editor holds a burst and MOTION EFFECTS is on; selectable and lab-windowable
    /// regardless, so the lab and the tests see them like any other card.
    static let burstOnly: Set<VisualEffectType> = [.frameEcho, .motionTrail, .speedLines]

    /// The primary slider's label: INTENSITY for most, what the burst cards actually mean.
    private var primarySliderLabel: String {
        switch self {
        case .frameEcho, .motionTrail: return "FADE"
        case .speedLines: return "LENGTH"
        default: return "INTENSITY"
        }
    }

    var isBurstOnly: Bool { Self.burstOnly.contains(self) }

    var isRetired: Bool { Self.retired.contains(self) }

    /// The controls this effect exposes, in the order they should be shown.
    ///
    /// This is the single source of truth for an effect's UI. Adding a control here is
    /// all that is needed for it to appear — no layout changes, and no per-effect
    /// branching in the view.
    var parameters: [EffectParameter] {
        // COLOR leads when the effect has one *(user's call, 2026-08-13)*. It is the choice that
        // changes the effect most, and a swatch row reads as a heading for the sliders that
        // follow rather than a footnote to them. Built first rather than appended last, which is
        // where it used to go.
        //
        // The ids stay `"tint"` / `"stops"` — they are storage keys, and `EffectParameter` warns
        // that renaming one silently resets that control to its default. Only the label changed.
        var params: [EffectParameter] = []

        switch colorPickerKind {
        case .tintColor where isBurstOnly:
            params.append(EffectParameter(id: EffectParameter.quinaryID, label: "COLOR", kind: .tintColorOrNone, defaultValue: 0))
        case .tintColor:
            params.append(EffectParameter(id: "tint", label: "COLOR", kind: .tintColor))
        case .gradientStops:
            params.append(EffectParameter(id: "stops", label: "COLORS", kind: .gradientStops))
        case .none:
            break
        }

        // FRAME ECHO's primary is how much each echo keeps of the last, so it says so.
        params.append(EffectParameter(
            id: EffectParameter.intensityID,
            label: primarySliderLabel,
            defaultValue: declaredDefault(EffectParameter.intensityID),
            displaysPercent: isBurstOnly
        ))

        switch self {
        case .fisheye:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SIZE"))
        case .dither:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SCALE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "LEVELS"))
        case .lensDistortion:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "REACH"))
        case .motionBlur:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ANGLE"))
        case .swirl:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SIZE"))
        case .chromaShift:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ANGLE"))
        case .halftone:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SHARPNESS"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "ANGLE"))
        case .heatHaze:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "FREQUENCY"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPEED"))
        case .rainbow:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SPEED"))
        case .gradientMap:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "MIDPOINT"))
        case .pixelate:
            params.append(EffectParameter(id: "shape", label: "SHAPE", kind: .pixelShape))
        case .sliceShift:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SIZE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "JITTER"))
        case .risoPrint:
            // Four independent scalars plus the spot colours — the widest panel in the app,
            // and the first that scrolls by design (ROADMAP §1a, user's call 2026-08-12).
            // CONTRAST is not decoration: without it a flat photo collapses into the midtone
            // band and prints as a single colour.
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SCALE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "OFFSET"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "GRAIN"))
            params.append(EffectParameter(id: EffectParameter.quinaryID, label: "CONTRAST"))
        case .caustic:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SCALE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "SHARPNESS"))
        case .subjectEcho:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SPREAD"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "ECHOES"))
        case .frameEcho:
            // OPACITY is the nearest echo's; FADE is how much each further one keeps, up to
            // "all of it" so a trail can persist for the whole burst. The tint lives on the
            // colour row (NONE by default), in the quinary well.
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "OPACITY", defaultValue: 1, displaysPercent: true))
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ECHOES", defaultValue: 1))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPACING", defaultValue: 0))
        case .motionTrail:
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "OPACITY", defaultValue: 1, displaysPercent: true))
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ECHOES", defaultValue: 1))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SMEAR", displaysPercent: true))
        case .speedLines:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "DENSITY", displaysPercent: true))
        case .bitmap:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SCALE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "CONTRAST"))
        case .stretch:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ANGLE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "POSITION"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "REACH"))

        // The shader pack: INTENSITY is whatever the look reads as an *amount* (the pack's own
        // intensity, an amplitude, a spread) and the pack's other controls follow in its order.
        // NEON EDGE and SOLARIZE have no amount of their own, so INTENSITY blends the result
        // over the original and all four pack controls follow.
        case .thermal:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SHIMMER"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "NOISE SPEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "PALETTE"))
        case .chromaticSplit:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ANGLE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "EDGE ONLY"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "ANIMATE"))
        case .datamosh:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SMEAR"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "COLOR BLEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "GLITCH RATE"))
        case .heatShimmer:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "FREQUENCY"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "VERTICAL BIAS"))
        case .liveRipple:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "FREQUENCY"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "DAMPING"))
        case .melt:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "DRIP SCALE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "HEAT"))
        case .neonEdge:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "EDGE STRENGTH"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "GLOW"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "COLOR CYCLE"))
            params.append(EffectParameter(id: EffectParameter.quinaryID, label: "MIX ORIGINAL"))
        case .pixelateStorm:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "STORM"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SWIRL"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "PULSE"))
        case .pulse:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "BPM"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SHARPNESS"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "GLOW"))
        case .shockwave:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "WAVE SPEED"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "RING WIDTH"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "REPEAT"))
        case .solarize:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "THRESHOLD"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "CURVE"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "COLOR SEP"))
            params.append(EffectParameter(id: EffectParameter.quinaryID, label: "ANIMATE"))
        case .wavePool:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "WAVELENGTH"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "SPEED"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "COMPLEXITY"))
        default:
            break
        }

        // Last, and on every effect — it is a *modifier* on whatever is above it
        // rather than one of the effect's own qualities, so it reads wrong interleaved with
        // them. Off by default (ROADMAP §2f).
        //
        // Deliberately not restricted to a subset. §1g found the palettisation cost lands on
        // background *banding*, so effects that flatten to few colours (MONOTONE, DUOTONE,
        // RISO, DITHER) pair best and effects leaving a smooth gradient band worst — but that
        // is guidance on what to reach for first, not a reason to withhold the control. The
        // geometry-distorting effects are the ones to look at hardest: the subject is sampled
        // from the *undistorted* frame, so a strong warp can pull background detail up to a
        // silhouette that did not move.
        // ECHO is excluded: it *is* a subject effect, so "apply to the background only" is not a
        // meaningful modifier on it — it would mask the effect with the same mask it draws from.
        //
        // Retired effects are *not* excluded, as of EFFECTS LAB: the lab can switch a retired
        // effect back on for the user, and it should arrive with the same modifier every other
        // card has. The old `selectable` gate only ever existed because nobody could reach them.
        // HEART BEAT is excluded too: it runs from the ZOOM tab, whose panel has no subject mask
        // to offer, and the modifier is only honoured for the IMAGE tab's selection.
        // FRAME ECHO draws *from* the masks like ECHO does, so the toggle means nothing to it.
        if self != .subjectEcho, self != .pulse, !isBurstOnly {
            params.append(.backgroundOnly)
        }

        return params
    }

    /// Which picker row to show beneath the sliders, if any.
    var colorPickerKind: EffectPickerKind? {
        switch self {
        case .duotone, .coloredEdges, .caustic, .subjectEcho, .frameEcho, .motionTrail, .speedLines: return .tintColor
        case .gradientMap, .risoPrint, .bitmap: return .gradientStops
        default:                      return nil
        }
    }

    /// Whether this effect shows a picker row. Derived from `colorPickerKind` so the
    /// two can never drift apart.
    var supportsColorPicker: Bool { colorPickerKind != nil }

    /// Progress value for the static live preview. Most effects look best
    /// at full strength (1.0). Pixelate reverses — it resolves as progress
    /// increases — so use a low value to show the pixelation.
    var previewProgress: CGFloat {
        switch self {
        case .pixelate: return 0.2
        default:        return 1.0
        }
    }

    func effect(intensity: Double = 0.5, options: EffectOptions = EffectOptions()) -> VisualEffect {
        let clamped = EffectParameter.clampSlider(intensity)

        switch self {
        case .chromaShift:  return ChromaticAberrationEffect(intensity: clamped, angle: EffectParameter.clampSlider(options.size))
        case .lensDistortion: return LensDistortionEffect(intensity: clamped, reach: EffectParameter.clampSlider(options.size))
        case .halftone:     return HalftoneEffect(intensity: clamped,
                                                  sharpness: EffectParameter.clampSlider(options.size),
                                                  angle: EffectParameter.clampSlider(options.tertiary))
        case .fisheye:      return FisheyeEffect(intensity: clamped, size: EffectParameter.clampSlider(options.size))
        case .swirl:        return SwirlEffect(intensity: clamped, size: EffectParameter.clampSlider(options.size))
        case .pixelate:     return PixelateEffect(intensity: clamped, shape: options.pixelShape)
        case .rainbow:      return RainbowGradientEffect(intensity: clamped, speed: EffectParameter.clampSlider(options.size))
        case .heatHaze:     return HeatHazeEffect(intensity: clamped,
                                                  frequency: EffectParameter.clampSlider(options.size),
                                                  speed: EffectParameter.clampSlider(options.tertiary))
        case .motionBlur:   return MotionBlurEffect(intensity: clamped, angle: EffectParameter.clampSlider(options.size))
        case .gradientMap:  return GradientMapEffect(intensity: clamped,
                                                     stops: options.gradientStops,
                                                     midpoint: EffectParameter.clampSlider(options.size))
        case .coloredEdges: return ColoredEdgesEffect(intensity: clamped, color: options.tintColor)
        case .sliceShift:   return SliceShiftEffect(intensity: clamped,
                                                    size: EffectParameter.clampSlider(options.size),
                                                    jitter: EffectParameter.clampSlider(options.tertiary))
        case .risoPrint:    return RisoPrintEffect(intensity: clamped,
                                                   stops: options.gradientStops,
                                                   scale: EffectParameter.clampSlider(options.size),
                                                   misregistration: EffectParameter.clampSlider(options.tertiary),
                                                   grain: EffectParameter.clampSlider(options.quaternary),
                                                   contrast: EffectParameter.clampSlider(options.quinary))
        case .bitmap:
            return BitmapEffect(
                intensity: clamped,
                size: EffectParameter.clampSlider(options.size),
                contrast: EffectParameter.clampSlider(options.tertiary),
                stops: options.gradientStops
            )
        case .subjectEcho:
            // The mask is injected by `EditorViewModel.activeVisualEffectList`, which is the only
            // place that has one. Built here without it, the effect is a no-op — which is exactly
            // what the card thumbnail should show, since a thumbnail has no segmentation either.
            return SubjectEchoEffect(
                intensity: clamped,
                spread: EffectParameter.clampSlider(options.size),
                count: EffectParameter.clampSlider(options.tertiary),
                color: options.tintColor
            )
        case .frameEcho:
            // Draws only with a `MotionContext`, which the generator and the burst preview
            // stack hand it per frame; the thumbnail, rendered from one still, shows the photo.
            return FrameEchoEffect(
                intensity: clamped,
                echoes: EffectParameter.clampSlider(options.size),
                spacing: EffectParameter.clampSlider(options.tertiary),
                opacity: EffectParameter.clampSlider(options.quaternary),
                tintStrength: EffectParameter.clampSlider(options.quinary),
                color: options.tintColor
            )
        case .motionTrail:
            return FrameEchoEffect(
                intensity: clamped,
                echoes: EffectParameter.clampSlider(options.size),
                spacing: 0,
                opacity: EffectParameter.clampSlider(options.quaternary),
                tintStrength: EffectParameter.clampSlider(options.quinary),
                color: options.tintColor,
                smear: EffectParameter.clampSlider(options.tertiary)
            )
        case .speedLines:
            return SpeedLinesEffect(
                intensity: clamped,
                density: EffectParameter.clampSlider(options.size),
                color: EffectParameter.isOn(options.quinary) ? options.tintColor : nil
            )
        case .stretch:      return StretchEffect(intensity: clamped,
                                                 angle: EffectParameter.clampSlider(options.size),
                                                 position: EffectParameter.clampSlider(options.tertiary),
                                                 reach: EffectParameter.clampSlider(options.quaternary))
        case .caustic:      return CausticEffect(intensity: clamped,
                                                 size: EffectParameter.clampSlider(options.size),
                                                 speed: EffectParameter.clampSlider(options.tertiary),
                                                 sharpness: EffectParameter.clampSlider(options.quaternary),
                                                 color: options.tintColor)
        case .dither:       return DitherEffect(intensity: clamped,
                                                size: EffectParameter.clampSlider(options.size),
                                                levels: EffectParameter.clampSlider(options.tertiary))

        case .thermal, .chromaticSplit, .datamosh, .heatShimmer, .liveRipple, .melt,
             .neonEdge, .pixelateStorm, .pulse, .shockwave, .solarize, .wavePool:
            return packShaderEffect(intensity: clamped, options: options)

        case .monotone:     return MonotoneEffect(intensity: clamped)
        case .duotone:      return DuotoneEffect(intensity: clamped, color: options.tintColor)
        case .bloom:        return BloomEffect(intensity: clamped)
        case .inversion:    return InversionEffect(intensity: clamped)
        case .vintageGrain: return VintageGrainEffect(intensity: clamped)
        case .popArt:       return PopArtEffect(intensity: clamped)
        }
    }
}

// MARK: - Shader pack

extension VisualEffectType {

    /// The pack's controls, mapped linearly over the ranges SHADER LAB documents for them. The
    /// tuned values from the lab land as the knobs' opening positions via
    /// `EffectTuningTables.windows`, not here — 0…1 stays the slider's whole documented span.
    ///
    /// `ramp` is the progress ease-in `PackShaderEffect` applies; it multiplies the amount, and
    /// for PIXEL STORM eases the block size up from one pixel so a ramp of zero cannot divide
    /// the grid by zero.
    fileprivate func packShaderEffect(intensity: Double, options: EffectOptions) -> VisualEffect {
        func unit(_ v: Double) -> Double { EffectParameter.clampSlider(v) }
        func lerp(_ u: Double, _ lo: Double, _ hi: Double) -> Double { lo + unit(u) * (hi - lo) }
        let a = intensity
        let b = options.size, c = options.tertiary, d = options.quaternary, e = options.quinary

        switch self {
        case .thermal:
            return PackShaderEffect(kernel: .thermal) { ramp in
                [unit(a) * ramp, lerp(b, 0, 15), lerp(c, 0.5, 3), unit(d)]
            }
        case .chromaticSplit:
            return PackShaderEffect(kernel: .chromaticSplit) { ramp in
                [lerp(a, 0, 30) * ramp, lerp(b, 0, 6.28), unit(c), unit(d)]
            }
        case .datamosh:
            return PackShaderEffect(kernel: .datamosh) { ramp in
                [unit(a) * ramp, lerp(b, 0, 60), unit(c), lerp(d, 0.5, 5)]
            }
        case .heatShimmer:
            return PackShaderEffect(kernel: .heatShimmer) { ramp in
                [lerp(a, 0, 20) * ramp, lerp(b, 1, 30), lerp(c, 0.5, 5), unit(d)]
            }
        case .liveRipple:
            // The pack's fifth control, ring count, stays at the lab's tuned 1.2 (one ring).
            return PackShaderEffect(kernel: .liveRipple) { ramp in
                [lerp(a, 0, 30) * ramp, lerp(b, 5, 60), lerp(c, 1, 10), lerp(d, 0.5, 5), 1.2]
            }
        case .melt:
            return PackShaderEffect(kernel: .melt) { ramp in
                [lerp(a, 0, 100) * ramp, lerp(b, 1, 15), lerp(c, 0.1, 3), unit(d)]
            }
        case .neonEdge:
            return PackShaderEffect(kernel: .neonEdge) { ramp in
                [unit(a) * ramp, lerp(b, 1, 10), lerp(c, 0, 4), lerp(d, 0, 3), unit(e)]
            }
        case .pixelateStorm:
            return PackShaderEffect(kernel: .pixelateStorm) { ramp in
                [1 + (lerp(a, 2, 40) - 1) * ramp, unit(b), lerp(c, 0, 3), lerp(d, 0, 3)]
            }
        case .pulse:
            return PackShaderEffect(kernel: .pulse) { ramp in
                [lerp(a, 0, 30) * ramp, lerp(b, 30, 180), lerp(c, 1, 10), unit(d) * ramp]
            }
        case .shockwave:
            return PackShaderEffect(kernel: .shockwave) { ramp in
                [lerp(b, 50, 500), lerp(c, 5, 60), lerp(a, 5, 80) * ramp, lerp(d, 0.5, 5)]
            }
        case .solarize:
            return PackShaderEffect(kernel: .solarize) { ramp in
                [unit(a) * ramp, lerp(b, 0.2, 0.8), lerp(c, 0, 3), unit(d), unit(e)]
            }
        case .wavePool:
            return PackShaderEffect(kernel: .wavePool) { ramp in
                [lerp(a, 0, 25) * ramp, lerp(b, 5, 40), lerp(c, 0.5, 5), lerp(d, 1, 6)]
            }
        default:
            return MonotoneEffect(intensity: 0)
        }
    }
}
