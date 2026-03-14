import Foundation

enum EffectCategory: String, CaseIterable, Identifiable {
    case zoomEffects   = "ZOOM EFFECTS"
    case faceFilters   = "FACE FILTERS"
    case visualEffects = "VISUAL EFFECTS"

    var id: String { rawValue }
}
