import SwiftUI
import UniformTypeIdentifiers

struct ShareSheet: UIViewControllerRepresentable {
    /// GIF bytes to write out and share, or —
    var gifData: Data? = nil
    /// — an already-written file (MP4 EXPORT's movie) and its type.
    var fileURL: URL? = nil
    var fileType: UTType = .gif

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let fileURL: URL
        let type: UTType
        if let existing = self.fileURL {
            fileURL = existing
            type = fileType
        } else {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "enhance_\(UUID().uuidString).gif"
            fileURL = tempDir.appendingPathComponent(fileName)
            try? (gifData ?? Data()).write(to: fileURL)
            type = .gif
        }

        let itemProvider = NSItemProvider()
        itemProvider.registerFileRepresentation(
            forTypeIdentifier: type.identifier,
            visibility: .all
        ) { completion in
            completion(fileURL, true, nil)
            return nil
        }

        let activityItem = GIFActivityItem(fileURL: fileURL, itemProvider: itemProvider, type: type)
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
    let type: UTType

    init(fileURL: URL, itemProvider: NSItemProvider, type: UTType) {
        self.fileURL = fileURL
        self.itemProvider = itemProvider
        self.type = type
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
        type.identifier
    }
}
