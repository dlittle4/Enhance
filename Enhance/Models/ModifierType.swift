import Foundation

enum ModifierType: String, CaseIterable, Identifiable, Hashable {
    case straight = "LINEAR"
    case shake = "SHAKE"
    case spiral = "SPIRAL"

    var id: String { rawValue }

    var modifier: MotionModifier {
        switch self {
        case .straight: return StraightModifier()
        case .shake: return ShakeModifier()
        case .spiral: return SpiralModifier()
        }
    }
}
