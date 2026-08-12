import SwiftUI

// Unified button component with app styling and press animation
struct AppButton: View {
    var text: String
    var action: () -> Void
    var isDisabled: Bool = false
    var fullWidth: Bool = true
    var useGradientBackground: Bool = true
    var noBackground: Bool = false // New option to disable background entirely
    
    // For text animation
    @State private var animatedText: String
    
    init(text: String, action: @escaping () -> Void, isDisabled: Bool = false, fullWidth: Bool = true, useGradientBackground: Bool = true, noBackground: Bool = false) {
        self.text = text
        self.action = action
        self.isDisabled = isDisabled
        self.fullWidth = fullWidth
        self.useGradientBackground = useGradientBackground
        self.noBackground = noBackground
        self._animatedText = State(initialValue: text)
    }
    
    var body: some View {
        Button(action: action) {
            Text(animatedText)
                .font(.silkscreenButton)
                .foregroundColor(Color(red: 0.09, green: 0.09, blue: 0.09))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: noBackground ? nil : 80)
                .background(
                    noBackground ? AnyView(Color.clear) :
                        useGradientBackground ? 
                            AnyView(SimpleGradientBackground()) : 
                            AnyView(Color.segmentSelected)
                )
                .clipShape(RoundedRectangle(cornerRadius: noBackground ? 0 : 100, style: .continuous))
        }
        .enhanceButtonAnimation()
        .disabled(isDisabled)
        .onChange(of: text) { _, newValue in
            withAnimation(Motion.press) {
                animatedText = newValue
            }
        }
    }
}

// Preview for the component
struct AppButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Standard button
            AppButton(text: "ENHANCE", action: {})
                .previewDisplayName("Standard")
            
            // Button without gradient
            AppButton(
                text: "NO GRADIENT",
                action: {},
                useGradientBackground: false
            )
                .previewDisplayName("No Gradient")
            
            // Button with fixed width
            AppButton(
                text: "FIXED WIDTH",
                action: {},
                fullWidth: false
            )
                .previewDisplayName("Fixed Width")
            
            // Button with no background
            AppButton(
                text: "TEXT ONLY",
                action: {},
                noBackground: true
            )
                .previewDisplayName("Text Only")
            
            // Disabled button state
            AppButton(
                text: "DISABLED",
                action: {},
                isDisabled: true
            )
                .previewDisplayName("Disabled")
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
} 
