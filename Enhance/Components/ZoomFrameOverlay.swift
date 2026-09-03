import SwiftUI

/// Minimap overlay that shows which region of the full image will be the GIF's focus.
/// Appears in the bottom-left corner of the canvas when the user has zoomed in.
struct ZoomFrameOverlay: View {
    let image: UIImage
    let visibleRect: CGRect
    let scale: CGFloat
    
    private let minimapSize: CGFloat = 72
    
    private var isZoomedIn: Bool { scale > 1.05 }
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                minimapView
                    .opacity(isZoomedIn ? 1 : 0)
                    .scaleEffect(isZoomedIn ? 1 : 0.8)
                    .animation(.spring(response: AppConstants.Animation.standard, dampingFraction: 0.7), value: isZoomedIn)
                Spacer()
            }
        }
        .padding(AppConstants.Spacing.small)
        .allowsHitTesting(false)
    }
    
    private var minimapView: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: minimapSize, height: minimapSize)
                .clipped()
                .overlay(dimOverlay)
                .overlay(focusRectBorder)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }
    
    /// Dims the area outside the visible rect to highlight the focus region.
    private var dimOverlay: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: visibleRect.origin.x * geo.size.width,
                y: visibleRect.origin.y * geo.size.height,
                width: visibleRect.width * geo.size.width,
                height: visibleRect.height * geo.size.height
            )
            
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .reverseMask {
                    Rectangle()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
        }
    }
    
    /// Bright border around the focus rect inside the minimap.
    private var focusRectBorder: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: visibleRect.origin.x * geo.size.width,
                y: visibleRect.origin.y * geo.size.height,
                width: visibleRect.width * geo.size.width,
                height: visibleRect.height * geo.size.height
            )
            
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.tiny, style: .continuous)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

// MARK: - Reverse Mask Extension

extension View {
    @ViewBuilder
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}
