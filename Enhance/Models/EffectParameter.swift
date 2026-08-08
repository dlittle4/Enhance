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

    /// A face filter's second control slot.
    ///
    /// Deliberately not `sizeID`. A visual effect's second slot maps verbatim to
    /// `EffectOptions.size`, so naming it "size" is honest there. A face filter's second
    /// slot is SPEED for googly/heart/rainbow and SIZE for lazer/fisheye/heartVignette —
    /// all routed through the positional `secondValue:` argument. Naming the id after the
    /// *slot* rather than one of its meanings keeps the lookup a single well-known key
    /// and avoids a lie in the storage key.
    static let secondaryID = "secondary"

    /// Number of dots on a slider track. The knob displays the value on this scale, so
    /// a 0…1 value of 0.5 reads as "10".
    static let sliderSteps = 20

    /// The integer shown in the knob for a 0…1 value.
    static func displayValue(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * Double(sliderSteps)).rounded())
    }

    // MARK: - Value storage keys

    /// Key under which a parameter's value is stored on the view model.
    static func key<E: ParameterizedEffect>(_ paramID: String, for effect: E) -> String {
        "\(E.parameterNamespace)|\(effect.parameterKeyComponent)|\(paramID)"
    }

    /// Key used when no effect is selected, so the legacy value shims always have
    /// somewhere stable to read and write rather than silently dropping the value.
    static func unselectedKey(_ paramID: String, namespace: String) -> String {
        "\(namespace)|·none·|\(paramID)"
    }
}

/// An effect whose controls are declared rather than hardcoded, and whose values are
/// stored per parameter.
///
/// `parameterNamespace` is **not** cosmetic. `VisualEffectType.fisheye` and
/// `FaceFilterType.fisheye` share `rawValue == "FISHEYE"` and both declare a second
/// control slot — without the namespace their values collide in the store and
/// cross-wire silently, with no compile error and no obvious symptom.
protocol ParameterizedEffect {
    /// Distinguishes two effect families that may share a raw value.
    static var parameterNamespace: String { get }

    /// Identifies this effect within its namespace.
    var parameterKeyComponent: String { get }

    /// The controls this effect exposes, in display order.
    ///
    /// **View layer only.** This builds an array of structs on every call, so it must
    /// never be touched from `activeVisualEffectList` or `activeFaceEffect`, which are
    /// computed properties re-evaluated on every debounced preview update. Those read
    /// the value store directly by well-known id instead.
    var parameters: [EffectParameter] { get }
}

extension ParameterizedEffect where Self: RawRepresentable, Self.RawValue == String {
    var parameterKeyComponent: String { rawValue }
}
