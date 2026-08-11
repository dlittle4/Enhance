import Foundation

enum FaceFilterType: String, CaseIterable, Identifiable, Hashable, ParameterizedEffect {
    static let parameterNamespace = "face"

    // Original face-specific effects
    case lazerEyes  = "LAZER EYES"
    case googlyEyes = "GOOGLY EYES"
    case squeeze    = "SQUEEZE"
    case handsome   = "HANDSOME"

    // New face-specific effects
    case heartVignette = "HEART VIGNETTE"
    case heartEyes     = "HEART EYES"
    case scramble      = "SCRAMBLE"

    // Visual effects adapted for face
    case fisheye    = "FISHEYE"
    case swirl      = "SWIRL"
    case pixelate   = "PIXELATE"
    case ripple     = "INTENSIFY"
    case fadeToBW   = "FADE TO B&W"
    case chromaShift = "CHROMA SHIFT"
    case rainbow    = "RAINBOW"
    case lensDistortion = "LENS"

    var id: String { rawValue }

    /// Effects that only make sense targeting a single face.
    var requiresSingleFace: Bool {
        self == .rainbow || self == .heartVignette || self == .scramble
    }

    /// Primary slider label.
    /// The controls this filter exposes, in display order. Single source of truth for
    /// its UI — see `VisualEffectType.parameters` for the visual-effect twin.
    var parameters: [EffectParameter] {
        var params = [EffectParameter(id: EffectParameter.intensityID, label: primaryLabel)]
        if let secondary = secondaryLabel {
            params.append(EffectParameter(id: EffectParameter.secondaryID, label: secondary))
        }
        if self == .lazerEyes {
            params.append(EffectParameter(id: "tint", label: "COLOUR", kind: .tintColor))
        }
        if self == .scramble {
            params.append(EffectParameter(id: "layout", label: "LAYOUT", kind: .preset))
        }
        return params
    }

    private var primaryLabel: String {
        switch self {
        case .googlyEyes: return "SIZE"
        case .heartEyes:  return "SIZE"
        case .scramble:   return "SIZE"
        case .handsome:   return "HANDSOMENESS"
        case .ripple:     return "REDNESS"
        default:          return "INTENSITY"
        }
    }

    /// nil means this filter has no second slider — which is also what makes
    /// `supportsSecondSlider` derivable rather than a separately maintained list.
    private var secondaryLabel: String? {
        switch self {
        case .lazerEyes:      return "SIZE"
        case .googlyEyes:     return "SPEED"
        case .fisheye:        return "SIZE"
        case .heartVignette:  return "SIZE"
        case .heartEyes:      return "SPEED"
        case .rainbow:        return "SPEED"
        case .lensDistortion: return "REACH"
        default:              return nil
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

    func effect(intensity: Double = 0.5, secondValue: Double = 0.5, laserColor: LaserColor = .red, scrambleLayout: ScrambleLayout = .thirdEye) -> FaceEffect {
        let clamped = max(0, min(1, intensity))
        let clampedSecond = max(0, min(1, secondValue))
        switch self {
        case .lazerEyes:  return LazerEyesEffect(intensity: clamped, size: clampedSecond, laserColor: laserColor)
        case .googlyEyes: return GooglyEyesEffect(size: clamped, speed: clampedSecond)
        case .squeeze:    return SqueezeEffect(intensity: clamped)
        case .handsome:   return HandsomeEffect(intensity: clamped)

        case .heartVignette: return HeartVignetteEffect(intensity: clamped, size: clampedSecond)
        case .heartEyes:     return HeartEyesEffect(intensity: clamped, speed: clampedSecond)
        // SIZE is the only slider (the primary slot); INTENSITY is dropped because the
        // effect only reads well at full strength, so it always renders opaque.
        case .scramble:      return FeatureScramblerEffect(size: clamped, intensity: 1.0, layout: scrambleLayout)

        case .fisheye:    return FaceVisualEffect(effect: FisheyeEffect(intensity: clamped, size: clampedSecond), skipDelay: true)
        case .swirl:      return FaceVisualEffect(effect: SwirlEffect(intensity: clamped), skipDelay: true)
        case .pixelate:   return FaceVisualEffect(effect: PixelateEffect(intensity: clamped), skipDelay: true, passRawProgress: true)
        case .ripple:     return FaceVisualEffect(effect: RippleEffect(intensity: clamped), skipDelay: true)
        case .fadeToBW:   return FaceVisualEffect(effect: FadeToBWEffect(intensity: clamped), skipDelay: true)
        case .chromaShift: return FaceVisualEffect(effect: ChromaticAberrationEffect(intensity: clamped), skipDelay: true)
        case .rainbow:    return RainbowFaceEffect(intensity: clamped, pulses: clampedSecond)
        case .lensDistortion: return FaceVisualEffect(effect: LensDistortionEffect(intensity: clamped, reach: clampedSecond), skipDelay: true)
        }
    }
}
