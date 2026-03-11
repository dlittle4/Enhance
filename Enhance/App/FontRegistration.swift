import CoreText
import Foundation

enum FontRegistration {
    static func registerCustomFonts() {
        let fontNames = ["Silkscreen-Regular", "Silkscreen-Bold"]
        
        for fontName in fontNames {
            if let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") {
                registerFont(at: url, name: fontName)
            } else if let url = Bundle.main.url(forResource: "Fonts/\(fontName)", withExtension: "ttf") {
                registerFont(at: url, name: fontName)
            }
        }
    }
    
    private static func registerFont(at url: URL, name: String) {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}
