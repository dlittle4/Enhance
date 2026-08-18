import SwiftUI

/// One `EffectParameter` of kind `.toggle`: a filled row with its label on the leading edge
/// and a switch on the trailing one.
///
/// **The filled container is the point, not decoration.** Per the panel spec
/// (`node-id=10325-26147`, the "Grouped List" row) a switch row is a 48pt rounded card in
/// `surface-control`, with the switch inset *inside* it. An earlier version drew a bare
/// label-and-switch row with no container, which put the switch hard against the row's
/// trailing edge and let it clip against the panel's 16pt margin *(user-reported)*. The
/// internal padding here is what keeps the control clear of that edge, so the container and
/// the fix are the same thing.
///
/// It stays inline where `ParameterSliderRow` and `ParameterPickerRow` put their label above
/// the control: those need the panel's full width for a track or a swatch row, and a switch is
/// a fixed-size control with nothing to stretch. The spec draws it inline for that reason.
///
/// The card carries the parameter's label itself, so callers do **not** also wrap it in a
/// section label — the spec's separate heading above the group exists for a list of several
/// switches, and repeating "BACKGROUND ONLY" twice would read as a mistake.
struct ParameterToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    /// Called after the value settles, matching `ParameterSliderRow`'s `onCommit` so the
    /// caller can re-render the preview and record one undo entry per panel visit.
    var onCommit: () -> Void = {}

    /// From the panel spec: a 48pt card, 16pt radius, label inset by the grid and the switch
    /// held a little tighter to the trailing edge so its capsule reads as centred in the gap.
    private let cardHeight: CGFloat = 48
    private let trailingInset: CGFloat = 12

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
        .padding(.leading, AppConstants.Spacing.grid)
        .padding(.trailing, trailingInset)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.Spacing.grid, style: .continuous)
                .fill(Color.surfaceControl)
        )
        .onChange(of: isOn) { _, _ in onCommit() }
        // **No row-wide `onTapGesture`.** An earlier version put one on this row to widen the
        // hit target, which meant a tap landing on the switch was handled twice — once by the
        // `Toggle` and once by the gesture — flipping the value and flipping it straight back.
        // The control read as dead exactly where a user aims first. Widening the target has to
        // avoid overlapping the switch, so it is not worth the ambiguity; `Toggle` already has
        // a standard-size hit region.
    }
}
