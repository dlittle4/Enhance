import SwiftUI

@main
struct EnhanceApp: App {
    @StateObject private var photoManager = PhotoManager()
    
    init() {
        // The adopted experiment profile *(user's call, 2026-08-26)*: these flags default ON
        // for a fresh install. Registration-domain defaults, so an explicit toggle in
        // GENERAL SETTINGS still wins, `FeatureFlags`' getters and every `@AppStorage` both
        // see them, and graduating or killing an experiment stays a one-line deletion here.
        UserDefaults.standard.register(defaults: [
            FeatureFlags.zoomOptionalKey: true,
            FeatureFlags.staticGradientKey: true,
            FeatureFlags.ditherGradientKey: true,
            FeatureFlags.faceMarkersReticleKey: true,
            FeatureFlags.faceMarkersScanlineKey: true,
            FeatureFlags.motionEntranceKey: true,
            FeatureFlags.motionCategorySwitchKey: true,
            FeatureFlags.motionTabScaleKey: true,
            FeatureFlags.motionTilePressKey: true,
            FeatureFlags.motionSharedZoomKey: true,
            FeatureFlags.motionSaveRevealKey: true,
            FeatureFlags.cameraCaptureKey: true,
            FeatureFlags.cameraRevealKey: true,
        ])

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
