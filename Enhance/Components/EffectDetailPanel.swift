import SwiftUI

/// The effect's control panel: a pinned header over a list of parameter rows.
///
/// Generic over its rows so the caller keeps ownership of building them from an
/// effect's declared `parameters` — the panel only supplies the chrome and the
/// scrolling behaviour.
struct EffectDetailPanel<Rows: View>: View {
    let title: String
    var onCancel: () -> Void
    var onConfirm: () -> Void
    @ViewBuilder var rows: () -> Rows

    /// Measured so the row list only becomes scrollable when it actually overflows.
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var needsScroll: Bool { contentHeight > viewportHeight + 0.5 }

    var body: some View {
        VStack(spacing: 8) {
            header

            ScrollView {
                VStack(spacing: 8) {
                    rows()
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // Only scrollable when the rows genuinely don't fit.
            //
            // This is load-bearing, not tidiness: the sliders use
            // `DragGesture(minimumDistance: 0)`, which claims a touch immediately and
            // would beat the scroll view — so a drag starting on a row would scroll
            // instead of adjusting the value. Disabling the scroll whenever the content
            // fits (every effect today, at one to three rows) means the conflict simply
            // does not arise in the common case.
            .scrollDisabled(!needsScroll)
            .scrollIndicators(needsScroll ? .automatic : .hidden)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.Layout.panelCornerRadius, style: .continuous)
                .fill(Color(hex: 0x1C1815))
        )
    }

    /// Title centred independently of the buttons.
    ///
    /// The buttons are `.overlay`s rather than `HStack` siblings around a `Spacer`,
    /// because Spacer-based centring shifts the title whenever the two buttons differ
    /// in width — and here one is a glyph and the other an icon.
    private var header: some View {
        Text(title)
            .font(.silkscreenButtonLabel)
            .foregroundColor(.enhanceMint)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: AppConstants.Layout.parameterRowHeight)
            .overlay(alignment: .leading) {
                Button {
                    HapticService.light()
                    onCancel()
                } label: {
                    // Matches the editor's existing "X" close treatment.
                    Text("<")
                        .font(.custom("Silkscreen-Regular", size: 24))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .trailing) {
                Button {
                    HapticService.success()
                    onConfirm()
                } label: {
                    Image("icon-check")
                        .renderingMode(.template)
                        .foregroundColor(.enhanceMint)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
    }
}
