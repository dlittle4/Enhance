import SwiftUI

struct ImageCanvasView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var visibleRect: CGRect
    
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var localVisibleRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    private let canvasSize: CGFloat = 325
    
    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvasSize, height: canvasSize)
                .scaleEffect(scale)
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: AppConstants.Animation.standard)) {
                        scale = scale > 1 ? 1 : 2
                        lastScale = scale
                        offset = .zero
                        lastOffset = .zero
                        calculateVisibleRect()
                    }
                }
                .offset(x: offset.width, y: offset.height)

            ZoomFrameOverlay(image: image, visibleRect: localVisibleRect, scale: scale)
                .frame(width: canvasSize, height: canvasSize)
                .allowsHitTesting(false)
        }
        .frame(width: canvasSize, height: canvasSize)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous))
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .gesture(magnificationGesture)
        .onChange(of: scale) { _, _ in calculateVisibleRect() }
        .onChange(of: localVisibleRect) { _, newRect in
            DispatchQueue.main.async { visibleRect = newRect }
        }
        .onAppear { calculateVisibleRect() }
    }
    
    /// The rendered image dimensions at the current scale, accounting for `.fill` aspect ratio.
    private var renderedSize: CGSize {
        let fillScale = max(canvasSize / image.size.width, canvasSize / image.size.height)
        return CGSize(
            width: image.size.width * fillScale * scale,
            height: image.size.height * fillScale * scale
        )
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                let rendered = renderedSize
                let maxOffsetX = max(0, (rendered.width - canvasSize) / 2)
                let maxOffsetY = max(0, (rendered.height - canvasSize) / 2)
                offset = CGSize(
                    width: min(maxOffsetX, max(-maxOffsetX, lastOffset.width + value.translation.width)),
                    height: min(maxOffsetY, max(-maxOffsetY, lastOffset.height + value.translation.height))
                )
                calculateVisibleRect()
            }
            .onEnded { _ in lastOffset = offset }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = min(max(1, lastScale * value), AppConstants.Zoom.maxScale)
                scale = newScale
                calculateVisibleRect()
            }
            .onEnded { _ in
                lastScale = scale
                withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                    scale = round(scale * 10) / 10
                    lastScale = scale
                    let rendered = renderedSize
                    let maxOffsetX = max(0, (rendered.width - canvasSize) / 2)
                    let maxOffsetY = max(0, (rendered.height - canvasSize) / 2)
                    offset = CGSize(
                        width: min(maxOffsetX, max(-maxOffsetX, offset.width)),
                        height: min(maxOffsetY, max(-maxOffsetY, offset.height))
                    )
                    lastOffset = offset
                    calculateVisibleRect()
                }
            }
    }
    
    private func calculateVisibleRect() {
        guard scale > 1 else {
            localVisibleRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        
        let rendered = renderedSize
        let centerX = rendered.width / 2 - offset.width
        let centerY = rendered.height / 2 - offset.height
        let visibleX = centerX - (canvasSize / 2)
        let visibleY = centerY - (canvasSize / 2)
        
        let normalizedW = canvasSize / rendered.width
        let normalizedH = canvasSize / rendered.height
        let normalizedX = max(0, min(1 - normalizedW, visibleX / rendered.width))
        let normalizedY = max(0, min(1 - normalizedH, visibleY / rendered.height))
        
        localVisibleRect = CGRect(x: normalizedX, y: normalizedY, width: normalizedW, height: normalizedH)
    }
}
