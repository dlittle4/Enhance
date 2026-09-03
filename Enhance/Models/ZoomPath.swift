import CoreGraphics
import Foundation

/// The stops a PATH zoom travels through, in the photo's **normalized, top-left-origin** space —
/// the same space as `EditorViewModel.visibleRect`, so a stop and the pinched framing can be
/// compared without a flip. `LaserAim` is the bottom-left counterpart; the two differ because
/// each matches the space of the thing that consumes it (Core Image there, the canvas here).
struct ZoomPath: Equatable {
    var stops: [CGPoint] = []

    var isEmpty: Bool { stops.isEmpty }

    /// Appends a stop, dropping any that is closer than `spacing` (in the same normalized
    /// units) to the last — a drag samples at touch rate and would otherwise stack dozens of
    /// near-identical stops that dwell and ease individually.
    mutating func append(_ point: CGPoint, minimumSpacing spacing: CGFloat) {
        let clamped = CGPoint(x: max(0, min(1, point.x)), y: max(0, min(1, point.y)))
        if let last = stops.last, hypot(last.x - clamped.x, last.y - clamped.y) < spacing { return }
        stops.append(clamped)
    }

    /// Cumulative arc length at each stop, normalized 0…1 over the whole path, so progress can
    /// be spent per unit of distance rather than per stop — a long leg and a short leg then move
    /// at one speed. A single stop (or none) has no length.
    var normalizedArcLengths: [CGFloat] {
        guard stops.count > 1 else { return stops.map { _ in 0 } }
        var lengths: [CGFloat] = [0]
        for i in 1..<stops.count {
            let a = stops[i - 1], b = stops[i]
            lengths.append(lengths[i - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        let total = lengths.last ?? 0
        guard total > 0 else { return stops.map { _ in 0 } }
        return lengths.map { $0 / total }
    }

    /// The point `t` (0…1) of the way along the path by arc length, with an optional dwell at
    /// every interior stop and Catmull-Rom smoothing through them.
    ///
    /// - Parameter dwell: fraction of the whole duration spent parked at *each* interior stop.
    ///   The moving legs share what is left, so 3 stops at dwell 0.1 travel for 90% of the time
    ///   and pause for 10% in the middle.
    func point(at t: CGFloat, dwell: CGFloat, smoothing: Bool) -> CGPoint? {
        guard let first = stops.first else { return nil }
        guard stops.count > 1 else { return first }

        // Remove the dwells from the timeline: `u` is progress along the *moving* legs.
        let interior = CGFloat(stops.count - 2)
        let totalDwell = min(0.9, max(0, dwell) * max(0, interior))
        let moving = 1 - totalDwell
        let arcs = normalizedArcLengths

        // Walk the legs, subtracting each leg's share of time and each dwell in turn.
        var remaining = max(0, min(1, t))
        for i in 1..<stops.count {
            let legShare = (arcs[i] - arcs[i - 1]) * moving
            if remaining <= legShare || i == stops.count - 1 {
                let f = legShare > 0 ? max(0, min(1, remaining / legShare)) : 1
                return smoothing ? catmullRom(segment: i - 1, f: f) : lerp(stops[i - 1], stops[i], f)
            }
            remaining -= legShare
            // The dwell at stop i (interior).
            let dwellShare = totalDwell / max(1, interior)
            if remaining <= dwellShare { return stops[i] }
            remaining -= dwellShare
        }
        return stops.last
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ f: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// Centripetal-ish Catmull-Rom through the stops, clamped at the ends. Keeps the curve
    /// *through* every stop (so a tap lands exactly where it was tapped) while rounding the
    /// corners between legs, which is what stops a hand-drawn path reading as a polyline.
    private func catmullRom(segment: Int, f: CGFloat) -> CGPoint {
        let p1 = stops[segment], p2 = stops[segment + 1]
        let p0 = segment > 0 ? stops[segment - 1] : p1
        let p3 = segment + 2 < stops.count ? stops[segment + 2] : p2
        let t = f, t2 = t * t, t3 = t2 * t
        func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
    }
}
