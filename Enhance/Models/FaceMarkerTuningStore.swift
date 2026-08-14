import Combine
import Foundation

/// The live, shared `FaceMarkerTuning` — what FACE MARKER LAB writes and the canvas reads.
///
/// Not `@AppStorage`: that wrapper cannot hold a struct, and dragging a slider has to redraw the
/// markers mid-gesture, which `@Published` gives directly. The feature *flags* stay on
/// `@AppStorage` because they are booleans and `FeatureFlags` documents that convention.
///
/// Persisted as one JSON blob under one key rather than fifteen. The tuning is edited and reset as
/// a unit, and when a variant graduates the cleanup is a single `removeObject`.
final class FaceMarkerTuningStore: ObservableObject {

    static let shared = FaceMarkerTuningStore()

    static let storageKey = "faceMarkerTuning"

    @Published var tuning: FaceMarkerTuning {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests round-trip against a scratch suite rather than the app's
    /// own — otherwise a test's tuning leaks into the next simulator launch and someone spends an
    /// afternoon wondering why their markers are 40pt wide.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(FaceMarkerTuning.self, from: data) {
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
