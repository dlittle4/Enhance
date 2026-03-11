import SwiftUI

@main
struct EnhanceApp: App {
    @StateObject private var photoManager = PhotoManager()
    
    init() {
        FontRegistration.registerCustomFonts()
        
        let fontName = "Silkscreen-Regular"
        UILabel.appearance().font = UIFont(name: fontName, size: 14)
        UITextField.appearance().font = UIFont(name: fontName, size: 14)
        UITextView.appearance().font = UIFont(name: fontName, size: 14)
    }
    
    var body: some Scene {
        WindowGroup {
            GalleryView()
                .environment(\.font, .silkscreenBody)
                .environmentObject(photoManager)
        }
    }
}
