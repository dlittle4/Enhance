import SwiftUI

/// A joined always-one-selected control.
///
/// Used for the zoom panel's LINEAR / SHAKE / SPIRAL motion row. LEARNINGS 2026-03-13
/// argues against segmented controls where selection is optional, because there is no
/// honest way to render "none" — but that does not apply here: `.straight` **is** none.
/// `activeAnimator` treats `nil` and `.straight` identically, so LINEAR is the name of
/// nothing rather than a fourth state pretending to be nothing, and the view model's
/// `modifierSelection` keeps `nil` canonical in storage.
struct SegmentedBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var onChange: (() -> Void)? = nil
    var onWillChange: (() -> Void)? = nil

    /// Follows the panel's adaptive row height so it lines up with slider rows.
    @Environment(\.panelRowHeight) private var rowHeight

    private let mintGreen = Color.enhanceMint

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    guard selection != item else { return }
                    onWillChange?()
                    withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                        selection = item
                    }
                    onChange?()
                } label: {
                    Text(label(item))
                        .font(.silkscreenBody)
                        .foregroundColor(isSelected ? mintGreen : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                                .fill(isSelected ? Color.segmentSelected.opacity(0.7) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                                .stroke(isSelected ? mintGreen : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}