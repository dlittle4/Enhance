import Foundation

/// One user-adjustable control on an effect.
///
/// Effects *declare* their controls and the editor renders a row per declaration, so
/// adding a control is a data change rather than a layout change. This replaces the
/// old arrangement, where an effect had `intensity` plus optionally `size`, gated by a
/// `supportsSizeControl` Bool, and the view hardcoded an `HStack` of exactly two
/// sliders — which capped every effect at two controls.
struct EffectParameter: Identifiable, Hashable {

    enum Kind: Hashable {
        /// A continuous 0…1 value, shown as a dotted track with a numeric knob.
        case slider
        /// The six-swatch `LaserColor` row.
        case tintColor
        /// The three gradient stop colour wells.
        case gradientStops
    }

    /// Stable key for value storage. Must not change once shipped — values are keyed
    /// on it, and renaming one silently resets that control to its default.
    let id: String

    /// Shown at the left of the row, in the app's uppercase style.
    let label: String

    let kind: Kind

    /// Starting value for `.slider`. Ignored by picker kinds, which read their value
    /// from dedicated view-model state.
    let defaultValue: Double

    init(id: String, label: String, kind: Kind = .slider, defaultValue: Double = 0.5) {
        self.id = id
        self.label = label
        self.kind = kind
        self.defaultValue = defaultValue
    }

    // MARK: - Well-known ids

    /// The primary strength control almost every effect has. Named because
    /// `EffectOptions.intensity` is threaded through to every effect's `init`.
    static let intensityID = "intensity"

    /// The secondary spatial control — fisheye radius, dither cell size. Named for the
    /// same reason: it maps to `EffectOptions.size`.
    static let sizeID = "size"

    /// Number of dots on a slider track. The knob displays the value on this scale, so
    /// a 0…1 value of 0.5 reads as "10".
    static let sliderSteps = 20

    /// The integer shown in the knob for a 0…1 value.
    static func displayValue(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * Double(sliderSteps)).rounded())
    }
}
