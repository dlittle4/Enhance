import Foundation

/// The span of an effect's 0…1 slider that the editor actually exposes, plus where the knob
/// starts.
///
/// Every slider in the editor is the same 20-dot 0…1 track, and each effect's `init` turns that
/// number into real units on its own terms (HALFTONE reads intensity as `24 × value` px). Some
/// of those spans have dead ends — a bottom third that renders as nothing, a top that is past
/// anything anyone would ship. A window trims the span without touching the effect: the
/// editor's knob position `u` becomes `min + u · (max − min)` at the view model's choke points,
/// and the effect's own mapping runs unchanged from there.
///
/// Deliberately **inside** today's 0…1 — a window can narrow a range but cannot reach past what
/// the effect's `init` already allows. Widening is a one-line edit in that effect, done by hand.
///
/// All three values are in slider space. `defaultValue` is absolute (not a fraction of the
/// window), so that reading a window tells you the value the knob opens at without doing
/// arithmetic; `initialSliderValue` does the arithmetic for the track.
struct ParameterWindow: Codable, Equatable {
    var min: Double = 0
    var max: Double = 1
    var defaultValue: Double = 0.5

    /// Today's behaviour: the whole span, knob in the middle.
    static let identity = ParameterWindow()

    /// One lattice step on the editor's track — the narrowest window that still has two
    /// distinguishable positions.
    static let minimumSpan = 1.0 / Double(EffectParameter.sliderSteps)

    init(min: Double = 0, max: Double = 1, defaultValue: Double = 0.5) {
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
    }

    var isIdentity: Bool { self == .identity }

    /// The invariants every stored window satisfies: `0 ≤ min ≤ max − minimumSpan ≤ 1` and
    /// `min ≤ defaultValue ≤ max`. Applied on every store write, so a MIN dragged over MAX
    /// pushes MAX rather than inverting the window, and DEFAULT follows the end that moved.
    func normalized() -> ParameterWindow {
        var lo = Self.clamp01(min)
        var hi = Self.clamp01(max)
        if hi < lo + Self.minimumSpan {
            // Prefer moving the *other* end: whichever end the caller just set should stick.
            if lo + Self.minimumSpan <= 1 {
                hi = lo + Self.minimumSpan
            } else {
                hi = 1
                lo = 1 - Self.minimumSpan
            }
        }
        let def = Swift.max(lo, Swift.min(hi, Self.clamp01(defaultValue)))
        return ParameterWindow(min: lo, max: hi, defaultValue: def)
    }

    /// The editor's knob position, mapped into the window.
    func remap(_ u: Double) -> Double {
        min + Self.clamp01(u) * (max - min)
    }

    /// Where on the 0…1 track a window-space value sits; the inverse of `remap`.
    func sliderPosition(for value: Double) -> Double {
        let span = max - min
        guard span > 0 else { return 0 }
        return Self.clamp01((value - min) / span)
    }

    /// Where the knob opens so that the effect starts at `defaultValue`.
    var initialSliderValue: Double { sliderPosition(for: defaultValue) }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.max(0, Swift.min(1, value))
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case min, max, defaultValue }

    /// Tolerant of a blob written by an older or newer build: a missing or malformed field reads
    /// as its default rather than discarding the whole window (MotionTuning's rule).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ParameterWindow.identity
        min = ((try? container.decodeIfPresent(Double.self, forKey: .min)) ?? nil) ?? fallback.min
        max = ((try? container.decodeIfPresent(Double.self, forKey: .max)) ?? nil) ?? fallback.max
        defaultValue = ((try? container.decodeIfPresent(Double.self, forKey: .defaultValue)) ?? nil)
            ?? fallback.defaultValue
        self = normalized()
    }
}

/// The values an effect's picker-card thumbnail is rendered at.
///
/// `values` are keyed by parameter id (`intensity`, `size`, …) and are **slider-space** `u`s —
/// they pass through the same `ParameterWindow` the editor applies, so "thumbnail intensity 0.7"
/// produces exactly what a user's knob at 0.7 does. Missing ids fall back to the values the
/// thumbnails have always used (see `EffectLabLookup.thumbnailValues`). `progress` overrides the
/// effect's `previewProgress`; nil keeps it.
struct ThumbnailPreset: Codable, Equatable {
    var values: [String: Double] = [:]
    var progress: Double? = nil

    init(values: [String: Double] = [:], progress: Double? = nil) {
        self.values = values
        self.progress = progress
    }

    var isDefault: Bool { values.isEmpty && progress == nil }

    private enum CodingKeys: String, CodingKey { case values, progress }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = ((try? container.decodeIfPresent([String: Double].self, forKey: .values)) ?? nil) ?? [:]
        progress = ((try? container.decodeIfPresent(Double.self, forKey: .progress)) ?? nil)
    }
}

