import Foundation

/// An exported movie (MP4 EXPORT), wrapped so a `.sheet(item:)` can present it.
struct ExportedVideo: Identifiable {
    let url: URL
    var id: String { url.path }
}
