import SwiftUI

struct ImageCanvasView: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var visibleRect: CGRect
    var faceOverlays: [(id: UUID, rect: CGRect, isSelected: Bool)] = []
    var onFaceSelected: ((Int) -> Void)? = nil

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var localVisibleRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    private let canvasSize: CGFloat = 325
    private let mintGreen = Color(red: 96/255, green: 255/255, blue: 168/255)

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvasSize, height: canvasSize)
                .overlay(faceBoxesOverlay)
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
        .highPriorityGesture(dragGesture)
        .highPriorityGesture(magnificationGesture)
        .onChange(of: scale) { _, _ in calculateVisibleRect() }
        .onChange(of: localVisibleRect) { _, newRect in
            DispatchQueue.main.async { visibleRect = newRect }
        }
        .onAppear { calculateVisibleRect() }
    }
    
    /// Face boxes positioned relative to the image's fill-scaled dimensions.
    /// The overlay frame matches the full rendered image size (not the clipped canvas),
    /// so face boxes at the edges naturally extend beyond the visible canvas and get
    /// clipped by the parent. Uses highPriorityGesture for drag/magnification on the
    /// parent ZStack so taps on face boxes coexist with pinch/zoom/drag.
    @ViewBuilder
    private var faceBoxesOverlay: some View {
        if !faceOverlays.isEmpty {
            let fillScale = max(canvasSize / image.size.width, canvasSize / image.size.height)
            let renderedW = image.size.width * fillScale
            let renderedH = image.size.height * fillScale

            ZStack {
                ForEach(Array(faceOverlays.enumerated()), id: \.element.id) { index, face in
                    let bb = face.rect
                    let faceTopY = 1.0 - bb.origin.y - bb.height
                    let x = bb.origin.x * renderedW
                    let y = faceTopY * renderedH
                    let w = bb.width * renderedW
                    let h = bb.height * renderedH

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(face.isSelected ? mintGreen : mintGreen.opacity(0.6), lineWidth: face.isSelected ? 3 : 2)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(face.isSelected ? mintGreen.opacity(0.15) : mintGreen.opacity(0.05))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onFaceSelected?(index) }
                        .frame(width: w, height: h)
                        .position(x: x + w / 2, y: y + h / 2)
                }
            }
            .frame(width: renderedW, height: renderedH)
        }
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