/// The graduated tables — what EFFECTS LAB's COPY SWIFT hands back once a set of windows and
/// thumbnail presets has been dialled in. Empty until then.
///
/// Keys are `EffectParameter.key(paramID, for:)` for windows (`"visual|HALFTONE|intensity"`) and
/// `EffectParameter.effectKey(for:)` for presets (`"visual|HALFTONE"`). `EffectLabStore`
/// overlays its live state on top of these, so pasting a snippet here and resetting the lab
/// leaves the app rendering exactly what the lab showed.
enum EffectTuningTables {
    /// Graduated from EFFECTS LAB on 2026-09-02 — the user's dial-in on device.
    static let windows: [String: ParameterWindow] = [
        "face|BIG HEAD|secondary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.45),
        "face|FISHEYE|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.30),
        "visual|BITMAP|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.20),
        "visual|BITMAP|size": ParameterWindow(min: 0.00, max: 0.60, defaultValue: 0.18),
        "visual|BITMAP|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.55),
        "visual|CHROMA SHIFT|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|CHROMA SHIFT|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.30),
        "visual|DITHER|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.20),
        "visual|DITHER|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|DITHER|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|ECHO|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.80),
        "visual|ECHO|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.45),
        "visual|ECHO|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.65),
        "visual|FISHEYE|intensity": ParameterWindow(min: 0.00, max: 0.70, defaultValue: 0.60),
        "visual|FISHEYE|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.00),
        "visual|HALFTONE|intensity": ParameterWindow(min: 0.10, max: 0.75, defaultValue: 0.10),
        "visual|HALFTONE|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|HALFTONE|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.80),
        "visual|LENS|intensity": ParameterWindow(min: 0.00, max: 0.65, defaultValue: 0.35),
        "visual|RAINBOW|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.45),
        "visual|RAINBOW|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|SLICE SHIFT|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|STRETCH|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.35),
        "visual|SWIRL|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.25),
        // The shader pack: SHADER LAB's tuned values, as the knobs' opening positions.
        "visual|THERMAL|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.60),
        "visual|THERMAL|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.70),
        "visual|THERMAL|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.75),
        "visual|THERMAL|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.65),
        "visual|CHROMATIC SPLIT|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|CHROMATIC SPLIT|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.95),
        "visual|CHROMATIC SPLIT|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.40),
        "visual|DATAMOSH|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.80),
        "visual|DATAMOSH|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.90),
        "visual|DATAMOSH|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|DATAMOSH|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|HEAT SHIMMER|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.35),
        "visual|HEAT SHIMMER|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.35),
        "visual|HEAT SHIMMER|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.25),
        "visual|HEAT SHIMMER|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.00),
        "visual|LIVE RIPPLE|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.95),
        "visual|LIVE RIPPLE|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.45),
        "visual|LIVE RIPPLE|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.35),
        "visual|LIVE RIPPLE|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|MELT|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|MELT|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.75),
        "visual|MELT|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.90),
        "visual|MELT|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|NEON EDGE|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|NEON EDGE|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.15),
        "visual|NEON EDGE|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.10),
        "visual|NEON EDGE|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|NEON EDGE|quinary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.55),
        "visual|PIXEL STORM|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.05),
        "visual|PIXEL STORM|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.85),
        "visual|PIXEL STORM|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.90),
        "visual|PIXEL STORM|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.95),
        "visual|SHOCKWAVE|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.47),
        "visual|SHOCKWAVE|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.33),
        "visual|SHOCKWAVE|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.45),
        "visual|SHOCKWAVE|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.33),
        "visual|SOLARIZE|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "visual|SOLARIZE|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.35),
        "visual|SOLARIZE|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.80),
        "visual|SOLARIZE|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.15),
        "visual|SOLARIZE|quinary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.25),
        "visual|WAVE POOL|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.48),
        "visual|WAVE POOL|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.49),
        "visual|HEART BEAT|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.30),
        "visual|HEART BEAT|size": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.90),
        "visual|HEART BEAT|tertiary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.00),
        "visual|HEART BEAT|quaternary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.20),
        // The FACE variants open where their IMAGE twins do.
        "face|THERMAL|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.60),
        "face|THERMAL|secondary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.70),
        "face|MELT|intensity": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 1.00),
        "face|MELT|secondary": ParameterWindow(min: 0.00, max: 1.00, defaultValue: 0.75),
    ]

    static let thumbnailPresets: [String: ThumbnailPreset] = [
        "face|BIG HEAD": ThumbnailPreset(values: ["intensity": 0.70, "secondary": 0.40], progress: 1.00),
        "face|FISHEYE": ThumbnailPreset(values: ["intensity": 0.45, "secondary": 0.45], progress: nil),
        "face|INTENSIFY": ThumbnailPreset(values: ["intensity": 1.00], progress: 0.90),
        "face|PIXELATE": ThumbnailPreset(values: ["intensity": 0.55], progress: nil),
        "visual|BITMAP": ThumbnailPreset(values: ["intensity": 1.00, "size": 0.05, "tertiary": 0.75], progress: 1.00),
        "visual|CHROMA SHIFT": ThumbnailPreset(values: ["intensity": 0.25, "size": 0.60], progress: 0.95),
        "visual|DITHER": ThumbnailPreset(values: ["intensity": 0.70, "size": 0.05, "tertiary": 0.95], progress: 1.00),
        "visual|EDGES": ThumbnailPreset(values: ["intensity": 0.75], progress: 0.50),
        "visual|GRADIENT": ThumbnailPreset(values: ["intensity": 1.00, "size": 0.40], progress: nil),
        "visual|HALFTONE": ThumbnailPreset(values: ["intensity": 0.35, "size": 0.40, "tertiary": 0.45], progress: 1.00),
        "visual|HEAT HAZE": ThumbnailPreset(values: ["intensity": 1.00, "size": 1.00, "tertiary": 0.60], progress: 1.00),
        "visual|LENS": ThumbnailPreset(values: ["intensity": 0.35, "size": 0.55], progress: 1.00),
        "visual|MOTION BLUR": ThumbnailPreset(values: ["intensity": 0.35, "size": 0.35], progress: 0.70),
        "visual|PIXELATE": ThumbnailPreset(values: ["intensity": 0.55], progress: 0.30),
        "visual|RAINBOW": ThumbnailPreset(values: ["intensity": 0.60], progress: 0.95),
        "visual|SLICE SHIFT": ThumbnailPreset(values: ["intensity": 0.65, "size": 0.30, "tertiary": 0.65], progress: 0.80),
        "visual|SWIRL": ThumbnailPreset(values: ["intensity": 0.35, "size": 0.35], progress: 1.00),
        // The shader pack's cards render at the tuned values, not the generic 0.7 / 0.5.
        "visual|THERMAL": ThumbnailPreset(values: ["intensity": 0.60, "quaternary": 0.65, "size": 0.70, "tertiary": 0.75], progress: nil),
        "visual|CHROMATIC SPLIT": ThumbnailPreset(values: ["intensity": 0.50, "quaternary": 0.40, "size": 0.05, "tertiary": 0.95], progress: nil),
        "visual|DATAMOSH": ThumbnailPreset(values: ["intensity": 0.80, "quaternary": 1.00, "size": 0.90, "tertiary": 1.00], progress: nil),
        "visual|HEAT SHIMMER": ThumbnailPreset(values: ["intensity": 0.35, "quaternary": 0.00, "size": 0.35, "tertiary": 0.25], progress: nil),
        "visual|LIVE RIPPLE": ThumbnailPreset(values: ["intensity": 0.95, "quaternary": 1.00, "size": 0.45, "tertiary": 0.35], progress: nil),
        "visual|MELT": ThumbnailPreset(values: ["intensity": 1.00, "quaternary": 1.00, "size": 0.75, "tertiary": 0.90], progress: nil),
        "visual|NEON EDGE": ThumbnailPreset(values: ["intensity": 1.00, "quaternary": 0.05, "quinary": 0.55, "size": 0.15, "tertiary": 0.10], progress: nil),
        "visual|PIXEL STORM": ThumbnailPreset(values: ["intensity": 0.05, "quaternary": 0.95, "size": 0.85, "tertiary": 0.90], progress: nil),
        "visual|SHOCKWAVE": ThumbnailPreset(values: ["intensity": 0.47, "quaternary": 0.33, "size": 0.33, "tertiary": 0.45], progress: nil),
        "visual|SOLARIZE": ThumbnailPreset(values: ["intensity": 1.00, "quaternary": 0.15, "quinary": 0.25, "size": 0.35, "tertiary": 0.80], progress: nil),
        "visual|WAVE POOL": ThumbnailPreset(values: ["intensity": 0.48, "quaternary": 0.50, "size": 0.49, "tertiary": 0.50], progress: nil),
        "visual|HEART BEAT": ThumbnailPreset(values: ["intensity": 0.30, "quaternary": 0.20, "size": 0.90, "tertiary": 0.00], progress: nil),
        "face|THERMAL": ThumbnailPreset(values: ["intensity": 0.60, "secondary": 0.70], progress: nil),
        "face|MELT": ThumbnailPreset(values: ["intensity": 1.00, "secondary": 0.75], progress: nil),
    ]
}

