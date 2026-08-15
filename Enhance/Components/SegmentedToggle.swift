import SwiftUI

/// A joined always-one-selected control, drawn as segments in a single track.
///
/// **The** segmented control for the effect panels — PIXELATE's cell shape, the zoom panel's
/// MOTION row, and the text panel's FILL and FROM rows all render through this. If a panel needs
/// a row of mutually-exclusive buttons, it needs this type; a new one-off is the bug.
///
/// The 2026-08-12 design's treatment: a `surfaceControl` track with the selected segment
/// filled `mintDim` and outlined 2pt in `enhanceMint`, its label mint while the others stay
/// `textPrimary`. Works for any number of options — the spec shows two and three.
///
/// ## Why the height is a constant
///
/// This absorbed `SegmentedBar` on 2026-08-13 *(user's call: the buttons must be one height
/// everywhere, and PIXELATE's are the right one)*. That type was the same control with a second
/// set of values — 14pt type instead of 12, `mintDim.opacity(0.7)` instead of `mintDim`, `.white`
/// instead of `textPrimary`, no haptic — and, visibly, a height that tracked
/// `\.panelRowHeight` and so shrank to as little as 34pt on a short device while PIXELATE's row
/// stayed 46.
///
/// Its stated reason for tracking that value was to "line up with slider rows", and that reason
/// had quietly expired: the same 2026-08-12 redesign gave `ParameterSliderRow` a fixed 49pt track
/// and stopped it reading `panelRowHeight` at all. `SegmentedBar` was shrinking to match something
/// that no longer shrank, which is what made two rows in the same panel disagree.
///
/// So the height is deliberately **not** adaptive. A button's touch target should not depend on
/// how many rows happen to share the panel; when the rows genuinely do not fit, the panel scrolls
/// (`EffectDetailPanel.needsScroll`), which ROADMAP §1a accepts and verified on an SE 3.
struct SegmentedToggle<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String

    /// Called before the selection changes, for the undo push.
    var onWillChange: (() -> Void)? = nil

    /// Called after the selection changes — the commit point that triggers regeneration.
    var onChange: (() -> Void)? = nil

    /// From the design spec, and the same on every panel — see the note above on why this is a
    /// constant rather than an environment read.
    private let height: CGFloat = 46

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
                    // Solid mint with dark type for the selection, and **no outline**
                    // *(user's call, 2026-08-15)*. The old treatment was a dim mint wash plus
                    // a 2pt mint ring, which spent two devices — fill and stroke — saying one
                    // thing; a filled segment reads as selected on its own.
                    Text(label(item))
                        .font(.silkscreenSubheadline)
                        .foregroundColor(isSelected ? .textOnGradient : .textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.control,
                                             style: .continuous)
                                .fill(isSelected ? Color.enhanceMint : Color.clear)
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
