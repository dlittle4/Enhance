import Foundation

enum EffectCategory: String, CaseIterable, Identifiable {
    case zoomEffects   = "ZOOM EFFECTS"
    case visualEffects = "VISUAL EFFECTS"

    var id: String { rawValue }
}
