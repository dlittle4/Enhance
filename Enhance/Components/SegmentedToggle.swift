import SwiftUI

/// A joined always-one-selected control, drawn as segments in a single track.
///
/// The 2026-08-12 design's treatment: a `surfaceControl` track with the selected segment
/// filled `mintDim` and outlined 2pt in `enhanceMint`, its label mint while the others stay
/// `textPrimary`. Works for any number of options — the spec shows two and three.
///
/// **Separate from `SegmentedBar`, not a replacement for it.** That one is the zoom panel's
/// LINEAR / SHAKE / SPIRAL row and still carries its own `panelRowHeight` behaviour and
/// `onWillChange` undo hook. Folding them together would mean reconciling two different
/// height models in the same commit as a visual redesign; this stays the parameter-panel
/// control until that is worth doing deliberately.
struct SegmentedToggle<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String

    /// Called before the selection changes, for the undo push.
    var onWillChange: (() -> Void)? = nil

    /// Called after the selection changes — the commit point that triggers regeneration.
    var onChange: (() -> Void)? = nil

    /// From the design spec.
    private let height: CGFloat = 46
    private let selectedBorderWidth: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    guard selection != item else { return }
                    onWillChange?()
                    HapticService.light()
                    withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                        selection = item
                    }
                    onChange?()
                } label: {
                    Text(label(item))
                        .font(.silkscreenSubheadline)
                        .foregroundColor(isSelected ? .enhanceMint : .textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.control,
                                             style: .continuous)
                                .fill(isSelected ? Color.mintDim : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.control,
                                             style: .continuous)
                                .stroke(isSelected ? Color.enhanceMint : Color.clear,
                                        lineWidth: selectedBorderWidth)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.control, style: .continuous)
                .fill(Color.surfaceControl)
        )
    }
}

#Preview {
    struct Harness: View {
        @State private var two = "COLOR"
        @State private var three = "THREE"
        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FILL").font(.silkscreenSubheadline).foregroundColor(.textPrimary)
                    SegmentedToggle(items: ["GRADIENT", "COLOR"], selection: $two) { $0 }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOGGLE 3 OPTIONS").font(.silkscreenSubheadline).foregroundColor(.textPrimary)
                    SegmentedToggle(items: ["ONE", "TWO", "THREE"], selection: $three) { $0 }
                }
            }
            .padding(16)
            .background(Color.surfaceCard)
        }
    }
    return Harness()
}
