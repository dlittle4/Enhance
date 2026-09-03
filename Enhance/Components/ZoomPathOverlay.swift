import SwiftUI

/// Draws a `ZoomPath` over the live canvas: the route, its stops, and one chip — DONE while
/// the route is being drawn, EDIT PATH once it is finished. Tweaking a route is undo and redo
/// (one entry per stroke), not buttons *(user's call, 2026-09-03)*.
///
/// Stops are in the photo's normalized space and the canvas shows `visibleRect` of it, so each
/// point is mapped through that rect — the route stays pinned to the photo through a pinch
/// rather than to the screen. Only the chip takes touches; the drawing must not, or it would
/// eat the strokes that extend it.
struct ZoomPathOverlay: View {
    let path: ZoomPath
    let visibleRect: CGRect
    let canvasSize: CGFloat
    /// The CURVE amount the route is drawn with — the same one the animator travels.
    let curve: CGFloat
    /// Drawing mode: strokes extend the route and the chip reads DONE.
    let isEditing: Bool
    /// The stop a tap picked out, ringed, with DELETE STOP offered.
    let selectedStop: Int?
    let onDone: () -> Void
    let onEdit: () -> Void
    let onDeleteStop: () -> Void

    private func canvasPoint(_ p: CGPoint) -> CGPoint {
        guard visibleRect.width > 0, visibleRect.height > 0 else { return .zero }
        return CGPoint(
            x: (p.x - visibleRect.origin.x) / visibleRect.width * canvasSize,
            y: (p.y - visibleRect.origin.y) / visibleRect.height * canvasSize
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, _ in
                let points = path.stops.map(canvasPoint)
                if points.count > 1 {
                    var route = Path()
                    // Sample the same curve the animator travels, so what is drawn is what
                    // the GIF does.
                    let samples = stride(from: 0.0, through: 1.0, by: 1.0 / 96).map {
                        canvasPoint(path.point(at: CGFloat($0), dwell: 0, curve: curve) ?? .zero)
                    }
                    route.move(to: samples[0])
                    for s in samples.dropFirst() { route.addLine(to: s) }
                    // Finished routes sit back so the photo reads as the thing being framed.
                    let alpha: CGFloat = isEditing ? 1 : 0.55
                    context.stroke(route, with: .color(.black.opacity(0.45 * alpha)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    context.stroke(route, with: .color(Color.enhanceMint.opacity(alpha)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                }
                for (index, p) in points.enumerated() {
                    let isEnd = index == 0 || index == points.count - 1
                    // Every stop is a target while editing, so the interior ones grow to be
                    // seen and hit; at rest they shrink back to route markers.
                    let r: CGFloat = isEnd ? 7 : (isEditing ? 5.5 : 3.5)
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(isEnd ? Color.enhanceMint : .white))
                    context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1)
                    if index == selectedStop {
                        let ring = Path(ellipseIn: CGRect(x: p.x - r - 5, y: p.y - r - 5, width: (r + 5) * 2, height: (r + 5) * 2))
                        context.stroke(ring, with: .color(Color.enhanceMint), lineWidth: 2)
                    }
                }
            }
            .allowsHitTesting(false)

            if isEditing {
                chip("DONE", tint: Color.enhanceMint) { onDone() }
            } else {
                chip("EDIT PATH", tint: .white) { onEdit() }
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditing, selectedStop != nil {
                chip("DELETE STOP", tint: Color.overdrive) { onDeleteStop() }
            }
        }
        .frame(width: canvasSize, height: canvasSize)
    }

    private func chip(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.selection()
            action()
        } label: {
            Text(title)
                .font(.silkscreenSmall)
                .foregroundColor(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .padding(AppConstants.Spacing.small)
    }
}
