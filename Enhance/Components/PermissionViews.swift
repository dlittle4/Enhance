import SwiftUI
import Photos

// Permission explanation sheet - reusable component for explaining why the app needs permissions
struct PermissionExplanationSheet: View {
    var requestAction: () -> Void
    var title: String = "Photo Library Access"
    var icon: String = "photo.on.rectangle.angled"
    var explanations: [(icon: String, title: String, description: String)] = [
        (icon: "sparkles", title: "Create Amazing GIFs", description: "Transform your photos into dynamic, animated GIFs with zoom effects"),
        (icon: "photo.stack", title: "Browse Recent Photos", description: "Easily access your recent photos directly in the app"),
        (icon: "lock.shield", title: "Privacy Focused", description: "Your photos never leave your device and are not shared with any third parties")
    ]
    var allowButtonText: String = "Allow Access"
    var cancelButtonText: String = "Not Now"
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.silkscreenTitle)
                    .foregroundColor(.white)
            }
            .padding(.top, 40)
            
            // Explanation text
            VStack(alignment:.leading, spacing: 24) {
                ForEach(explanations, id: \.title) { explanation in
                    explanationRow(
                        icon: explanation.icon,
                        title: explanation.title,
                        description: explanation.description
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 16) {
                AppButton(
                    text: allowButtonText,
                    action: requestAction,
                    fullWidth: true
                )
                
                AppButton(
                    text: cancelButtonText,
                    action: { dismiss() },
                    fullWidth: true,
                    noBackground: true
//                    useGradientBackground: false
                   
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }
    
    private func explanationRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.silkscreenBody)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// View shown when permissions are denied - reusable across different permission types
struct PermissionDeniedView: View {
    var icon: String = "exclamationmark.lock.fill"
    var title: String = "Photos Access Denied"
    var message: String = "We need access to your photos to display them in the gallery. Please enable photo access in Settings."
    var buttonText: String = "Open Settings"
    var buttonColor: Color = Color.blue
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text(title)
                .font(.silkscreenHeadline)
                .padding(.top, 8)
            
            Text(message)
                .font(.silkscreenBody)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            // Custom button with the provided color
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text(buttonText)
                    .font(.silkscreenButton)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(buttonColor)
                    .cornerRadius(8)
            }
            .enhanceButtonAnimation()
            .padding(.top, 16)
        }
        .padding(32)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// Preview for the permission components
struct PermissionViews_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview the explanation sheet
            PermissionExplanationSheet(requestAction: {})
                .previewDisplayName("Permission Explanation")
            
            // Preview the denied view
            PermissionDeniedView()
                .background(Color.black.opacity(0.7))
                .previewDisplayName("Permission Denied")
            
            // Preview customized version
            PermissionDeniedView(
                icon: "mic.slash",
                title: "Microphone Access Denied",
                message: "We need microphone access to record audio. Please enable microphone access in Settings.",
                buttonText: "Go to Settings",
                buttonColor: Color.red
            )
            .background(Color.black.opacity(0.7))
            .previewDisplayName("Custom Permission Denied")
        }
    }
} 
