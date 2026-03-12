import Foundation

enum EffectCategory: String, CaseIterable, Identifiable {
    case zoomEffects   = "ZOOM EFFECTS"
    case visualEffects = "VISUAL EFFECTS"
    case faceFilters   = "FACE FILTERS"

    var id: String { rawValue }
}
