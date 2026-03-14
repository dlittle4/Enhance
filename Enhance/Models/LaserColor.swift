import SwiftUI
import CoreImage

enum LaserColor: String, CaseIterable, Identifiable, Hashable {
    case red     = "RED"
    case yellow  = "YELLOW"
    case green   = "GREEN"
    case blue    = "BLUE"
    case purple  = "PURPLE"
    case magenta = "MAGENTA"

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .red:     return Color(red: 1.0,  green: 0.0,  blue: 0.0)
        case .yellow:  return Color(red: 1.0,  green: 0.9,  blue: 0.0)
        case .green:   return Color(red: 0.0,  green: 0.8,  blue: 0.467)
        case .blue:    return Color(red: 0.0,  green: 0.4,  blue: 1.0)
        case .purple:  return Color(red: 0.667, green: 0.2, blue: 0.867)
        case .magenta: return Color(red: 1.0,  green: 0.133, blue: 0.6)
        }
    }

    /// RGB tuple for the core laser effect pipeline.
    var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .red:     return (1.0,  0.0,  0.0)
        case .yellow:  return (1.0,  0.9,  0.0)
        case .green:   return (0.0,  0.8,  0.467)
        case .blue:    return (0.0,  0.4,  1.0)
        case .purple:  return (0.667, 0.2, 0.867)
        case .magenta: return (1.0,  0.133, 0.6)
        }
    }
}
