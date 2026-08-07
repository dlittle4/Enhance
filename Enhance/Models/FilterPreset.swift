import CoreImage

/// Photo-style colour grades, each expressed as a fully-graded target image.
///
/// Defining a preset as a *target* rather than a parameterised chain is what lets
/// the parameterless stock `CIPhotoEffect*` filters take an intensity knob:
/// `FilterPresetEffect` dissolves from the original toward `graded(_:)`, so the
/// slider works uniformly whether the grade is one stock filter or three chained.
enum FilterPreset: String, CaseIterable, Identifiable, Hashable {
    case sepia    = "SEPIA"
    case vintage  = "VINTAGE"
    case warm     = "WARM"
    case cool     = "COOL"
    case fade     = "FADE"
    case vivid    = "VIVID"
    case contrast = "CONTRAST"
    case noir     = "NOIR"
    case mono     = "MONO"

    var id: String { rawValue }

    /// Every Core Image filter name this enum depends on. `applyingFilter` fails
    /// silently on an unknown name — returning an unchanged image rather than
    /// throwing — so `requiredFilterNames_exist` asserts these all resolve.
    static let requiredFilterNames = [
        "CISepiaTone", "CIPhotoEffectTransfer", "CIPhotoEffectNoir",
        "CITemperatureAndTint", "CIColorControls", "CIToneCurve", "CIVibrance"
    ]

    /// The image at full grade. `FilterPresetEffect` handles intensity and progress.
    func graded(_ image: CIImage) -> CIImage {
        switch self {
        case .sepia:
            return image.applyingFilter("CISepiaTone", parameters: [
                kCIInputIntensityKey: 1.0
            ])

        case .vintage:
            return image.applyingFilter("CIPhotoEffectTransfer")

        case .warm:
            return image
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 8200, y: 20)
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.08
                ])

        case .cool:
            return image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 4800, y: -15)
            ])

        case .fade:
            // Lifted blacks + reduced contrast — the washed-out film look.
            return image
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0.00, y: 0.13),
                    "inputPoint1": CIVector(x: 0.25, y: 0.33),
                    "inputPoint2": CIVector(x: 0.50, y: 0.55),
                    "inputPoint3": CIVector(x: 0.75, y: 0.76),
                    "inputPoint4": CIVector(x: 1.00, y: 0.93)
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.82,
                    kCIInputContrastKey: 0.92
                ])

        case .vivid:
            // Vibrance first so already-saturated colours don't clip before the
            // global saturation boost.
            return image
                .applyingFilter("CIVibrance", parameters: [
                    "inputAmount": 0.9
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.18,
                    kCIInputContrastKey: 1.08
                ])

        case .contrast:
            return image
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0.00, y: 0.00),
                    "inputPoint1": CIVector(x: 0.25, y: 0.17),
                    "inputPoint2": CIVector(x: 0.50, y: 0.50),
                    "inputPoint3": CIVector(x: 0.75, y: 0.83),
                    "inputPoint4": CIVector(x: 1.00, y: 1.00)
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.25
                ])

        case .noir:
            return image.applyingFilter("CIPhotoEffectNoir")

        case .mono:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0
            ])
        }
    }
}