/// The resolved, read-only answer to "what does this editor session expose": which effects are
/// on, how each slider is windowed, and what each thumbnail renders at.
///
/// A value, not the store. `EditorViewModel` takes one at construction — the editor is built
/// fresh per photo and Settings cannot be open over it, so a snapshot is both the simplest and
/// the correct read (see `EditorViewModel.allowsGenerationWithoutZoom` for the precedent). It
/// also keeps the GIF path, which evaluates the effect list off the main thread, from touching a
/// shared `ObservableObject`.
///
/// Hot-path safe: `remap` is one key string and one dictionary lookup, with an early return when
/// nothing is windowed. Nothing here calls `.parameters`.
struct EffectLabLookup: Equatable {
    /// Non-identity windows only, keyed by full parameter key.
    var windows: [String: ParameterWindow]

    /// Non-default presets only, keyed by effect key.
    var thumbnails: [String: ThumbnailPreset]

    /// Effects the lab has explicitly switched, keyed by effect key. Anything absent falls back
    /// to the code default: on unless retired.
    var enabledOverrides: [String: Bool]

    init(windows: [String: ParameterWindow] = EffectTuningTables.windows,
         thumbnails: [String: ThumbnailPreset] = EffectTuningTables.thumbnailPresets,
         enabledOverrides: [String: Bool] = [:]) {
        self.windows = windows
        self.thumbnails = thumbnails
        self.enabledOverrides = enabledOverrides
    }

