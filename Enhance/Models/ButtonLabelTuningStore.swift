import Combine
import Foundation

/// The live, shared `ButtonLabelTuning` — what BUTTON TEXT LAB writes and the MAKE A GIF button
/// reads.
///
/// Deliberately *not* `@AppStorage`, for the reasons `GradientTuningStore` records: the value is a
/// struct, which that wrapper cannot hold, and typing a phrase or dragging a slider has to repaint
/// the preview mid-edit, which an `ObservableObject` gives directly. The feature *flag* stays on
/// `@AppStorage` because it is a boolean and `FeatureFlags` documents that convention.
///
/// Persisted as one JSON blob under one key. The tuning is edited and reset as a unit, and when
/// the experiment graduates the cleanup is a single `removeObject`.
final class ButtonLabelTuningStore: ObservableObject {

    static let shared = ButtonLabelTuningStore()

    static let storageKey = "buttonLabelTuning"

    @Published var tuning: ButtonLabelTuning {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can round-trip against a scratch suite instead of the
    /// app's own, which would leak a tuned rotation into the next launch of the simulator.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ButtonLabelTuning.self, from: data) {
            self.tuning = decoded
        } else {
            self.tuning = .default
        }
    }

    func reset() {
        tuning = .default
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tuning) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
