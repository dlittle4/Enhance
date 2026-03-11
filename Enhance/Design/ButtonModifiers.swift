import SwiftUI

struct EnhanceButtonPressAnimationModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.90 : 1.0)
            .brightness(isPressed ? 0.15 : 0)
            .opacity(1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        isPressed = true
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

public extension View {
    func enhanceButtonAnimation() -> some View {
        self.modifier(EnhanceButtonPressAnimationModifier())
    }
}
