import Foundation

struct AnimationConfig {
    var animatorType: AnimatorType = .zoomIn
    var frameCount: Int = 20
    var pauseFrameCount: Int = 5
    var frameDelay: Double = 0.08
    var pauseDelay: Double = 0.2
    var outputDimension: CGFloat = 600.0
}
