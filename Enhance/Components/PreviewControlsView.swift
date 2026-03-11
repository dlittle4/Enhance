import SwiftUI

struct PreviewControlsView: View {
    @Binding var isPlaying: Bool
    @Binding var playbackSpeed: Double
    
    private let speeds: [Double] = [0.5, 1.0, 2.0]
    
    var body: some View {
        HStack(spacing: AppConstants.Spacing.grid) {
            playPauseButton
            
            Spacer()
            
            speedPicker
        }
        .padding(.horizontal, AppConstants.Spacing.standard)
        .padding(.vertical, AppConstants.Spacing.small)
    }
    
    private var playPauseButton: some View {
        Button {
            withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                isPlaying.toggle()
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.15))
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private var speedPicker: some View {
        HStack(spacing: AppConstants.Spacing.small) {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    withAnimation(.easeOut(duration: AppConstants.Animation.quick)) {
                        playbackSpeed = speed
                    }
                } label: {
                    Text(speedLabel(speed))
                        .font(.silkscreenCaption)
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard, style: .continuous)
                                .fill(playbackSpeed == speed ?
                                      Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
    
    private func speedLabel(_ speed: Double) -> String {
        if speed == 1.0 { return "1x" }
        if speed == 0.5 { return "0.5x" }
        return "\(Int(speed))x"
    }
}
