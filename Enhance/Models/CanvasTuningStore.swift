import Combine
import Foundation

/// The live, shared `CanvasTuning` — what CANVAS LAB writes and the preview and sliders read.
/// One JSON blob under one key, for the same reasons as `FaceMarkerTuningStore`: edited and reset
/// as a unit, and graduation is a single `removeObject`.
final class CanvasTuningStore: ObservableObject {

    static let shared = CanvasTuningStore()

    static let storageKey = "canvasTuning"

    @Published var tuning: CanvasTuning {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(CanvasTuning.self, from: data) {
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
