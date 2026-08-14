import Combine
import Foundation

/// The live, shared `MotionTuning` — what MOTION LAB writes and every tuned animation reads.
///
/// Deliberately *not* `@AppStorage`, for the two reasons `GradientTuningStore` records: the value
/// is a struct, which that wrapper cannot hold; and dragging a slider has to repaint the preview
/// mid-gesture, which an `ObservableObject` gives directly. The feature *flags* stay on
/// `@AppStorage` because they are booleans and because `FeatureFlags` documents that convention.
///
/// Persisted as one JSON blob under one key rather than a dozen keys. The tuning is edited and
/// reset as a unit, and when the experiment graduates the cleanup is a single `removeObject`.
final class MotionTuningStore: ObservableObject {

    static let shared = MotionTuningStore()

    static let storageKey = "motionTuning"
    static let presetsKey = "motionPresets"

    @Published var tuning: MotionTuning {
        didSet { persist() }
    }

    /// Saved looks, newest last. Unbounded on purpose — one costs a few hundred bytes of JSON, and
    /// a cap would mean deciding for the user which of their looks to throw away.
    ///
    /// Only the user's own are stored; `presets` prepends the built-ins.
    @Published private(set) var savedPresets: [MotionPreset] {
        didSet { persistPresets() }
    }

    /// What the strip shows: the two built-ins first, then everything saved.
    var presets: [MotionPreset] { [.original, .suggested] + savedPresets }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can round-trip against a scratch suite instead of the
    /// app's own, which would leak a tuned curve into the next launch of the simulator.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(MotionTuning.self, from: data) {
            self.tuning = decoded
        } else {
            self.tuning = .default
        }

        if let data = defaults.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([MotionPreset].self, from: data) {
            self.savedPresets = decoded
        } else {
            self.savedPresets = []
        }
    }

    // MARK: - Presets

    /// Snapshots the live tuning. Returns the new preset so the caller can scroll it into view.
    @discardableResult
    func saveCurrentAsPreset() -> MotionPreset {
        let preset = MotionPreset(id: UUID(), tuning: tuning)
        savedPresets.append(preset)
        return preset
    }

    func load(_ preset: MotionPreset) {
        tuning = preset.tuning
    }

    /// Built-ins ignore this — ORIGINAL is the way back, and losing it to a stray long-press would
    /// take the escape hatch with it.
    func delete(_ preset: MotionPreset) {
        guard !preset.isBuiltIn else { return }
        savedPresets.removeAll { $0.id == preset.id }
    }

    // MARK: - Reset

    /// Clears the live tuning only. Presets deliberately survive: they are the reason to feel safe
    /// pressing this, not more collateral from it.
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

/// One saved feel.
///
/// The whole `MotionTuning` rather than a diff against `.default`, so a preset saved today still
/// means the same thing after the defaults move — which they will, since shipping an experiment
/// *is* moving them.
///
/// **Unlike `GradientPreset`, this deliberately does not carry the feature flags.** A gradient
/// preset needs them because the same palette with the quantizer off is a different *look* — the
/// toggles are part of what is being judged. Motion flags shape nothing; they only gate which call
/// sites read the tuning at all. A motion preset is fully described by its numbers.
struct MotionPreset: Codable, Equatable, Identifiable {
    let id: UUID
    let tuning: MotionTuning

    /// Built-ins cannot be deleted and always sort first.
    var isBuiltIn: Bool = false
    var title: String?

    /// The app's motion before any of this existed. Pinned first so there is always one tap back
    /// to the known-good state — RESET does the same to the live tuning, but a preset is visible
    /// in the strip beside the alternatives, which is where you want the way back to be.
    static let original = MotionPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        tuning: .default,
        isBuiltIn: true,
        title: "ORIGINAL"
    )

    /// The plan's proposed starting point, so the intended effect is one tap away rather than
    /// something to dial in from zero. Explicitly a proposal, not a default — see `MotionTuning`.
    static let suggested = MotionPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        tuning: .suggested,
        isBuiltIn: true,
        title: "SUGGESTED"
    )
}

/// Tolerant decoding, for the same reason `MotionTuning` has it: a preset saved before a field
/// existed must still load rather than vanishing, and `tuning`'s own tolerant decode handles the
/// inside of it.
extension MotionPreset {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            tuning: try container.decode(MotionTuning.self, forKey: .tuning),
            isBuiltIn: ((try? container.decodeIfPresent(Bool.self, forKey: .isBuiltIn)) ?? nil) ?? false,
            title: (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        )
    }
}
