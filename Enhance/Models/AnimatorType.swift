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
    /// STEERABLE ZOOM (`FeatureFlags.pathZoom`): the camera travels a route drawn on the photo.
    /// The bare `animator` here has no route — the view model builds the real `PathAnimator`
    /// from its `zoomPath` and the lab's knobs — so this stays a plain ZOOM IN for every caller
    /// that walks `allCases` without an editor behind it.
    case path = "Path"
    
    var id: String { rawValue }

    /// The cards the ZOOM carousel shows: every case, minus PATH while its experiment is off.
    static var selectable: [AnimatorType] {
        allCases.filter { $0 != .path || FeatureFlags.pathZoom }
    }
    
    var animator: Animator {
        switch self {
        case .zoomIn: return ZoomInAnimator()
        case .zoomOut: return ZoomOutAnimator()
        case .pulse: return PulseAnimator()
        case .heartBeat: return StaticAnimator()
        case .path: return PathAnimator(path: ZoomPath())
        }
    }
}
