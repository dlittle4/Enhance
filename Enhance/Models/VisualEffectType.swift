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
    /// ROADMAP §2b — 1-bit clustered-dot halftone in two spot colours.
    case bitmap        = "BITMAP"

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
        .caustic
    ]

    /// The effects the picker offers, in carousel order. Everything that walks the
    /// effect list for the *user* should use this; `allCases` still returns all of
    /// them and is what keeps retired effects under test.
    static var selectable: [VisualEffectType] {
        allCases.filter { !retired.contains($0) }
    }

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
        case .tintColor:
            params.append(EffectParameter(id: "tint", label: "COLOR", kind: .tintColor))
        case .gradientStops:
            params.append(EffectParameter(id: "stops", label: "COLORS", kind: .gradientStops))
        case .none:
            break
        }

        params.append(EffectParameter(id: EffectParameter.intensityID, label: "INTENSITY"))

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
        case .bitmap:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "SCALE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "CONTRAST"))
        case .stretch:
            params.append(EffectParameter(id: EffectParameter.sizeID, label: "ANGLE"))
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "POSITION"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "REACH"))
        default:
            break
        }

        // Last, and on every selectable effect — it is a *modifier* on whatever is above it
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
        if Self.selectable.contains(self), self != .subjectEcho {
            params.append(.backgroundOnly)
        }

        return params
    }

    /// Which picker row to show beneath the sliders, if any.
    var colorPickerKind: EffectPickerKind? {
        switch self {
        case .duotone, .coloredEdges, .caustic, .subjectEcho: return .tintColor
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
        let clamped = max(0, min(1, intensity))

        switch self {
        case .chromaShift:  return ChromaticAberrationEffect(intensity: clamped, angle: max(0, min(1, options.size)))
        case .lensDistortion: return LensDistortionEffect(intensity: clamped, reach: max(0, min(1, options.size)))
        case .halftone:     return HalftoneEffect(intensity: clamped,
                                                  sharpness: max(0, min(1, options.size)),
                                                  angle: max(0, min(1, options.tertiary)))
        case .fisheye:      return FisheyeEffect(intensity: clamped, size: max(0, min(1, options.size)))
        case .swirl:        return SwirlEffect(intensity: clamped, size: max(0, min(1, options.size)))
        case .pixelate:     return PixelateEffect(intensity: clamped, shape: options.pixelShape)
        case .rainbow:      return RainbowGradientEffect(intensity: clamped, speed: max(0, min(1, options.size)))
        case .heatHaze:     return HeatHazeEffect(intensity: clamped,
                                                  frequency: max(0, min(1, options.size)),
                                                  speed: max(0, min(1, options.tertiary)))
        case .motionBlur:   return MotionBlurEffect(intensity: clamped, angle: max(0, min(1, options.size)))
        case .gradientMap:  return GradientMapEffect(intensity: clamped,
                                                     stops: options.gradientStops,
                                                     midpoint: max(0, min(1, options.size)))
        case .coloredEdges: return ColoredEdgesEffect(intensity: clamped, color: options.tintColor)
        case .sliceShift:   return SliceShiftEffect(intensity: clamped,
                                                    size: max(0, min(1, options.size)),
                                                    jitter: max(0, min(1, options.tertiary)))
        case .risoPrint:    return RisoPrintEffect(intensity: clamped,
                                                   stops: options.gradientStops,
                                                   scale: max(0, min(1, options.size)),
                                                   misregistration: max(0, min(1, options.tertiary)),
                                                   grain: max(0, min(1, options.quaternary)),
                                                   contrast: max(0, min(1, options.quinary)))
        case .bitmap:
            return BitmapEffect(
                intensity: clamped,
                size: max(0, min(1, options.size)),
                contrast: max(0, min(1, options.tertiary)),
                stops: options.gradientStops
            )
        case .subjectEcho:
            // The mask is injected by `EditorViewModel.activeVisualEffectList`, which is the only
            // place that has one. Built here without it, the effect is a no-op — which is exactly
            // what the card thumbnail should show, since a thumbnail has no segmentation either.
            return SubjectEchoEffect(
                intensity: clamped,
                spread: max(0, min(1, options.size)),
                count: max(0, min(1, options.tertiary)),
                color: options.tintColor
            )
        case .stretch:      return StretchEffect(intensity: clamped,
                                                 angle: max(0, min(1, options.size)),
                                                 position: max(0, min(1, options.tertiary)),
                                                 reach: max(0, min(1, options.quaternary)))
        case .caustic:      return CausticEffect(intensity: clamped,
                                                 size: max(0, min(1, options.size)),
                                                 speed: max(0, min(1, options.tertiary)),
                                                 sharpness: max(0, min(1, options.quaternary)),
                                                 color: options.tintColor)
        case .dither:       return DitherEffect(intensity: clamped,
                                                size: max(0, min(1, options.size)),
                                                levels: max(0, min(1, options.tertiary)))

        case .monotone:     return MonotoneEffect(intensity: clamped)
        case .duotone:      return DuotoneEffect(intensity: clamped, color: options.tintColor)
        case .bloom:        return BloomEffect(intensity: clamped)
        case .inversion:    return InversionEffect(intensity: clamped)
        case .vintageGrain: return VintageGrainEffect(intensity: clamped)
        case .popArt:       return PopArtEffect(intensity: clamped)
        }
    }
}
