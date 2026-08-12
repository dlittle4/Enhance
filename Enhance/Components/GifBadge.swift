import SwiftUI

// Reusable badge to indicate GIF media type
struct GifBadge: View {
    var body: some View {
        Text("GIF")
            .font(.silkscreenCaption)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.segmentSelected.opacity(0.8))
            )
            .padding(6)
    }
}

// Preview for the component
struct GifBadge_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
                .frame(width: 150, height: 150)
            
            GifBadge()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .previewLayout(.sizeThatFits)
    }
} 
