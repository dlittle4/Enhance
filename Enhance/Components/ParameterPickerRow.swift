import SwiftUI

/// One `EffectParameter` of a picker kind, laid out to match `ParameterSliderRow` —
/// same height, same label column width, so labels align down the panel regardless of
/// whether a row holds a slider or swatches.
///
/// Deliberately generic over its content rather than switching on
/// `EffectParameter.Kind` itself. The gradient stop wells in particular are fragile
/// (see LEARNINGS 2026-08-07 — three failed attempts at restyling `ColorPicker`), so
/// the caller keeps ownership of the actual control and this only supplies the row.
struct ParameterPickerRow<Content: View>: View {
    @Environment(\.panelRowHeight) private var rowHeight
    let label: String
    @ViewBuilder var content: () -> Content

    private let labelWidth: CGFloat = 96

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.silkscreenControl)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity)
        }
        .frame(height: rowHeight)
    }
}
