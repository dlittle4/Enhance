import Foundation

/// How PATH's STOP PAUSE reaches the generator.
///
/// The generator's animated length is fixed at `1s / speed`, and `PathAnimator.dwell` is a
/// *fraction* of that length parked at each interior stop — so a pause added inside a fixed
/// length would be stolen from the travel. Instead the pauses are added to the journey: the GIF
/// is asked for a slower effective speed whose length is the travel plus every pause, and the
/// dwell fraction is the pause over that whole. The user sees SPEED for the travel and STOP
/// PAUSE in seconds, the two knobs they asked for, and neither eats the other.
enum ZoomPathTiming {
    static let defaultStopPause: Double = 0.25
    /// CURVE's default: fully rounded, which is what the route always was.
    static let defaultCurve: Double = 1.0
    /// Slider top. Three interior stops at the top land on the generator's 4s ceiling.
    static let maxStopPause: Double = 1.0

    struct Resolved: Equatable {
        /// The SPEED handed to the generator; its animated length is `1 / speed`.
        let speed: Double
        /// `PathAnimator.dwell`: fraction of that length parked at each interior stop.
        let dwell: Double
    }

    static func resolve(speed: Double, stopCount: Int, stopPause: Double) -> Resolved {
        resolve(speed: speed, stopPause: stopPause, stopCount: stopCount)
    }

    static func resolve(speed: Double, stopPause: Double, stopCount: Int) -> Resolved {
        let travel = 1 / max(ZoomPlayback.minSpeed, min(ZoomPlayback.maxSpeed, speed))
        let interior = max(0, stopCount - 2)
        guard interior > 0, stopPause > 0 else { return Resolved(speed: 1 / travel, dwell: 0) }
        // The generator clamps speed to 0.25…4, i.e. length to 0.25…4s. Past that ceiling the
        // pauses shrink to fit rather than overrunning the travel.
        let wanted = travel + stopPause * Double(interior)
        let length = min(1 / ZoomPlayback.minSpeed, wanted)
        let perStop = (length - travel) / Double(interior)
        return Resolved(speed: 1 / length, dwell: max(0, perStop / length))
    }
}
