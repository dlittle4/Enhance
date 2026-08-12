import SwiftUI

struct EnhanceButtonPressAnimationModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.90 : 1.0)
            .brightness(isPressed ? 0.15 : 0)
            .opacity(1.0)
            .animation(Motion.press, value: isPressed)
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

/// A ButtonStyle that provides the same press animation as
/// `enhanceButtonAnimation()` but works with PhotosPicker and
/// other button types that swallow DragGesture.
struct EnhancePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .brightness(configuration.isPressed ? 0.15 : 0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

public extension View {
    func enhanceButtonAnimation() -> some View {
        self.modifier(EnhanceButtonPressAnimationModifier())
    }
}