    /// The graduated tables and nothing else — what the app ships with, and what tests inject
    /// so a developer's simulator lab state cannot leak into an assertion.
    static let identity = EffectLabLookup()

    // MARK: - Windows

    func window<E: ParameterizedEffect>(_ paramID: String, for effect: E) -> ParameterWindow {
        guard !windows.isEmpty else { return .identity }
        return windows[EffectParameter.key(paramID, for: effect)] ?? .identity
    }

    /// The editor's knob position mapped through the parameter's window.
    func remap<E: ParameterizedEffect>(_ u: Double, paramID: String, for effect: E) -> Double {
        guard !windows.isEmpty else { return u }
        return window(paramID, for: effect).remap(u)
    }

    /// What the effect is built with, given what the view model has stored for the knob.
    ///
    /// `nil` means the knob has never been touched, which is the one case where the answer is
    /// the window's *default* rather than a remap — the knob opens at `initialSliderValue`, and
    /// remapping that reproduces the same number, but reading it directly avoids a round trip
    /// through the lattice. `declared` is the parameter's own `defaultValue` for the no-window
    /// case, so a toggle stored as nil still reads as off.
    func resolvedSliderValue<E: ParameterizedEffect>(stored: Double?, paramID: String, for effect: E,
                                                     declared: Double = 0.5) -> Double {
        let window = window(paramID, for: effect)
        guard let stored else {
            return window.isIdentity ? declared : window.defaultValue
        }
        return window.remap(stored)
    }

    /// Where the editor's knob opens for a parameter it has no stored value for.
    func initialSliderValue<E: ParameterizedEffect>(_ paramID: String, for effect: E,
                                                    declared: Double) -> Double {
        let window = window(paramID, for: effect)
        return window.isIdentity ? declared : window.initialSliderValue
    }

    // MARK: - Enabled

    func isEnabled(_ effect: VisualEffectType) -> Bool {
        enabledOverrides[EffectParameter.effectKey(for: effect)] ?? !effect.isRetired
    }

    func isEnabled(_ filter: FaceFilterType) -> Bool {
        enabledOverrides[EffectParameter.effectKey(for: filter)] ?? !filter.isRetired
    }

    /// The IMAGE carousel, in declaration order. Replaces `VisualEffectType.selectable` wherever
    /// the *user* is the audience; `selectable` remains the code's own answer.
    var enabledVisualEffects: [VisualEffectType] {
        VisualEffectType.allCases.filter(isEnabled)
    }

    var enabledFaceFilters: [FaceFilterType] {
        FaceFilterType.allCases.filter(isEnabled)
    }

    // MARK: - Thumbnails

    /// The values the thumbnails have always rendered at, before any preset. Intensity 0.7 so
    /// the card shows the effect clearly; everything else at the knob's midpoint.
    static let defaultThumbnailIntensity = 0.7
    static let defaultThumbnailSecondary = 0.5

    /// A thumbnail's slider-space values for each of the given parameter ids, and the progress
    /// to render at. Values are returned **un-remapped**; the renderer passes them through
    /// `remap` so the card and the editor agree.
    func thumbnailValues<E: ParameterizedEffect>(for effect: E, paramIDs: [String],
                                                 previewProgress: CGFloat) -> (values: [String: Double], progress: CGFloat) {
        let preset = thumbnails[EffectParameter.effectKey(for: effect)]
        var values: [String: Double] = [:]
        for id in paramIDs {
            values[id] = preset?.values[id]
                ?? (id == EffectParameter.intensityID ? Self.defaultThumbnailIntensity : Self.defaultThumbnailSecondary)
        }
        let progress = preset?.progress.map { CGFloat($0) } ?? previewProgress
        return (values, progress)
    }
}
