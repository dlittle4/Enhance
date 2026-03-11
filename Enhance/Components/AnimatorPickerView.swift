import SwiftUI

struct AnimatorPickerView: View {
    @Binding var selectedType: AnimatorType
    
    var body: some View {
        VStack(spacing: AppConstants.Spacing.small) {
            Text("SELECT EFFECT")
                .font(.silkscreenCaption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, AppConstants.Spacing.xsmall)
            
            HStack(spacing: AppConstants.Spacing.small) {
                ForEach(AnimatorType.allCases) { effect in
                    Button {
                        withAnimation { selectedType = effect }
                    } label: {
                        Text(effect.rawValue)
                            .font(.silkscreenCaption)
                            .padding(.vertical, AppConstants.Spacing.small)
                            .padding(.horizontal, AppConstants.Spacing.grid)
                            .background(
                                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous)
                                    .fill(selectedType == effect ?
                                          Color.white.opacity(0.2) : Color.white.opacity(0.05))
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, AppConstants.Spacing.standard)
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
