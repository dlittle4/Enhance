import Foundation

enum VisualEffectType: String, CaseIterable, Identifiable, Hashable {
    case fadeToBW    = "FADE TO B&W"
    case chromaShift = "CHROMA SHIFT"
    case halftone    = "HALFTONE"
    case fisheye     = "FISHEYE"
    case swirl       = "SWIRL"
    case scanlines   = "SCANLINES"
    case pixelate    = "PIXELATE"
    case ripple      = "RIPPLE"

    var id: String { rawValue }

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

    func effect(intensity: Double = 0.5, size: Double = 0.5) -> VisualEffect {
        let clamped = max(0, min(1, intensity))
        switch self {
        case .fadeToBW:    return FadeToBWEffect(intensity: clamped)
        case .chromaShift: return ChromaticAberrationEffect(intensity: clamped)
        case .halftone:    return HalftoneEffect(intensity: clamped)
        case .fisheye:     return FisheyeEffect(intensity: clamped, size: max(0, min(1, size)))
        case .swirl:       return SwirlEffect(intensity: clamped)
        case .scanlines:   return ScanlinesEffect(intensity: clamped)
        case .pixelate:    return PixelateEffect(intensity: clamped)
        case .ripple:      return RippleEffect(intensity: clamped)
        }
    }
}
