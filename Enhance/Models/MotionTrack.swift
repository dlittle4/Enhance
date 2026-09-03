import CoreGraphics
import Foundation

/// Per-frame velocities for a burst, derived from what moved between frames — the numbers the
/// motion effects read (FEATURE-MOTION-EFFECTS.md §1c–1d). Pure so the matching, smoothing and
/// gap handling are testable without Vision.
///
/// Units are **normalized frame units per frame**: a velocity of (0.1, 0) means the thing moved
/// a tenth of the frame's width to the right since the previous frame. Resolution-free, so the
/// same number serves the 650px preview and the 600px GIF.
enum MotionTrack {

    /// Smoothing weight for the exponential moving average: the share of the *new* sample.
    /// 1 is raw; 0.5 halves a one-frame wobble; lower lags a real change of direction.
    static let defaultSmoothing: Double = 0.5

    /// Frames a track survives without a detection before its velocity zeroes — a face that
    /// turns away drops out of Vision for a frame or two, and the EMA should carry it through.
    static let maximumGap = 3

    /// The subject's velocity per frame, from the largest face's centre frame to frame.
    ///
    /// - Parameters:
    ///   - faceCentres: per frame, the detected faces' centres in normalized units (0…1). The
    ///     largest face is tracked; between frames it is matched by nearest centre, which is
    ///     the same rule BIG HEAD uses for its per-face masks.
    ///   - smoothing: EMA weight of the new sample.
    /// - Returns: one velocity per frame; frame 0 is the smoothed first step (zero when there
    ///   is only one frame or no face).
    static func subjectVelocities(faceCentres: [[CGPoint]], smoothing: Double = defaultSmoothing) -> [CGVector] {
        let count = faceCentres.count
        guard count > 0 else { return [] }
        var velocities = [CGVector](repeating: .zero, count: count)
        var tracked: CGPoint? = faceCentres[0].first
        var smoothed = CGVector.zero
        var gap = 0
        let alpha = CGFloat(max(0, min(1, smoothing)))

        for i in 1..<max(1, count) {
            let candidates = faceCentres[i]
            if let previous = tracked, let nearest = candidates.min(by: { distance($0, previous) < distance($1, previous) }) {
                let raw = CGVector(dx: nearest.x - previous.x, dy: nearest.y - previous.y)
                smoothed = CGVector(dx: smoothed.dx + (raw.dx - smoothed.dx) * alpha,
                                    dy: smoothed.dy + (raw.dy - smoothed.dy) * alpha)
                tracked = nearest
                gap = 0
            } else if let first = candidates.first {
                // A track starting mid-burst: no previous position, so no velocity yet.
                tracked = first
                smoothed = .zero
                gap = 0
            } else {
                gap += 1
                if gap > maximumGap { smoothed = .zero; tracked = nil }
            }
            velocities[i] = smoothed
        }
        // Frame 0 has no earlier frame; give it the first real step so an effect on frame 0
        // is not the one frame with no motion.
        if count > 1 { velocities[0] = velocities[1] }
        return velocities
    }

    /// The camera's velocity per frame, from the translation Vision measured between each
    /// consecutive pair. `translations[i]` is the shift from frame `i-1` to frame `i`, already
    /// normalized; index 0 is unused and may be zero.
    static func cameraVelocities(translations: [CGVector], smoothing: Double = defaultSmoothing) -> [CGVector] {
        let count = translations.count
        guard count > 0 else { return [] }
        let alpha = CGFloat(max(0, min(1, smoothing)))
        var out = [CGVector](repeating: .zero, count: count)
        var smoothed = CGVector.zero
        for i in 1..<max(1, count) {
            let raw = translations[i]
            smoothed = CGVector(dx: smoothed.dx + (raw.dx - smoothed.dx) * alpha,
                                dy: smoothed.dy + (raw.dy - smoothed.dy) * alpha)
            out[i] = smoothed
        }
        if count > 1 { out[0] = out[1] }
        return out
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

public extension CGVector {
    /// Length, in the same units as the components.
    var motionMagnitude: CGFloat { hypot(dx, dy) }
    /// Direction in radians, CIImage convention (y up), or 0 when there is no motion.
    var motionAngle: CGFloat { motionMagnitude > 0 ? atan2(dy, dx) : 0 }
}
