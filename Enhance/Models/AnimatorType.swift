import Foundation

enum AnimatorType: String, CaseIterable, Identifiable {
    case zoomIn = "Zoom In"
    case zoomOut = "Zoom Out"
    case pulse = "Pulse"
    
    var id: String { rawValue }
    
    var animator: Animator {
        switch self {
        case .zoomIn: return ZoomInAnimator()
        case .zoomOut: return ZoomOutAnimator()
        case .pulse: return PulseAnimator()
        }
    }
}
