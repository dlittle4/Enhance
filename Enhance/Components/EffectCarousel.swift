import SwiftUI

/// The horizontal card gallery shared by all three effect tabs.
///
/// Spans the **full screen width** and insets its content to the canvas edges, rather
/// than being clipped at the canvas width. Clipping there put the cut on a line the rest
/// of the layout treats as a margin, so a sliced card read as a rendering fault — two
/// rounded corners and two square ones — instead of as content continuing off-screen.
///
/// The edges then dissolve, and only on the side that actually has more content. That is
/// this carousel's only "there is more" affordance: it has no scrollbar, and at three
/// cards it may not look scrollable at all.
struct EffectCarousel<Item: Hashable & Identifiable, Card: View>: View {
    let items: [Item]

    /// Centred on appear, so the active card is visible without the user hunting for it.
    let scrollTo: Item?

    /// Gap between the screen edge and the canvas, so cards line up with the canvas at
    /// rest while still being able to scroll out to the screen edge.
    let contentInset: CGFloat

    @ViewBuilder var card: (Item) -> Card

    /// How much hidden content lies off each end, in points, clamped to `fadeWidth`.
    @State private var overflow: EdgeOverflow = .none

    /// Width of the dissolve. Wide enough to read as a soft edge, narrow enough that it
    /// never eats a whole card.
    private let fadeWidth: CGFloat = 28

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        card(item).id(item)
                    }
                }
                .padding(.vertical, 2)
                // Plain padding rather than `.contentMargins`, which would fold into
                // `ScrollGeometry.contentInsets` and complicate the overflow arithmetic
                // below for no visible difference.
                .padding(.horizontal, contentInset)
            }
            .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
                let maxOffset = max(0, geometry.contentSize.width - geometry.containerSize.width)
                return EdgeOverflow(
                    leading: geometry.contentOffset.x,
                    trailing: maxOffset - geometry.contentOffset.x
                )
            } action: { _, new in
                overflow = new
            }
            .mask(fadeMask)
            .onAppear {
                guard let scrollTo else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(scrollTo, anchor: .center)
                    }
                }
            }
        }
    }

    /// Opaque means visible. Built from three fixed-width pieces rather than gradient
    /// stops so it needs no measured width of its own.
    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(1 - fadeAmount(overflow.leading)), .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)

            Rectangle().fill(.black)

            LinearGradient(
                colors: [.black, .black.opacity(1 - fadeAmount(overflow.trailing))],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
        }
    }

    /// Ramps in over the first `fadeWidth` points of hidden content, so nudging the
    /// carousel a few points does not snap the edge to fully transparent.
    private func fadeAmount(_ hidden: CGFloat) -> Double {
        Double(max(0, min(1, hidden / fadeWidth)))
    }
}

/// Hidden content off each end of a carousel.
struct EdgeOverflow: Equatable {
    var leading: CGFloat
    var trailing: CGFloat

    /// Both ends flush. Deliberately the initial value: assuming *no* overflow and
    /// letting the first geometry callback add the fade avoids a fade flashing on a
    /// carousel whose cards all fit.
    static let none = EdgeOverflow(leading: 0, trailing: 0)
}
