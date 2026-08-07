import Foundation

/// Which picker row an effect wants below its sliders. Effects that need no
/// secondary selection return nil from `colorPickerKind`.
enum EffectPickerKind {
    case tintColor
    case gradientRamp
}

/// Secondary inputs to `VisualEffectType.effect(intensity:options:)`. Bundled into
/// a struct because the factory was heading for five positional parameters, and
/// every new one otherwise touches all three call sites. Every member is defaulted
/// so `type.effect()` stays valid.
struct EffectOptions {
    var size: Double = 0.5
    var tintColor: LaserColor = .red
    var gradientRamp: GradientRamp = .sunset

    init(size: Double = 0.5, tintColor: LaserColor = .red, gradientRamp: GradientRamp = .sunset) {
        self.size = size
        self.tintColor = tintColor
        self.gradientRamp = gradientRamp
    }
}

enum VisualEffectType: String, CaseIterable, Identifiable, Hashable {
    case chromaShift   = "CHROMA SHIFT"
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

    // Colour grades, grouped at the end so the distortions above stay together.
    case sepia         = "SEPIA"
    case vintage       = "VINTAGE"
    case warm          = "WARM"
    case cool          = "COOL"
    case fade          = "FADE"
    case vivid         = "VIVID"
    case contrast      = "CONTRAST"
    case noir          = "NOIR"
    case mono          = "MONO"

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

    /// The colour grades, which all share `FilterPresetEffect`.
    var filterPreset: FilterPreset? {
        switch self {
        case .sepia:    return .sepia
        case .vintage:  return .vintage
        case .warm:     return .warm
        case .cool:     return .cool
        case .fade:     return .fade
        case .vivid:    return .vivid
        case .contrast: return .contrast
        case .noir:     return .noir
        case .mono:     return .mono
        default:        return nil
        }
    }

    /// Whether this effect supports the separate size slider.
    var supportsSizeControl: Bool {
        self == .fisheye
    }

    /// Label for the second slider (used for size or other secondary controls).
    var secondSliderLabel: String {
        switch self {
        case .fisheye: return "SIZE"
        default:       return "SIZE"
        }
    }

    /// Which picker row to show beneath the sliders, if any.
    var colorPickerKind: EffectPickerKind? {
        switch self {
        case .duotone, .coloredEdges: return .tintColor
        case .gradientMap:            return .gradientRamp
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

        if let preset = filterPreset {
            return FilterPresetEffect(intensity: clamped, preset: preset)
        }

        switch self {
        case .chromaShift:  return ChromaticAberrationEffect(intensity: clamped)
        case .halftone:     return HalftoneEffect(intensity: clamped)
        case .fisheye:      return FisheyeEffect(intensity: clamped, size: max(0, min(1, options.size)))
        case .swirl:        return SwirlEffect(intensity: clamped)
        case .pixelate:     return PixelateEffect(intensity: clamped)
        case .rainbow:      return RainbowGradientEffect(intensity: clamped)
        case .heatHaze:     return HeatHazeEffect(intensity: clamped)
        case .motionBlur:   return MotionBlurEffect(intensity: clamped)
        case .gradientMap:  return GradientMapEffect(intensity: clamped, ramp: options.gradientRamp)
        case .coloredEdges: return ColoredEdgesEffect(intensity: clamped, color: options.tintColor)
        case .dither:       return DitherEffect(intensity: clamped)

        case .monotone:     return MonotoneEffect(intensity: clamped)
        case .duotone:      return DuotoneEffect(intensity: clamped, color: options.tintColor)
        case .bloom:        return BloomEffect(intensity: clamped)
        case .inversion:    return InversionEffect(intensity: clamped)
        case .vintageGrain: return VintageGrainEffect(intensity: clamped)
        case .popArt:       return PopArtEffect(intensity: clamped)

        // Handled by the filterPreset branch above; unreachable.
        case .sepia, .vintage, .warm, .cool, .fade, .vivid, .contrast, .noir, .mono:
            return FilterPresetEffect(intensity: clamped, preset: .sepia)
        }
    }
}
