import SwiftUI

/// Infinite carousel with center-scale effect, swipe support, and slow auto-scroll.
/// Supports both static images (by asset name) and animated GIFs (by file URL).
struct ShowcaseCarousel: View {
    let items: [CarouselItem]

    enum CarouselItem {
        case image(String)
        case gif(URL)
    }

    private let baseSize: CGFloat = 305
    private let edgeScale: CGFloat = 265.0 / 305.0
    private let spacing: CGFloat = 16
    private let visibleRange = -3...3
    private let autoScrollRate: CGFloat = -0.08

    @State private var position: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var isDragging = false
    @State private var autoScrollAnchor: CGFloat = 0
    @State private var autoScrollStart: Date = .now

    private var nominalStep: CGFloat {
        (baseSize + baseSize * edgeScale) / 2 + spacing
    }

    private func scaleForDistance(_ d: CGFloat) -> CGFloat {
        max(edgeScale, 1.0 - (1.0 - edgeScale) * abs(d))
    }

    private func sizeForDistance(_ d: CGFloat) -> CGFloat {
        baseSize * scaleForDistance(d)
    }

    private func xPosition(displayOffset: CGFloat, centerX: CGFloat) -> CGFloat {
        guard abs(displayOffset) > 0.001 else { return centerX }

        let sign: CGFloat = displayOffset > 0 ? 1 : -1
        let absOffset = abs(displayOffset)
        let wholeSteps = Int(absOffset)
        let fractional = absOffset - CGFloat(wholeSteps)

        var x: CGFloat = 0
        let centerHalf = sizeForDistance(0) / 2

        if wholeSteps == 0 {
            let neighborHalf = sizeForDistance(fractional) / 2
            x = fractional * (centerHalf + spacing + neighborHalf)
            return centerX + sign * x
        }

        x += centerHalf + spacing + sizeForDistance(1) / 2

        for step in 1..<wholeSteps {
            let d = CGFloat(step)
            x += sizeForDistance(d) / 2 + spacing + sizeForDistance(d + 1) / 2
        }

        if fractional > 0.001 {
            let d = CGFloat(wholeSteps)
            x += fractional * (sizeForDistance(d) / 2 + spacing + sizeForDistance(d + fractional) / 2)
        }

        return centerX + sign * x
    }

    var body: some View {
        TimelineView(.animation(paused: isDragging)) { timeline in
            let elapsed = isDragging
                ? 0.0
                : timeline.date.timeIntervalSince(autoScrollStart) * autoScrollRate
            let effectiveIndex = position + CGFloat(elapsed)

            carouselContent(effectiveIndex: effectiveIndex)
        }
        .frame(height: baseSize)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private func carouselContent(effectiveIndex: CGFloat) -> some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let floorIndex = floor(effectiveIndex)
            let fraction = effectiveIndex - floorIndex

            ZStack {
                ForEach(visibleRange, id: \.self) { offset in
                    let displayOffset = CGFloat(offset) - fraction
                    let absDistance = abs(displayOffset)
                    let scale = scaleForDistance(displayOffset)
                    let size = baseSize * scale
                    let xPos = xPosition(displayOffset: displayOffset, centerX: centerX)

                    let rawIndex = Int(floorIndex) + offset
                    let count = max(items.count, 1)
                    let wrapped = ((rawIndex % count) + count) % count

                    itemView(for: items[wrapped])
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .position(x: xPos, y: geo.size.height / 2)
                        .zIndex(10 - absDistance)
                        .onTapGesture {
                            guard abs(displayOffset) > 0.3 else { return }
                            let elapsed = Date.now.timeIntervalSince(autoScrollStart) * autoScrollRate
                            let current = position + CGFloat(elapsed)
                            let target = (current + displayOffset).rounded()
                            position = current
                            isDragging = true
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                position = target
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                autoScrollStart = .now
                                isDragging = false
                            }
                        }
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if !isDragging {
                    let elapsed = Date.now.timeIntervalSince(autoScrollStart) * autoScrollRate
                    position += CGFloat(elapsed)
                    dragStart = position
                    isDragging = true
                }
                position = dragStart - value.translation.width / nominalStep
            }
            .onEnded { value in
                let drag = -value.translation.width / nominalStep
                let predicted = -value.predictedEndTranslation.width / nominalStep
                let momentum = predicted - drag

                var target: CGFloat
                if abs(momentum) > 0.3 {
                    target = momentum > 0
                        ? ceil(position)
                        : floor(position)
                } else if abs(drag) > 0.05 {
                    target = drag > 0
                        ? ceil(dragStart)
                        : floor(dragStart)
                } else {
                    target = position.rounded()
                }

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    position = target
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    autoScrollStart = .now
                    isDragging = false
                }
            }
    }

    @ViewBuilder
    private func itemView(for item: CarouselItem) -> some View {
        switch item {
        case .image(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .gif(let url):
            AnimatedGifView(url: url, contentMode: .scaleAspectFill, lowQuality: true)
        }
    }
}
