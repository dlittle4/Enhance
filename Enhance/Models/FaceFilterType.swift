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
    case thirdEye      = "THIRD EYE"

    // Visual effects adapted for face
    case fisheye    = "FISHEYE"
    case swirl      = "SWIRL"
    case pixelate   = "PIXELATE"
    case ripple     = "INTENSIFY"
    case fadeToBW   = "FADE TO B&W"
    case chromaShift = "CHROMA SHIFT"
    case rainbow    = "RAINBOW"
    case lensDistortion = "LENS"
    /// ROADMAP §2a — one `CIBumpDistortion` with a head-sized radius and a positive scale.
    case bigHead        = "BIG HEAD"

    var id: String { rawValue }

    /// Effects that only make sense targeting a single face.
    var requiresSingleFace: Bool {
        self == .rainbow || self == .heartVignette || self == .thirdEye
    }

    /// The controls this filter exposes, in display order. Single source of truth for
    /// its UI — see `VisualEffectType.parameters` for the visual-effect twin.
    ///
    /// **COLOR leads when present** *(user's call, 2026-08-13)*, ahead of the sliders. It is the
    /// choice that changes the effect most, and a swatch row reads as a heading for what follows
    /// rather than a footnote to it.
    ///
    /// The `id` stays `"tint"` — it is the storage key, and `EffectParameter` warns that renaming
    /// one silently resets that control to its default. Only the label is the user's business.
    var parameters: [EffectParameter] {
        var params: [EffectParameter] = []
        if self == .lazerEyes || self == .thirdEye {
            params.append(EffectParameter(id: "tint", label: "COLOR", kind: .tintColor))
        }
        params.append(EffectParameter(id: EffectParameter.intensityID, label: primaryLabel))
        if let secondary = secondaryLabel {
            params.append(EffectParameter(id: EffectParameter.secondaryID, label: secondary))
        }
        if self == .lazerEyes {
            // Energy travelling out of the eyes. Two rows, which puts LAZER EYES at five with
            // COLOR — the panel scrolls, and that is accepted (ROADMAP §1a, 2026-08-12).
            params.append(EffectParameter(id: EffectParameter.tertiaryID, label: "PULSE"))
            params.append(EffectParameter(id: EffectParameter.quaternaryID, label: "PULSE SPEED"))
        }
        return params
    }

    private var primaryLabel: String {
        switch self {
        case .googlyEyes: return "SIZE"
        case .heartEyes:  return "SIZE"
        case .thirdEye:   return "SIZE"
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
        case .thirdEye:       return "INTENSITY"
        // Semantic V2 already owns the complete head outline, so the old REACH control (ellipse
        // coverage) cannot affect it. The second slot now nudges the enlarged head vertically;
        // its midpoint preserves the face-centred V2 result.
        case .bigHead:        return "VERTICAL POSITION"
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

    /// - Parameter laserAim: where LAZER EYES points. Only that filter reads it; `nil` keeps the
    ///   classic edge-to-edge flare, which is also what every thumbnail shows.
    /// - Parameters:
    ///   - tertiary: the third slider slot (`EffectParameter.tertiaryID`) — LAZER EYES' PULSE.
    ///   - quaternary: the fourth (`quaternaryID`) — LAZER EYES' PULSE SPEED. Both default to
    ///     the "no pulse" end here so thumbnails and every existing call see a steady beam; the
    ///     editor reads the declared row defaults instead.
    func effect(intensity: Double = 0.5, secondValue: Double = 0.5, laserColor: LaserColor = .red, laserAim: LaserAim? = nil,
                tertiary: Double = 0, quaternary: Double = 0.5) -> FaceEffect {
        let clamped = max(0, min(1, intensity))
        let clampedSecond = max(0, min(1, secondValue))
        switch self {
        case .lazerEyes:  return LazerEyesEffect(intensity: clamped, size: clampedSecond, laserColor: laserColor, aim: laserAim,
                                                 pulse: max(0, min(1, tertiary)), pulseSpeed: max(0, min(1, quaternary)))
        case .googlyEyes: return GooglyEyesEffect(size: clamped, speed: clampedSecond)
        case .squeeze:    return SqueezeEffect(intensity: clamped)
        case .handsome:   return HandsomeEffect(intensity: clamped)

        case .heartVignette: return HeartVignetteEffect(intensity: clamped, size: clampedSecond)
        case .heartEyes:     return HeartEyesEffect(intensity: clamped, speed: clampedSecond)
        // Primary slot is SIZE; secondary is INTENSITY (ray count); the picker is the eye colour.
        case .thirdEye:      return ThirdEyeEffect(size: clamped, rayIntensity: clampedSecond, eyeColor: laserColor)

        case .fisheye:    return FaceVisualEffect(effect: FisheyeEffect(intensity: clamped, size: clampedSecond), skipDelay: true)
        case .swirl:      return FaceVisualEffect(effect: SwirlEffect(intensity: clamped), skipDelay: true)
        case .pixelate:   return FaceVisualEffect(effect: PixelateEffect(intensity: clamped), skipDelay: true, passRawProgress: true)
        case .ripple:     return FaceVisualEffect(effect: RippleEffect(intensity: clamped), skipDelay: true)
        case .fadeToBW:   return FaceVisualEffect(effect: FadeToBWEffect(intensity: clamped), skipDelay: true)
        case .chromaShift: return FaceVisualEffect(effect: ChromaticAberrationEffect(intensity: clamped), skipDelay: true)
        case .rainbow:    return RainbowFaceEffect(intensity: clamped, pulses: clampedSecond)
        case .lensDistortion: return FaceVisualEffect(effect: LensDistortionEffect(intensity: clamped, reach: clampedSecond), skipDelay: true)
        // Not wrapped in `FaceVisualEffect`: that adapter masks its wrapped effect to a radius
        // around the face, which would clip the head exactly where it is meant to swell past
        // its outline. `CIBumpDistortion` already falls off to nothing on its own.
        case .bigHead:        return BigHeadEffect(intensity: clamped, size: clampedSecond)
        }
    }
}
