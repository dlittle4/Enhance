import Foundation

enum AnimatorType: String, CaseIterable, Identifiable {
    case zoomIn = "Zoom In"
    case zoomOut = "Zoom Out"
    case pulse = "Pulse"
    /// SHADER LAB's PULSE, hosted on this tab (user's call, 2026-09-02). The *animator* holds
    /// the user's framing still; the beat is `VisualEffectType.pulse`, which the view model
    /// appends to the effect list while this is selected, and whose controls replace SPEED /
    /// PAUSE / MOTION in the panel — those shape a camera move, and this is not one.
    case heartBeat = "Heart Beat"
    
    var id: String { rawValue }
    
    var animator: Animator {
        switch self {
        case .zoomIn: return ZoomInAnimator()
        case .zoomOut: return ZoomOutAnimator()
        case .pulse: return PulseAnimator()
        case .heartBeat: return StaticAnimator()
        }
    }
}
