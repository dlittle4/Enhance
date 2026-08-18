import SwiftUI

/// One `EffectParameter` of kind `.toggle`: a label with a switch on the trailing edge.
///
/// **Deliberately inline, where `ParameterSliderRow` and `ParameterPickerRow` put the label
/// *above* the control.** Those two need the panel's full width for a track or a six-swatch
/// row, and the shared rhythm exists to serve that. A switch is a fixed-size control with
/// nothing to stretch, and the Figma spec for it (`node-id=10346-8747`, an Apple HIG grouped
/// list row) is explicitly label-left / switch-right. Stacking a label above a lone switch
/// would waste a row's height and read as an unfinished picker.
///
/// Sized to `PanelMetrics`' fixed row height so it shares the panel's vertical rhythm even
/// though its internal arrangement differs.
struct ParameterToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    /// Called after the value settles, matching `ParameterSliderRow`'s `onCommit` so the
    /// caller can re-render the preview and record one undo entry per panel visit.
    var onCommit: () -> Void = {}

    var body: some View {
        HStack(spacing: AppConstants.Spacing.small) {
            Text(label)
                .font(.silkscreenSubheadline)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AppConstants.Spacing.small)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.enhanceMint)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: isOn) { _, _ in onCommit() }
        // **No row-wide `onTapGesture`.** An earlier version put one on this HStack to widen the
        // hit target, which meant a tap landing on the switch was handled twice — once by the
        // `Toggle` and once by the gesture — flipping the value and flipping it straight back.
        // The control read as dead exactly where a user aims first. Widening the target has to
        // avoid overlapping the switch, so it is not worth the ambiguity; `Toggle` already has
        // a standard-size hit region.
    }
}
