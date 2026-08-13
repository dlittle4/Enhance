import SwiftUI

/// One `EffectParameter` of kind `.slider`, drawn as a dotted track with a numeric knob.
///
/// Replaces four near-identical bespoke sliders (intensity / size / face intensity /
/// face second) that differed only in which view-model property they wrote.
///
/// **Restructured for the 2026-08-12 design.** The label moved from a fixed 96pt column on the
/// left to a line above the track, which lets the track use the panel's full width. The track
/// itself changed from "mint line up to the knob, dots after it" to **dots on both sides** —
/// mint behind the knob, `textInactive` ahead of it — so the control reads as a discrete
/// 20-step scale rather than a progress bar.
struct ParameterSliderRow: View {
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

    /// Which way the current drag was going when it first exceeded the slop.
    ///
    /// Latched for the whole gesture rather than re-evaluated per frame: a scrub that drifts
    /// vertically must not hand control back to the scroll view mid-drag, and a scroll that
    /// drifts sideways must not start moving the knob.
    @State private var isHorizontalDrag: Bool? = nil

    /// From the design spec. The knob shrank from 34pt and the dots grew from 3pt — together
    /// they make the track read as a scale the knob sits *on*, rather than a handle on a bar.
    private let knobSize: CGFloat = 24
    private let dotSize: CGFloat = 4
    private let trackHeight: CGFloat = 49

    private var steps: Int { EffectParameter.sliderSteps }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.small) {
            Text(label)
                .font(.silkscreenSubheadline)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            track
                .frame(height: trackHeight)
        }
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
            let filledSteps = Int((progress * Double(steps)).rounded())

            ZStack(alignment: .leading) {
                // Dots sit on the same lattice the knob snaps to, so the knob always
                // lands on one rather than between two. Those behind the knob take the
                // accent; those ahead of it stay inactive.
                ForEach(0...steps, id: \.self) { step in
                    Circle()
                        .fill(step <= filledSteps ? Color.enhanceMint : Color.textInactive)
                        .frame(width: dotSize, height: dotSize)
                        .position(
                            x: knobSize / 2 + (CGFloat(step) / CGFloat(steps)) * travel,
                            y: midY
                        )
                }

                Circle()
                    .fill(Color.enhanceMint)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Text(valueText ?? "\(EffectParameter.displayValue(value))")
                            .font(.silkscreenSmall)
                            .foregroundColor(.textOnGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    )
                    .position(x: knobCentre, y: midY)
            }
            .contentShape(Rectangle())
            // A tap sets the value outright. This exists because the drag below can no
            // longer claim the touch immediately — see the note on `minimumDistance`.
            .onTapGesture(coordinateSpace: .local) { location in
                onBeginDrag()
                let raw = (location.x - knobSize / 2) / travel
                value = Self.quantise(raw, allowingZero: allowsZero)
                onCommit()
            }
            // **`simultaneousGesture`, and the axis latch, are both load-bearing.**
            //
            // This used to be `.gesture(DragGesture(minimumDistance: 0))`, which claims the
            // touch on contact and always beats the enclosing `ScrollView` — so a vertical
            // swipe starting on a slider scrubbed the value instead of scrolling the panel.
            // That was survivable while rows had a 96pt label column to drag on; the
            // 2026-08-12 design made every row a full-width slider, leaving no neutral area
            // and no way to scroll by drag at all.
            //
            // Raising `minimumDistance` alone does *not* fix it: SwiftUI does not arbitrate a
            // custom drag against a scroll view by direction, so once the gesture recognises
            // it is still exclusive. `simultaneousGesture` lets both see the touch, and this
            // one then declines anything vertical — the scroll view keeps those, and the
            // slider only acts on a drag that was horizontal when it crossed the slop.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag in
                        if isHorizontalDrag == nil {
                            let dx = abs(drag.translation.width)
                            let dy = abs(drag.translation.height)
                            // Ignore the ambiguous first frames; wait until one axis leads.
                            guard max(dx, dy) > 6 else { return }
                            isHorizontalDrag = dx > dy
                        }
                        guard isHorizontalDrag == true else { return }

                        if !didPushUndo {
                            onBeginDrag()
                            didPushUndo = true
                        }
                        // Map back out of knob-centre space before quantising.
                        let raw = (drag.location.x - knobSize / 2) / travel
                        value = Self.quantise(raw, allowingZero: allowsZero)
                    }
                    .onEnded { _ in
                        let wasScrubbing = isHorizontalDrag == true
                        isHorizontalDrag = nil
                        didPushUndo = false
                        if wasScrubbing { onCommit() }
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
