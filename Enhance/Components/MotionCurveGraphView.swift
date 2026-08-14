import SwiftUI

/// A `MotionCurve` drawn as a curve, with the real animation running beside it.
///
/// Two things are on screen deliberately:
///
/// - **The plotted line** is `MotionCurve.displacement(atTime:)` — a damped-harmonic-oscillator
///   model, and an *approximation* of SwiftUI's spring rather than a reproduction of it.
/// - **The dot** underneath is animated by the actual `curve.animation`. It is ground truth.
///
/// Showing both is what keeps the approximation honest: if the line and the dot ever disagree
/// about when the motion settles or how far it overshoots, the dot is right and the model needs
/// revisiting. A graph on its own would be trusted silently, which is exactly the failure this
/// arrangement is designed to make visible.
struct MotionCurveGraphView: View {

    let curve: MotionCurve

    /// Drawn behind `curve` in a dimmed dashed stroke, for comparing an override against the
    /// global it departs from. The visible gap between the two lines *is* the micro-adjustment.
    var reference: MotionCurve? = nil

    /// Drawn as thin lines under everything else — the other curves in the same tuning.
    ///
    /// This is what lets a preset swatch distinguish itself. Presets that differ only in their
    /// per-animation overrides share a global curve, so a swatch plotting the global alone renders
    /// them identically and the strip stops being recognisable at a glance — which is the entire
    /// job of a preset strip. Fanned lines say "this one pulls its animations apart"; a single
    /// line says "this one moves as a whole".
    var companions: [MotionCurve] = []

    /// Suppressed in tight rows where the graph is decoration rather than the thing being judged.
    var showsGroundTruth: Bool = true

    var height: CGFloat = 96

    /// Ground-truth dot position, flipped on a repeating timer so the animation replays.
    @State private var dotAtEnd = false

    /// Vertical span the plot maps onto, in displacement units. Fixed rather than fitted to the
    /// curve so two settings can be compared: an overshoot has to visibly grow when damping drops,
    /// which it cannot do if the axis rescales to contain it every time.
    private static let low: Double = -0.25
    private static let high: Double = 1.5

    /// Enough to render a ring smoothly at this width without sampling every pixel.
    private static let samples = 160

    private let replay = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                drawSettledLine(in: &context, size: size)
                for companion in companions {
                    context.stroke(
                        path(for: companion, in: size),
                        with: .color(.enhanceMint.opacity(0.35)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                }
                if let reference {
                    context.stroke(
                        path(for: reference, in: size),
                        with: .color(.textInactive.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
                    )
                }
                context.stroke(
                    path(for: curve, in: size),
                    with: .color(.enhanceMint),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous)
                    .fill(Color.surfaceControl)
            )

            if showsGroundTruth {
                groundTruth
            }
        }
    }

    /// The line the curve is settling onto. Without it an overshoot has nothing to be an overshoot
    /// *of* — the ring reads as part of the shape rather than as travel past the target.
    private func drawSettledLine(in context: inout GraphicsContext, size: CGSize) {
        var settled = Path()
        settled.move(to: CGPoint(x: 0, y: y(for: 1, in: size)))
        settled.addLine(to: CGPoint(x: size.width, y: y(for: 1, in: size)))
        context.stroke(
            settled,
            with: .color(.textInactive.opacity(0.3)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 4])
        )
    }

    private func path(for curve: MotionCurve, in size: CGSize) -> Path {
        var path = Path()
        for sample in 0...Self.samples {
            let fraction = Double(sample) / Double(Self.samples)
            let point = CGPoint(
                x: size.width * fraction,
                y: y(for: curve.displacement(atTime: fraction * MotionCurve.graphWindow), in: size)
            )
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func y(for value: Double, in size: CGSize) -> CGFloat {
        let normalized = (value - Self.low) / (Self.high - Self.low)
        return size.height * (1 - normalized)
    }

    /// A dot driven by the real `Animation`, so the plot above it can be checked against
    /// something that is not a model.
    private var groundTruth: some View {
        HStack(spacing: 8) {
            Text("LIVE")
                .font(.silkscreenSmall)
                .foregroundColor(.textInactive)

            GeometryReader { geo in
                Circle()
                    .fill(Color.enhanceMint)
                    .frame(width: 10, height: 10)
                    .position(
                        x: dotAtEnd ? max(5, geo.size.width - 5) : 5,
                        y: geo.size.height / 2
                    )
                    .animation(curve.animation, value: dotAtEnd)
            }
            .frame(height: 14)
        }
        .onReceive(replay) { _ in
            dotAtEnd.toggle()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MotionCurveGraphView(curve: MotionCurve(response: 0.3, dampingFraction: 0.6))
        MotionCurveGraphView(
            curve: MotionCurve(response: 0.25, dampingFraction: 0.35),
            reference: MotionCurve(response: 0.3, dampingFraction: 0.6)
        )
        MotionCurveGraphView(curve: MotionCurve(response: 0.5, dampingFraction: 1.0))
    }
    .padding(16)
    .background(Color.surfaceCard)
}
