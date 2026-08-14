import SwiftUI

// Reusable circle button component with app styling and press animation
struct CircleButton: View {
    var action: () -> Void
    var showBorder: Bool = false
    var contentOnly: Bool = false
    
    var body: some View {
        if contentOnly {
            // Just the visual content without the Button wrapper
            circleButtonContent
        } else {
            // Standard button with action
            Button(action: action) {
                circleButtonContent
            }
            .enhanceButtonAnimation()
        }
    }
    
    // Extracted button content so it can be reused
    private var circleButtonContent: some View {
        ZStack {
            // Base circle with animation background
            Circle()
                .foregroundColor(.clear)
                .overlay(
                    ButtonGradientBackground(cornerRadius: 30, borderWidth: 4, showsBorder: showBorder)
                        .clipShape(Circle())
                )

            // Optional animated border. The radius matches the 60pt frame's inscribed circle, so
            // the ring the border draws for itself *is* the circle — the old code masked a
            // rounded-rect ring with a circular one and got their intersection, which is four
            // arcs rather than a ring.
            if showBorder {
                ButtonGradientBorder(cornerRadius: 30, lineWidth: 4)
            }
            
            // "X" text on top
            Text("X")
                .font(.silkscreenHeadline)
                .foregroundColor(.white)
        }
        .frame(width: 62, height: 60)
    }
}

// Preview for the component
struct CircleButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Standard circle button
            CircleButton(action: {})
                .previewDisplayName("Default")
            
            // With border
            CircleButton(action: {}, showBorder: true)
                .previewDisplayName("With Border")
            
            // Content only mode (for use in other components)
            CircleButton(action: {}, contentOnly: true)
                .previewDisplayName("Content Only")
            
            // Rotated plus button variation
            CircleButton(action: {}, contentOnly: true)
                .rotationEffect(.degrees(45))
                .previewDisplayName("Plus Button (Rotated)")
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
} 
