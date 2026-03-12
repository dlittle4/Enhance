import Foundation

enum FaceFilterType: String, CaseIterable, Identifiable, Hashable {
    case lazerEyes  = "LAZER EYES"
    case googlyEyes = "GOOGLY EYES"
    case bobbleHead = "BOBBLE HEAD"
    case handsome   = "HANDSOME"

    var id: String { rawValue }

    /// Primary slider label.
    var sliderLabel: String {
        switch self {
        case .lazerEyes:  return "INTENSITY"
        case .googlyEyes: return "SIZE"
        case .bobbleHead: return "BIGNESS"
        case .handsome:   return "HANDSOMENESS"
        }
    }

    /// Whether this filter exposes a second slider.
    var supportsSecondSlider: Bool {
        self == .googlyEyes || self == .lazerEyes
    }

    /// Label for the second slider.
    var secondSliderLabel: String {
        switch self {
        case .lazerEyes:  return "SIZE"
        case .googlyEyes: return "SPEED"
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
        case .lazerEyes:
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

    func effect(intensity: Double = 0.5, secondValue: Double = 0.5) -> FaceEffect {
        let clamped = max(0, min(1, intensity))
        let clampedSecond = max(0, min(1, secondValue))
        switch self {
        case .lazerEyes:  return LazerEyesEffect(intensity: clamped, size: clampedSecond)
        case .googlyEyes: return GooglyEyesEffect(size: clamped, speed: clampedSecond)
        case .bobbleHead: return BobbleHeadEffect(intensity: clamped)
        case .handsome:   return HandsomeEffect(intensity: clamped)
        }
    }
}
