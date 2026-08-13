import SwiftUI

/// One `EffectParameter` of a picker kind, laid out to match `ParameterSliderRow` —
/// **label above the control**, so every row in the panel shares the same rhythm regardless of
/// whether it holds a slider, swatches or a toggle.
///
/// Restructured for the 2026-08-12 design, which moved labels out of a fixed left column. The
/// control now gets the panel's full width, which is what the six-swatch colour row and the
/// segmented toggle both need.
///
/// Deliberately generic over its content rather than switching on
/// `EffectParameter.Kind` itself. The gradient stop wells in particular are fragile
/// (see LEARNINGS 2026-08-07 — three failed attempts at restyling `ColorPicker`), so
/// the caller keeps ownership of the actual control and this only supplies the row.
struct ParameterPickerRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.small) {
            Text(label)
                .font(.silkscreenSubheadline)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            content()
                .frame(maxWidth: .infinity)
        }
    }
}
