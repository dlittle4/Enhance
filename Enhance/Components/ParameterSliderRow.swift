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

    /// The lattice step the last haptic fired for.
    ///
    /// The drag emits a value on every frame, but the knob only *moves between dots* occasionally
    /// — so the tick has to be keyed to the step changing rather than to the gesture updating, or
    /// the Taptic Engine is asked to fire 60 times a second and the result is a buzz rather than
    /// a series of detents.
    @State private var lastHapticStep: Int?

    /// From the design spec. The dots grew from 3pt so the track reads as a scale the knob sits
    /// *on*, rather than a handle on a bar.
    ///
    /// The knob is a **40 × 24 capsule** as of 2026-08-13, up from a 24pt circle. A circle that
    /// size had to shrink its label to fit — `0.25X` is five characters — and the wider capsule
    /// gives the readout room without making the knob taller than the dots it rides over.
    private let knobWidth: CGFloat = 40
    private let knobHeight: CGFloat = 24
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
            // **The dots own the geometry, not the knob** *(user's call, 2026-08-13: the dots
            // should fill the panel's width out to its 16pt margin)*.
            //
            // Both used to share a travel of `width - knobWidth`, which inset the first and last
            // dot by half a knob — 20pt of dead track at each end. The scale now spans the full
            // width, inset only by half a dot so the end dots are drawn whole, and every position
            // below derives from that one value. Mixing the two spaces is what makes a knob lag
            // the finger at the extremes.
            let travel = max(1, geo.size.width - dotSize)
            let progress = max(0, min(1, value))
            let midY = geo.size.height / 2
            let filledSteps = Int((progress * Double(steps)).rounded())

            // The knob rides the same scale, but is held inside the track: centred on its dot it
            // would hang 18pt past each end, and the enclosing `ScrollView` clips. Only the first
            // and last step or two are affected — the dots are ~15pt apart and the knob's half
            // width is 20 — and there the knob's *edge* lining up with the track's edge is what
            // you would want anyway.
            let dotCentre = dotSize / 2 + progress * travel
            let knobCentre = min(max(dotCentre, knobWidth / 2), geo.size.width - knobWidth / 2)

            ZStack(alignment: .leading) {
                // Dots sit on the same lattice the knob snaps to, so the knob always
                // lands on one rather than between two. Those behind the knob take the
                // accent; those ahead of it stay inactive.
                ForEach(0...steps, id: \.self) { step in
                    Circle()
                        .fill(step <= filledSteps ? Color.enhanceMint : Color.textInactive)
                        .frame(width: dotSize, height: dotSize)
                        .position(
                            x: dotSize / 2 + (CGFloat(step) / CGFloat(steps)) * travel,
                            y: midY
                        )
                }

                knob(travel: travel)
                    .position(x: knobCentre, y: midY)
            }
            // The track takes taps but **no drag**, which is the whole point: a drag that
            // starts anywhere except the knob belongs to the enclosing `ScrollView`.
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                onBeginDrag()
                let raw = (location.x - dotSize / 2) / travel
                let snapped = Self.quantise(raw, allowingZero: allowsZero)
                // One tick for a tap: it is a single discrete jump, however far it travels.
                if snapped != value { HapticService.selection() }
                value = snapped
                onCommit()
            }
            .coordinateSpace(name: Self.trackSpace)
        }
        .animation(.easeOut(duration: 0.1), value: value)
    }

    /// The knob, and the only part of the row that scrubs.
    ///
    /// **Dragging is scoped to the knob deliberately** *(user's call, 2026-08-12)*. Two earlier
    /// approaches failed: a `minimumDistance: 0` drag over the whole track claimed every touch
    /// and made the panel unscrollable, and raising `minimumDistance` changed nothing because
    /// SwiftUI does not arbitrate a custom drag against a scroll view by direction — once it
    /// recognises, it is exclusive. Guessing intent from the drag's axis worked but was still a
    /// guess.
    ///
    /// Scoping the gesture removes the ambiguity instead of resolving it: grab the knob and you
    /// are scrubbing, touch anywhere else and the panel scrolls. The knob's own gesture keeps
    /// `minimumDistance: 0` so a scrub starts immediately, and because it is attached to the knob
    /// alone it can claim the touch without stealing the rest of the row.
    ///
    /// The hit area is 40 × 44 around the 40 × 24 capsule — the knob is under Apple's minimum
    /// target vertically, and this is the only way to drag.
    private func knob(travel: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.enhanceMint)
            .frame(width: knobWidth, height: knobHeight)
            .overlay(
                Text(valueText ?? "\(EffectParameter.displayValue(value))")
                    .font(.silkscreenSmall)
                    .foregroundColor(.textOnGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            )
            // 44pt tall for the touch target; the capsule is already 40 wide, so the hit area
            // only needs to match it horizontally rather than pad it into its neighbours.
            .frame(width: knobWidth, height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.trackSpace))
                    .onChanged { drag in
                        if !didPushUndo {
                            onBeginDrag()
                            didPushUndo = true
                            HapticService.prepareSelection()
                            lastHapticStep = Self.step(of: value, steps: steps)
                        }
                        // Map back out of knob-centre space before quantising.
                        let raw = (drag.location.x - dotSize / 2) / travel
                        let snapped = Self.quantise(raw, allowingZero: allowsZero)

                        // One tick per dot crossed, so the track feels like detents under the
                        // thumb rather than a continuous slide.
                        let step = Self.step(of: snapped, steps: steps)
                        if step != lastHapticStep {
                            HapticService.selection()
                            lastHapticStep = step
                        }

                        value = snapped
                    }
                    .onEnded { _ in
                        didPushUndo = false
                        lastHapticStep = nil
                        onCommit()
                    }
            )
    }

    /// Which dot a 0…1 value sits on. Used to decide when a drag has crossed a detent.
    static func step(of value: Double, steps: Int) -> Int {
        Int((max(0, min(1, value)) * Double(steps)).rounded())
    }

    /// Names the track's coordinate space so the knob's drag reports positions in it rather
    /// than in its own 44pt frame.
    private static let trackSpace = "slider-track"

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
