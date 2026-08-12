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
    var tintColor: LaserColor = .red
    var gradientStops: GradientStops = .default

    init(size: Double = 0.5,
         tertiary: Double = 0.5,
         tintColor: LaserColor = .red,
         gradientStops: GradientStops = .default) {
        self.size = size
        self.tertiary = tertiary
        self.tintColor = tintColor
        self.gradientStops = gradientStops
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
        .monotone, .duotone, .bloom, .inversion, .vintageGrain, .popArt
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
        var params = [EffectParameter(id: EffectParameter.intensityID, label: "INTENSITY")]

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
        default:
            break
        }

        switch colorPickerKind {
        case .tintColor:
            params.append(EffectParameter(id: "tint", label: "COLOUR", kind: .tintColor))
        case .gradientStops:
            params.append(EffectParameter(id: "stops", label: "COLOURS", kind: .gradientStops))
        case .none:
            break
        }

        return params
    }

    /// Which picker row to show beneath the sliders, if any.
    var colorPickerKind: EffectPickerKind? {
        switch self {
        case .duotone, .coloredEdges: return .tintColor
        case .gradientMap:            return .gradientStops
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
        case .pixelate:     return PixelateEffect(intensity: clamped)
        case .rainbow:      return RainbowGradientEffect(intensity: clamped, speed: max(0, min(1, options.size)))
        case .heatHaze:     return HeatHazeEffect(intensity: clamped,
                                                  frequency: max(0, min(1, options.size)),
                                                  speed: max(0, min(1, options.tertiary)))
        case .motionBlur:   return MotionBlurEffect(intensity: clamped, angle: max(0, min(1, options.size)))
        case .gradientMap:  return GradientMapEffect(intensity: clamped,
                                                     stops: options.gradientStops,
                                                     midpoint: max(0, min(1, options.size)))
        case .coloredEdges: return ColoredEdgesEffect(intensity: clamped, color: options.tintColor)
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
