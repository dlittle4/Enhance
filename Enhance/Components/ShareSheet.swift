import SwiftUI
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {
    let gifData: Data

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "enhance_\(UUID().uuidString).gif"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try? gifData.write(to: fileURL)

        let itemProvider = NSItemProvider()
        itemProvider.registerFileRepresentation(
            forTypeIdentifier: UTType.gif.identifier,
            visibility: .all
        ) { completion in
            completion(fileURL, true, nil)
            return nil
        }

        let activityItem = GIFActivityItem(fileURL: fileURL, itemProvider: itemProvider)
        let controller = UIActivityViewController(
            activityItems: [activityItem],
            applicationActivities: nil
        )

        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.permittedArrowDirections = []
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Provides the GIF with proper type metadata so Messages, Mail, etc. can all receive it.
private final class GIFActivityItem: NSObject, UIActivityItemSource {
    let fileURL: URL
    let itemProvider: NSItemProvider

    init(fileURL: URL, itemProvider: NSItemProvider) {
        self.fileURL = fileURL
        self.itemProvider = itemProvider
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.gif.identifier
    }
}
