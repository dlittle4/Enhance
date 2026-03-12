import Foundation

enum FaceFilterType: String, CaseIterable, Identifiable, Hashable {
    // Original face-specific effects
    case lazerEyes  = "LAZER EYES"
    case googlyEyes = "GOOGLY EYES"
    case squeeze    = "SQUEEZE"
    case handsome   = "HANDSOME"

    // Visual effects adapted for face
    case fisheye    = "FISHEYE"
    case swirl      = "SWIRL"
    case pixelate   = "PIXELATE"
    case ripple     = "RIPPLE"
    case fadeToBW   = "FADE TO B&W"
    case chromaShift = "CHROMA SHIFT"

    var id: String { rawValue }

    /// Primary slider label.
    var sliderLabel: String {
        switch self {
        case .googlyEyes: return "SIZE"
        case .handsome:   return "HANDSOMENESS"
        case .ripple:     return "REDNESS"
        default:          return "INTENSITY"
        }
    }

    /// Whether this filter exposes a second slider.
    var supportsSecondSlider: Bool {
        self == .googlyEyes || self == .lazerEyes || self == .fisheye
    }

    /// Label for the second slider.
    var secondSliderLabel: String {
        switch self {
        case .lazerEyes:  return "SIZE"
        case .googlyEyes: return "SPEED"
        case .fisheye:    return "SIZE"
        default:          return ""
        }
    }

    /// Human-readable intensity bucket for a slider value.
    func intensityBucket(_ value: Double) -> String {
        switch value {
        case ..<0.3:  return "LIGHT"
        case ..<0.6:  return "MEDIUM"
        case ..<0.85: return "HEAVY"
        default:      return "MAX"
        }
    }

    /// Human-readable bucket for the second slider value.
    func secondSliderBucket(_ value: Double) -> String {
        switch self {
        case .googlyEyes:
            switch value {
            case ..<0.25: return "SLOW"
            case ..<0.5:  return "MEDIUM"
            case ..<0.75: return "FAST"
            default:      return "HYPER"
            }
        case .lazerEyes, .fisheye:
            switch value {
            case ..<0.3:  return "SMALL"
            case ..<0.6:  return "MEDIUM"
            case ..<0.85: return "LARGE"
            default:      return "MAX"
            }
        default:
            return "MEDIUM"
        }
    }

    /// Progress value used for the static live preview. Most effects look best
    /// at 1.0 (full strength). Pixelate needs a low value because its full
    /// strength is at progress=0 (fully pixelated → resolves to clear).
    var previewProgress: CGFloat {
        switch self {
        case .pixelate: return 0.2
        default:        return 1.0
        }
    }

    func effect(intensity: Double = 0.5, secondValue: Double = 0.5) -> FaceEffect {
        let clamped = max(0, min(1, intensity))
        let clampedSecond = max(0, min(1, secondValue))
        switch self {
        case .lazerEyes:  return LazerEyesEffect(intensity: clamped, size: clampedSecond)
        case .googlyEyes: return GooglyEyesEffect(size: clamped, speed: clampedSecond)
        case .squeeze:    return SqueezeEffect(intensity: clamped)
        case .handsome:   return HandsomeEffect(intensity: clamped)

        case .fisheye:    return FaceVisualEffect(effect: FisheyeEffect(intensity: clamped, size: clampedSecond), skipDelay: true)
        case .swirl:      return FaceVisualEffect(effect: SwirlEffect(intensity: clamped), skipDelay: true)
        case .pixelate:   return FaceVisualEffect(effect: PixelateEffect(intensity: clamped), skipDelay: true, passRawProgress: true)
        case .ripple:     return FaceVisualEffect(effect: RippleEffect(intensity: clamped), skipDelay: true)
        case .fadeToBW:   return FaceVisualEffect(effect: FadeToBWEffect(intensity: clamped), skipDelay: true)
        case .chromaShift: return FaceVisualEffect(effect: ChromaticAberrationEffect(intensity: clamped), skipDelay: true)
        }
    }
}
