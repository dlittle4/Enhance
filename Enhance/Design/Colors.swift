import SwiftUI
import UIKit

/// The app's accent colour, defined once.
///
/// This value was previously written out in five places, in two different forms
/// (`Color(red: 96/255, green: 255/255, blue: 168/255)` and `Color(hex: 0x60FFA8)`),
/// plus a third in the `icon-check` asset's SVG fill. They all mean `#60FFA8`.
extension Color {
    /// Selection, active state, and confirm affordances throughout the editor.
    static let enhanceMint = Color(hex: 0x60FFA8)
}

extension UIColor {
    /// UIKit twin of `Color.enhanceMint`, for the UIKit-backed canvas overlays in
    /// `ImageCanvasView` where a `Color` can't be used.
    static let enhanceMint = UIColor(red: 96 / 255, green: 255 / 255, blue: 168 / 255, alpha: 1)
}
