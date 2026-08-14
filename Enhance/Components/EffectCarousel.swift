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

    /// Staggered card entrance when the carousel arrives, or `nil` for the shipped
    /// all-at-once appearance. A value, so the component stays free of the tuning store.
    var cascade: CardCascadeMotion? = nil

    @ViewBuilder var card: (Item) -> Card

    /// Flipped once, on appear; each card animates toward it on its own delay. The carousel is
    /// rebuilt per category (each tab's branch is its own view identity), so switching tabs
    /// resets this and replays the cascade — which is the point.
    @State private var cascadeIn = false

    /// How much hidden content lies off each end, in points, clamped to `fadeWidth`.
    @State private var overflow: EdgeOverflow = .none

    /// Width of the dissolve. Wide enough to read as a soft edge, narrow enough that it
    /// never eats a whole card.
    private let fadeWidth: CGFloat = 28

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        card(item)
                            .modifier(CascadeEntrance(
                                shown: cascadeIn || cascade == nil,
                                delay: Double(index) * (cascade?.stagger ?? 0),
                                curve: cascade?.curve
                            ))
                            .id(item)
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
                // One flip; the per-card delay does the sequencing. Set unconditionally so a
                // cascade toggled on later still finds the settled state.
                cascadeIn = true
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

/// What a card cascade needs to know. Top-level rather than nested in `EffectCarousel`,
/// which is generic — naming a nested type would force call sites to spell out the
/// carousel's type parameters just to build a value.
struct CardCascadeMotion: Equatable {
    /// Seconds between one card starting its entrance and the next.
    var stagger: Double
    var curve: MotionCurve
}

/// One card's entrance in a cascade: transparent, small and slightly low until `shown`, then
/// springing to rest on its own delay — index × stagger, so the row reads left to right.
///
/// Always in the tree rather than applied conditionally, for the same reason
/// `PixelRevealModifier` documents: a modifier that comes and goes changes the view's identity
/// and can drop the very animation it drives. With `shown` true and no curve it is inert.
private struct CascadeEntrance: ViewModifier {
    let shown: Bool
    let delay: Double
    let curve: MotionCurve?

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.8)
            .offset(y: shown ? 0 : 14)
            .animation(curve.map { $0.animation.delay(delay) }, value: shown)
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
