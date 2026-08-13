import SwiftUI

/// One `EffectParameter` of kind `.slider`, drawn as a dotted track with a numeric knob.
///
/// Replaces four near-identical bespoke sliders (intensity / size / face intensity /
/// face second) that differed only in which view-model property they wrote.
struct ParameterSliderRow: View {
    @Environment(\.panelRowHeight) private var rowHeight
    let label: String
    @Binding var value: Double

    /// Called once at the start of a drag, for the undo push.
    var onBeginDrag: () -> Void = {}

    /// Called on drag end — the discrete commit point that triggers regeneration.
    var onCommit: () -> Void = {}

    /// Lets the knob reach 0. See `quantise(_:allowingZero:)`.
    var allowsZero: Bool = false

    /// Replaces the knob's lattice integer with real units.
    ///
    /// The integer is a *position* readout — knob "7" tells you nothing about playback
    /// speed, whereas the button it replaced read "0.5X". Rows whose value has a unit
    /// should show it.
    var valueText: String? = nil

    /// Owned here rather than by the parent: each row has its own drag, so a shared
    /// flag across rows was never the right shape.
    @State private var didPushUndo = false

    /// Scales with the row so a shrunken row cannot clip it.
    private var knobSize: CGFloat { min(34, rowHeight - 2) }
    private let labelWidth: CGFloat = 96
    private let dotSize: CGFloat = 3

    private var steps: Int { EffectParameter.sliderSteps }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.silkscreenBody)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            track
        }
        .frame(height: rowHeight)
    }

    private var track: some View {
        GeometryReader { geo in
            // The knob is inset by half its width at each end, so its centre travels
            // `width - knobSize`, not the full width. Every position below is derived
            // from this one value — mixing the two spaces is what makes a knob lag the
            // finger at the extremes.
            let travel = max(1, geo.size.width - knobSize)
            let progress = max(0, min(1, value))
            let knobCentre = knobSize / 2 + progress * travel
            let midY = geo.size.height / 2

            ZStack(alignment: .leading) {
                // Dots sit on the same lattice the knob snaps to, so the knob always
                // lands on one rather than between two.
                ForEach(0...steps, id: \.self) { step in
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: dotSize, height: dotSize)
                        .position(
                            x: knobSize / 2 + (CGFloat(step) / CGFloat(steps)) * travel,
                            y: midY
                        )
                }

                Capsule()
                    .fill(Color.enhanceMint)
                    .frame(width: knobCentre, height: 2)
                    .position(x: knobCentre / 2, y: midY)

                Circle()
                    .fill(Color.enhanceMint)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Text(valueText ?? "\(EffectParameter.displayValue(value))")
                            .font(.silkscreenBody)
                            .foregroundColor(.textOnGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    )
                    .position(x: knobCentre, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !didPushUndo {
                            onBeginDrag()
                            didPushUndo = true
                        }
                        // Map back out of knob-centre space before quantising.
                        let raw = (drag.location.x - knobSize / 2) / travel
                        value = Self.quantise(raw, allowingZero: allowsZero)
                    }
                    .onEnded { _ in
                        didPushUndo = false
                        onCommit()
                    }
            )
        }
        .animation(.easeOut(duration: 0.1), value: value)
    }

    /// Snaps to the dot lattice so the knob's integer is honest — a continuous value
    /// would show "10" across a range of positions.
    ///
    /// The floor is one step rather than zero: `0.05` is exactly 1/20, so the lowest
    /// reachable value reads as "1". This matches the old sliders, which also clamped
    /// to 0.05 to avoid handing an effect a zero strength.
    ///
    /// `allowingZero` opts out, for rows whose zero is meaningful rather than degenerate
    /// — a 0s pause is a real setting, an effect at zero strength is just "off". The two
    /// floors are deliberate opposites, not an inconsistency.
    static func quantise(_ raw: Double, allowingZero: Bool = false) -> Double {
        let steps = Double(EffectParameter.sliderSteps)
        let snapped = (max(0, min(1, raw)) * steps).rounded() / steps
        return max(allowingZero ? 0 : 1 / steps, snapped)
    }
}
