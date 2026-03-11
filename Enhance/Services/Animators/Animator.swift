import CoreGraphics

public protocol Animator {
    func animationParameters(for progress: CGFloat, in context: GIFGenerator.DrawingContext) -> GIFGenerator.AnimationParameters
}

/// Logarithmic scale interpolation produces perceptually uniform zoom speed.
/// Going from 1x→2x takes the same number of frames as 4x→8x.
/// Center is interpolated linearly — at low zoom the pan is barely visible,
/// which naturally couples center movement with visual zoom.
func interpolate(from start: GIFGenerator.AnimationParameters, to end: GIFGenerator.AnimationParameters, progress: CGFloat) -> GIFGenerator.AnimationParameters {
    let logStart = log(max(start.scale, 0.001))
    let logEnd = log(max(end.scale, 0.001))
    let scale = exp(logStart + progress * (logEnd - logStart))

    let centerX = start.centerX + progress * (end.centerX - start.centerX)
    let centerY = start.centerY + progress * (end.centerY - start.centerY)
    return GIFGenerator.AnimationParameters(scale: scale, centerX: centerX, centerY: centerY)
}

/// Cubic ease-in-out: smooth acceleration then deceleration.
func easeInOut(_ t: CGFloat) -> CGFloat {
    t < 0.5
        ? 4 * t * t * t
        : 1 - pow(-2 * t + 2, 3) / 2
}
