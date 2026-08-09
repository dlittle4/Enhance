import SwiftUI

/// The backdrop of a ZOOM browse card: the user's photo framed the way that zoom type
/// leaves it.
///
/// The IMAGE and FACE cards apply a filter to show what their effect does. A zoom has no
/// filter to apply — the difference is entirely in the framing — so this card crops
/// instead. See `ZoomCardFraming` for which framing each type gets and why.
struct ZoomCardThumbnail: View {
    let image: UIImage
    let type: AnimatorType

    /// The framing the zoom travels to, from `EditorViewModel.zoomPreviewFraming`.
    let zoomScale: CGFloat
    let zoomCenter: CGPoint

    let size: CGFloat

    var body: some View {
        let transform = ZoomCardFraming.transform(
            fraction: ZoomCardFraming.fraction(for: type),
            zoomScale: zoomScale,
            zoomCenter: zoomCenter,
            imageSize: image.size,
            cardSize: size
        )

        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .scaleEffect(transform.scale)
            .offset(transform.offset)
            .frame(width: size, height: size)
            .clipped()
    }
}
