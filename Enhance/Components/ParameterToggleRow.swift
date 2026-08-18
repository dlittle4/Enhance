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
        // The whole row is the hit target, not just the switch — a 51pt control on the far
        // edge of a 350pt row is a small target for a control whose label is right there.
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}
