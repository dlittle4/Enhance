import CoreGraphics
import Foundation

/// What a touch on the canvas landed on, in editing mode.
enum ZoomPathHit: Equatable {
    case stop(Int)
    /// The route between two stops, at fraction `f` of segment `index` — where a new stop goes.
    case segment(Int, f: CGFloat)
    case none
}

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
        let clamped = Self.clamp(point)
        if let last = stops.last, hypot(last.x - clamped.x, last.y - clamped.y) < spacing { return }
        stops.append(clamped)
    }

    // MARK: - Editing (2026-09-03)

    mutating func move(stop i: Int, to point: CGPoint) {
        guard stops.indices.contains(i) else { return }
        stops[i] = Self.clamp(point)
    }

    mutating func remove(stop i: Int) {
        guard stops.indices.contains(i) else { return }
        stops.remove(at: i)
    }

    /// Inserts a stop on the route at fraction `f` of segment `index` and returns its index.
    /// Placed on the curve, not the chord, so the route passes through where the finger was.
    @discardableResult
    mutating func insert(onSegment index: Int, f: CGFloat) -> Int {
        guard index >= 0, index + 1 < stops.count else { return max(0, stops.count - 1) }
        let point = catmullRom(segment: index, f: max(0, min(1, f)))
        stops.insert(point, at: index + 1)
        return index + 1
    }

    /// What a touch landed on. `map` takes a normalized point to the space the touch and
    /// `tolerance` are in (the canvas's content points). Stops win over the route, and the
    /// route is tested along the curve it is drawn with.
    func hitTest(_ touch: CGPoint, map: (CGPoint) -> CGPoint, tolerance: CGFloat) -> ZoomPathHit {
        func distance(_ p: CGPoint) -> CGFloat { let m = map(p); return hypot(m.x - touch.x, m.y - touch.y) }

        var nearestStop: (Int, CGFloat)? = nil
        for (i, stop) in stops.enumerated() {
            let d = distance(stop)
            if d <= tolerance, d < (nearestStop?.1 ?? .infinity) { nearestStop = (i, d) }
        }
        if let nearestStop { return .stop(nearestStop.0) }

        var nearestOnRoute: (Int, CGFloat, CGFloat)? = nil
        if stops.count > 1 {
            for i in 0..<(stops.count - 1) {
                for s in 0...Self.samplesPerSegment {
                    let f = CGFloat(s) / CGFloat(Self.samplesPerSegment)
                    let d = distance(catmullRom(segment: i, f: f))
                    if d <= tolerance, d < (nearestOnRoute?.2 ?? .infinity) { nearestOnRoute = (i, f, d) }
                }
            }
        }
        if let nearestOnRoute { return .segment(nearestOnRoute.0, f: nearestOnRoute.1) }
        return .none
    }

    static let samplesPerSegment = 24

    // MARK: - Geometry

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
                return smoothing ? catmullRom(segment: i - 1, f: f) : Self.lerp(stops[i - 1], stops[i], f)
            }
            remaining -= legShare
            // The dwell at stop i (interior).
            let dwellShare = totalDwell / max(1, interior)
            if remaining <= dwellShare { return stops[i] }
            remaining -= dwellShare
        }
        return stops.last
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ f: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(1, p.x)), y: max(0, min(1, p.y)))
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
