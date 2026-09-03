import Foundation

/// How PATH's timing reaches the generator.
///
/// The generator's animated length is fixed at `1s / speed`, and `PathAnimator` works in
/// fractions of that length — so anything added to the journey (the zoom-in before the first
/// stop, the pauses at stops) would be stolen from the travel if the length stayed put. Instead
/// the GIF is asked for a slower effective speed whose length is lead-in + travel + every
/// pause, and each part is handed back as its fraction of that whole. SPEED sets the travel
/// (and the lead-in, which is one travel's worth); the pauses are seconds and do not change
/// with SPEED *(user's call, 2026-09-03)*.
enum ZoomPathTiming {
    static let defaultStopPause: Double = 0.25
    /// Slider top *(user's call, 2026-09-03: up to 3s at each stop)*.
    static let maxStopPause: Double = 3.0
    /// CURVE's default: fully rounded, which is what the route always was.
    static let defaultCurve: Double = 1.0
    /// The longest GIF the generator will make; past it the pauses shrink to fit.
    static var maxLength: Double { 1 / GIFGenerator.minimumSpeed }

    struct Resolved: Equatable {
        /// The SPEED handed to the generator; its animated length is `1 / speed`.
        let speed: Double
        /// `PathAnimator.dwell`: fraction of that length parked at each interior stop.
        let dwell: Double
        /// `PathAnimator.leadIn`: fraction of that length spent zooming in to the first stop.
        let leadIn: Double
    }

    /// - Parameter zoomsIn: whether there is a magnification to reach — false at 1×, where a
    ///   lead-in would be a still and its time is better spent travelling.
    static func resolve(speed: Double, stopPause: Double, stopCount: Int, zoomsIn: Bool = false) -> Resolved {
        let travel = 1 / max(ZoomPlayback.minSpeed, min(ZoomPlayback.maxSpeed, speed))
        let interior = max(0, stopCount - 2)
        let lead = zoomsIn && stopCount > 0 ? travel : 0
        let pauses = interior > 0 ? max(0, stopPause) * Double(interior) : 0
        let wanted = lead + travel + pauses
        let length = min(maxLength, wanted)
        // Over the cap the pauses give way first; the lead-in and travel keep their shape.
        let pauseTotal = max(0, length - lead - travel)
        let perStop = interior > 0 ? pauseTotal / Double(interior) : 0
        return Resolved(speed: 1 / length, dwell: perStop / length, leadIn: lead / length)
    }
}
