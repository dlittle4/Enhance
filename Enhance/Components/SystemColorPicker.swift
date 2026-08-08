import SwiftUI
import UIKit

/// Presents the system colour picker (`UIColorPickerViewController`) directly.
///
/// Used instead of SwiftUI's `ColorPicker` because that renders a `UIColorWell`,
/// whose spectrum ring cannot be hidden or restyled — it clashed badly with the
/// editor's mint selection ring. Driving the picker ourselves means the swatch can
/// be an ordinary SwiftUI button styled like every other colour swatch in the app,
/// while still opening the real system colour wheel.
struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color
    var supportsAlpha: Bool = false

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = supportsAlpha
        picker.selectedColor = UIColor(color)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: SystemColorPicker

        init(parent: SystemColorPicker) {
            self.parent = parent
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            parent.color = Color(color)
        }
    }
}
