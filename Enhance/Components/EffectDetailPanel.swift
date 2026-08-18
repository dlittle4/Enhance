import SwiftUI

/// Identifies the end of the panel's row list for `scrollTo`.
///
/// A file-level constant rather than a static on `EffectDetailPanel` because that type is
/// generic over its rows, and Swift does not allow static stored properties on generic types.
private let panelBottomAnchor = "panel-bottom"

/// Diameter of the scroll nudge. File-level for the same reason as `panelBottomAnchor`.
private let panelNudgeDiameter: CGFloat = 32

/// The effect's control panel: a pinned header over a list of parameter rows.
///
/// Generic over its rows so the caller keeps ownership of building them from an
/// effect's declared `parameters` — the panel only supplies the chrome and the
/// scrolling behaviour.
struct EffectDetailPanel<Rows: View>: View {
    let title: String

    /// Height the panel has actually been given, measured by the caller. Rows shrink to
    /// fit it rather than overflowing — see `AppConstants.Layout.parameterRowHeight(forPanelHeight:rowCount:)`.
    var availableHeight: CGFloat = 0

    /// How many rows `rows` will produce. The panel cannot infer this from opaque
    /// content, and needs it to size them before they are laid out.
    var rowCount: Int = 0

    var onCancel: () -> Void
    var onConfirm: () -> Void
    @ViewBuilder var rows: () -> Rows

    /// The **header's** height. Named for what it still does: the rows themselves are fixed-height
    /// as of 2026-08-13 (see `PanelMetrics`), so this no longer sizes anything below the title.
    private var rowHeight: CGFloat {
        AppConstants.Layout.parameterRowHeight(forPanelHeight: availableHeight, rowCount: rowCount)
    }

    /// Measured so the row list only becomes scrollable when it actually overflows.
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var needsScroll: Bool { contentHeight > viewportHeight + 0.5 }

    /// How far the row list has been scrolled, so the nudge can hide once the user reaches
    /// the end and does not sit there promising more content that is not coming.
    @State private var scrollOffset: CGFloat = 0

    private var isAtBottom: Bool {
        scrollOffset >= contentHeight - viewportHeight - 4
    }

    var body: some View {
        VStack(spacing: 8) {
            header

            ScrollViewReader { proxy in
              ScrollView {
                // 24pt between parameter groups, per the design spec. Each row is now a
                // label-plus-control stack rather than a single line, so the gap has to be
                // larger than the 8pt *inside* a row or the two rhythms compete.
                VStack(alignment: .leading, spacing: AppConstants.Spacing.standard) {
                    rows()

                    // Zero-height run-out below the last row (it buys one VStack spacing).
                    Color.clear
                        .frame(height: 0)
                }
                // Replaces the panel's bottom padding, which had to go so the rows could scroll
                // all the way to the panel's edge — see the overlay note below. Applied to the
                // *content* so it scrolls with the rows, and only while scrolling, so a panel
                // that fits is untouched. Padding can only add overflow, so it cannot flip
                // `needsScroll` off and oscillate.
                .padding(.bottom, needsScroll ? AppConstants.Spacing.grid : 0)
                .frame(maxWidth: .infinity)
                // The nudge's scroll target — on the *padded* content, not a zero-height element
                // inside it. `scrollTo(anchor: .bottom)` aligns the identified view's bottom edge
                // with the viewport's, so an anchor inside the padding stopped 16pt short of the
                // end; `isAtBottom`'s 4pt tolerance read that as "not there yet" and the nudge
                // survived its own tap.
                .id(panelBottomAnchor)
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
              .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in
                  scrollOffset = new
              }
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
              .frame(maxHeight: .infinity, alignment: .top)

              // The nudge **floats** over the rows rather than taking a slot below them.
              //
              // Arrangements tried here, because each failure is invisible until you tap or look
              // closely at the thing underneath:
              //
              // 1. *Its own slot below the viewport.* Nothing could be covered, but it cost 40pt
              //    of a viewport that measures 72pt on an SE 3, pushing a whole row off the fold.
              //    Traded an unreachable control for an invisible one.
              // 2. *Floating, offset half into the panel's 16pt bottom padding.* The padding kept
              //    the scroll viewport 16pt short of the panel's edge, so the rows were clipped on
              //    a straight line running through the middle of the chevron. That reads as the
              //    nudge resting on a cut edge — the opposite of floating *(user-reported)*.
              // 3. *This.* The panel has **no bottom padding**, so the viewport runs to its
              //    rounded edge and the rows clip there instead — against the panel's own
              //    boundary, where a clip reads as the panel ending. The nudge then sits just
              //    inside that edge with content passing beneath it. The 16pt of breathing room
              //    the padding used to give moved onto the scroll *content*, so it travels with
              //    the rows rather than shortening the viewport.
              //
              // **Overlapping a control is accepted, not prevented** *(user's call, 2026-08-13:
              // "it's okay if the middle swatch buttons are untappable when the scroll nudge is
              // present")*.
              .overlay(alignment: .bottom) {
                  if needsScroll && !isAtBottom {
                      scrollNudge(proxy: proxy)
                          .padding(.bottom, AppConstants.Spacing.small)
                  }
              }
            }
        }
        .padding(.horizontal, AppConstants.Spacing.grid)
        .padding(.top, AppConstants.Spacing.grid)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.Spacing.standard, style: .continuous)
                .fill(Color.surfaceCard)
        )
    }

    /// A tap target that scrolls the row list on, because a drag cannot.
    ///
    /// **This is not decoration.** The 2026-08-12 design moved every parameter label above its
    /// control, so a row is now a full-width slider with no dead margin — and the sliders use
    /// `DragGesture(minimumDistance: 0)`, which claims a touch before the `ScrollView` sees it.
    /// With the old label-on-the-left layout there was at least a 96pt column to drag on. Now
    /// there is nothing, so on a short device the rows below the fold would be unreachable
    /// without this. The design calls it the scroll nudge; it is the answer to a real gesture
    /// conflict rather than a flourish.
    ///
    /// Hidden once the list is at its end, so it never promises content that is not there.
    private func scrollNudge(proxy: ScrollViewProxy) -> some View {
        Button {
            HapticService.light()
            withAnimation(Motion.panel) {
                proxy.scrollTo(panelBottomAnchor, anchor: .bottom)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .frame(width: panelNudgeDiameter, height: panelNudgeDiameter)
                .background(Circle().fill(Color.surfacePrimary))
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityLabel("Scroll to more controls")
    }

    /// Title centred independently of the buttons.
    ///
    /// The buttons are `.overlay`s rather than `HStack` siblings around a `Spacer`,
    /// because Spacer-based centring shifts the title whenever the two buttons differ
    /// in width — and here one is a glyph and the other an icon.
    private var header: some View {
        Text(title)
            .font(.silkscreenSubheadline)
            .foregroundColor(.enhanceMint)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .overlay(alignment: .leading) {
                Button {
                    HapticService.light()
                    onCancel()
                } label: {
                    // Matches the editor's existing "X" close treatment.
                    // 44pt stays the tap target, but the glyph is pinned to the leading
                    // edge of it rather than centred — otherwise the frame adds 10pt of
                    // visual inset on top of the panel's own 16pt padding and the chevron
                    // drifts into the title.
                    Text("<")
                        .font(.silkscreenTitle)
                        .foregroundColor(.textPrimary)
                        .frame(width: 44, height: 44, alignment: .leading)
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
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
    }
}
