import Combine
import Foundation

/// The live, shared `GradientTuning` — what GRADIENT LAB writes and every gradient view reads.
///
/// Deliberately *not* `@AppStorage`, for two reasons. The value is a struct, which that wrapper
/// cannot hold; and dragging a colour well has to repaint every button on screen mid-gesture,
/// which an `ObservableObject` gives directly. The feature *flags* stay on `@AppStorage` because
/// they are booleans and because `FeatureFlags` documents that convention.
///
/// Persisted as one JSON blob under one key rather than sixteen keys. The tuning is edited and
/// reset as a unit, and when the experiment graduates the cleanup is a single `removeObject`.
final class GradientTuningStore: ObservableObject {

    static let shared = GradientTuningStore()

    static let storageKey = "gradientTuning"
    static let presetsKey = "gradientPresets"

    @Published var tuning: GradientTuning {
        didSet { persist() }
    }

    /// Saved looks, newest last. Unbounded on purpose — the cost of one is a few hundred bytes of
    /// JSON, and a cap would mean deciding for the user which of their looks to throw away.
    ///
    /// Only the user's own are stored; `presets` prepends the built-in.
    @Published private(set) var savedPresets: [GradientPreset] {
        didSet { persistPresets() }
    }

    /// What the strip shows: ORIGINAL first, then everything saved.
    var presets: [GradientPreset] { [.original] + savedPresets }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can round-trip against a scratch suite instead of the
    /// app's own, which would leak a tuned palette into the next launch of the simulator.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(GradientTuning.self, from: data) {
            self.tuning = decoded
        } else {
            self.tuning = .default
        }

        if let data = defaults.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([GradientPreset].self, from: data) {
            self.savedPresets = decoded
        } else {
            self.savedPresets = []
        }
    }

    // MARK: - Presets

    /// Snapshots the live tuning together with the effect state it was being viewed under.
    /// Returns the new preset so the caller can scroll it into view.
    @discardableResult
    func saveCurrentAsPreset(staticOn: Bool, ditherOn: Bool) -> GradientPreset {
        let preset = GradientPreset(id: UUID(), tuning: tuning, staticOn: staticOn, ditherOn: ditherOn)
        savedPresets.append(preset)
        return preset
    }

    func load(_ preset: GradientPreset) {
        tuning = preset.tuning
    }

    /// Built-ins ignore this — ORIGINAL is the way back, and losing it to a stray long-press
    /// would take the escape hatch with it.
    func delete(_ preset: GradientPreset) {
        guard !preset.isBuiltIn else { return }
        savedPresets.removeAll { $0.id == preset.id }
    }

    // MARK: - Reset

    /// Clears the live tuning only. Presets deliberately survive: they are the reason to feel
    /// safe pressing this, not more collateral from it.
    func reset() {
        tuning = .default
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tuning) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(savedPresets) else { return }
        defaults.set(data, forKey: Self.presetsKey)
    }
}

/// One saved look.
///
/// The whole `GradientTuning` rather than a diff against `.default`, so a preset saved today
/// still means the same thing after the defaults move — which they will, since shipping an
/// experiment *is* moving them.
///
/// It carries the two effect toggles as well as the colours, because a look is not fully
/// described without them: the same palette with the quantizer off is the plain mesh, which is a
/// different thing entirely. That is also what lets `.original` exist as a preset at all.
struct GradientPreset: Codable, Equatable, Identifiable {
    let id: UUID
    let tuning: GradientTuning
    var staticOn: Bool
    var ditherOn: Bool

    /// Built-ins cannot be deleted and always sort first.
    var isBuiltIn: Bool = false
    var title: String?

    /// The app's look before any of this existed: stock palette, quantizer off.
    ///
    /// Pinned as the first slot so there is always one tap back to the known-good state. RESET
    /// does the same thing to the live tuning, but only this carries the *flags* with it — and
    /// with the quantizer left on, a reset palette is still not the original button.
    static let original = GradientPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        tuning: .default,
        staticOn: false,
        ditherOn: false,
        isBuiltIn: true,
        title: "ORIGINAL"
    )
}

/// Tolerant decoding, for the same reason `GradientTuning` has it: presets saved before this
/// type carried the effect toggles must still load rather than vanishing.
extension GradientPreset {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            tuning: try container.decode(GradientTuning.self, forKey: .tuning),
            // A preset from before this field existed was necessarily saved while the quantizer
            // was on — the lab had no other mode — so that is the honest default.
            staticOn: ((try? container.decodeIfPresent(Bool.self, forKey: .staticOn)) ?? nil) ?? true,
            ditherOn: ((try? container.decodeIfPresent(Bool.self, forKey: .ditherOn)) ?? nil) ?? false,
            isBuiltIn: ((try? container.decodeIfPresent(Bool.self, forKey: .isBuiltIn)) ?? nil) ?? false,
            title: (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        )
    }
}
