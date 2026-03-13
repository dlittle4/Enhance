import Foundation

enum VisualEffectType: String, CaseIterable, Identifiable, Hashable {
    case chromaShift = "CHROMA SHIFT"
    case halftone    = "HALFTONE"
    case fisheye     = "FISHEYE"
    case swirl       = "SWIRL"
    case pixelate    = "PIXELATE"
    case rainbow     = "RAINBOW"

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

    /// Progress value for the static live preview. Most effects look best
    /// at full strength (1.0). Pixelate reverses — it resolves as progress
    /// increases — so use a low value to show the pixelation.
    var previewProgress: CGFloat {
        switch self {
        case .pixelate: return 0.2
        default:        return 1.0
        }
    }

    func effect(intensity: Double = 0.5, size: Double = 0.5) -> VisualEffect {
        let clamped = max(0, min(1, intensity))
        switch self {
        case .chromaShift: return ChromaticAberrationEffect(intensity: clamped)
        case .halftone:    return HalftoneEffect(intensity: clamped)
        case .fisheye:     return FisheyeEffect(intensity: clamped, size: max(0, min(1, size)))
        case .swirl:       return SwirlEffect(intensity: clamped)
        case .pixelate:    return PixelateEffect(intensity: clamped)
        case .rainbow:     return RainbowGradientEffect(intensity: clamped)
        }
    }
}
