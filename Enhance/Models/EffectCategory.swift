import Foundation

enum EffectCategory: String, CaseIterable, Identifiable {
    case zoomEffects   = "ZOOM EFFECTS"
    case faceFilters   = "FACE FILTERS"
    case visualEffects = "VISUAL EFFECTS"
    case text          = "TEXT"

    var id: String { rawValue }
}
