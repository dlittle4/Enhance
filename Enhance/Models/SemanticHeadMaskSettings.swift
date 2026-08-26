import Combine
import Foundation

/// Experimental rollout switch for the model-backed BIG HEAD mask.
///
/// It intentionally lives outside `HeadMaskTuning`: adding a required field to that Codable
/// value would invalidate every developer's saved lab settings. HEAD MASK LAB owns this switch,
/// while the editor reads it so the exact same implementation can be tried on any photo.
final class SemanticHeadMaskSettings: ObservableObject {

    enum Mode: Int, CaseIterable {
        case legacy
        case semanticV1
        case semanticV2

        var label: String {
            switch self {
            case .legacy: return "LEGACY"
            case .semanticV1: return "V1"
            case .semanticV2: return "V2"
            }
        }
    }

    static let shared = SemanticHeadMaskSettings()
    static let storageKey = "semanticHeadMaskV1Enabled"
    static let modeStorageKey = "semanticHeadMaskMode"

    @Published var mode: Mode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.modeStorageKey)
            defaults.set(mode != .legacy, forKey: Self.storageKey)
        }
    }

    var isEnabled: Bool { mode != .legacy }
    var usesV2: Bool { mode == .semanticV2 }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.modeStorageKey) != nil,
           let stored = Mode(rawValue: defaults.integer(forKey: Self.modeStorageKey)) {
            self.mode = stored
        } else {
            // Preserve existing comparison builds that had the V1 Boolean enabled.
            self.mode = defaults.bool(forKey: Self.storageKey) ? .semanticV1 : .legacy
        }
    }
}
