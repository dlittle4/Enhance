import SwiftUI

/// Draws a `ZoomPath` over the live canvas: the route, numbered stops, and a CLEAR chip.
///
/// Stops are in the photo's normalized space and the canvas shows `visibleRect` of it, so each
/// point is mapped through that rect — the route stays pinned to the photo through a pinch
/// rather than to the screen. Only the chip takes touches; the drawing must not, or it would
/// eat the strokes that extend it.
struct ZoomPathOverlay: View {
    let path: ZoomPath
    let visibleRect: CGRect
    let canvasSize: CGFloat
    let smoothing: Bool
    let onClear: () -> Void

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
                    if smoothing {
                        // Sample the same curve the animator travels, so what is drawn is
                        // what the GIF does.
                        let samples = stride(from: 0.0, through: 1.0, by: 1.0 / 96).map {
                            canvasPoint(path.point(at: CGFloat($0), dwell: 0, smoothing: true) ?? .zero)
                        }
                        route.move(to: samples[0])
                        for s in samples.dropFirst() { route.addLine(to: s) }
                    } else {
                        route.move(to: points[0])
                        for p in points.dropFirst() { route.addLine(to: p) }
                    }
                    context.stroke(route, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    context.stroke(route, with: .color(Color.enhanceMint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                }
                for (index, p) in points.enumerated() {
                    let isEnd = index == 0 || index == points.count - 1
                    let r: CGFloat = isEnd ? 7 : 3.5
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(isEnd ? Color.enhanceMint : .white))
                    context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            if !path.isEmpty {
                Button {
                    HapticService.selection()
                    onClear()
                } label: {
                    Text("CLEAR PATH")
                        .font(.silkscreenSmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(AppConstants.Spacing.small)
            }
        }
        .frame(width: canvasSize, height: canvasSize)
    }
}
