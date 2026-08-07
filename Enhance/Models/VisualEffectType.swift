import Foundation

enum VisualEffectType: String, CaseIterable, Identifiable, Hashable {
    case chromaShift   = "CHROMA SHIFT"
    case halftone      = "HALFTONE"
    case fisheye       = "FISHEYE"
    case swirl         = "SWIRL"
    case pixelate      = "PIXELATE"
    case rainbow       = "RAINBOW"
    case heatHaze      = "HEAT HAZE"
    case motionBlur    = "MOTION BLUR"

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

    /// Whether this effect shows a color/preset picker row.
    var supportsColorPicker: Bool {
        self == .duotone
    }

    /// Progress value for the static live preview. Most effects look best
    /// at full strength (1.0). Pixelate reverses — it resolves as progress
    /// increases — so use a low value to show the pixelation.
    var previewProgress: CGFloat {
        switch self {
        case .pixelate: return 0.2
        default:        return 1.0
        }
    }

    func effect(intensity: Double = 0.5, size: Double = 0.5, duotoneColor: LaserColor = .red) -> VisualEffect {
        let clamped = max(0, min(1, intensity))
        switch self {
        case .chromaShift:  return ChromaticAberrationEffect(intensity: clamped)
        case .halftone:     return HalftoneEffect(intensity: clamped)
        case .fisheye:      return FisheyeEffect(intensity: clamped, size: max(0, min(1, size)))
        case .swirl:        return SwirlEffect(intensity: clamped)
        case .pixelate:     return PixelateEffect(intensity: clamped)
        case .rainbow:      return RainbowGradientEffect(intensity: clamped)
        case .monotone:     return MonotoneEffect(intensity: clamped)
        case .duotone:      return DuotoneEffect(intensity: clamped, color: duotoneColor)
        case .heatHaze:     return HeatHazeEffect(intensity: clamped)
        case .bloom:        return BloomEffect(intensity: clamped)
        case .motionBlur:   return MotionBlurEffect(intensity: clamped)
        case .inversion:    return InversionEffect(intensity: clamped)
        case .vintageGrain: return VintageGrainEffect(intensity: clamped)
        case .popArt:       return PopArtEffect(intensity: clamped)
        }
    }
}
