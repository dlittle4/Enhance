import Testing
import UIKit
@testable import Enhance

/// Regression tests for the "gallery GIFs disappear after the app sits unused" bug.
///
/// The system purges `Library/Caches/` under storage pressure, preferentially for apps
/// that haven't been used recently. Recovery from that purge has to be robust: the fetch
/// must not hang, and the caches must rebuild themselves rather than staying broken.
struct GIFLibraryCacheTests {

    // MARK: - LeaveGuard

    /// PHImageManager may invoke a request handler more than once (a degraded delivery
    /// followed by a final one). An unguarded `leave()` per callback over-balances the
    /// group and traps at runtime.
    @Test func leaveGuard_repeatedLeaves_balanceGroupExactlyOnce() {
        let group = DispatchGroup()
        let token = LeaveGuard(group)

        token.leave()
        token.leave()
        token.leave()

        // If leave() ran more than once the group would already have trapped; if it never
        // ran, this wait times out. Success proves exactly one leave balanced the enter.
        #expect(group.wait(timeout: .now() + 1) == .success)
    }

    /// The inverse failure: a handler that never fires must leave the group outstanding,
    /// so the caller's timeout — not an early completion — decides when the fetch ends.
    @Test func leaveGuard_withoutLeave_keepsGroupOutstanding() {
        let group = DispatchGroup()
        _ = LeaveGuard(group)

        #expect(group.wait(timeout: .now() + 0.2) == .timedOut)
    }

    @Test func leaveGuard_concurrentLeaves_balanceGroupExactlyOnce() {
        let group = DispatchGroup()
        let token = LeaveGuard(group)

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            token.leave()
        }

        #expect(group.wait(timeout: .now() + 1) == .success)
    }

    // MARK: - ThumbnailCache

    /// `cleanupStaleCacheFiles` used to delete the Thumbs directory on every refresh,
    /// because it lives inside the swept directory and isn't a recognised GIF filename.
    /// The directory name is now exposed so the sweep can skip it.
    @Test func thumbnailCache_directoryName_isNotAGifFilename() {
        #expect(ThumbnailCache.directoryName == "Thumbs")
        #expect(!ThumbnailCache.directoryName.hasSuffix(".gif"))
    }

    /// The directory was previously created only in the singleton's `init`, so once the
    /// system (or the stale sweep) removed it, every later disk write failed silently
    /// through `try?` and the disk cache never recovered.
    @Test func thumbnailCache_afterDirectoryRemoved_writesRecover() throws {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let thumbsDir = caches.appendingPathComponent("MyGIFs/\(ThumbnailCache.directoryName)", isDirectory: true)

        // Simulate the purge.
        try? FileManager.default.removeItem(at: thumbsDir)
        #expect(!FileManager.default.fileExists(atPath: thumbsDir.path))

        let gifURL = URL(fileURLWithPath: "/tmp/regression-\(UUID().uuidString).gif")
        ThumbnailCache.shared.set(makeTestImage(), for: gifURL)

        // set() writes asynchronously on its io queue.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !FileManager.default.fileExists(atPath: thumbsDir.path) {
            usleep(50_000)
        }

        #expect(FileManager.default.fileExists(atPath: thumbsDir.path))
        #expect(ThumbnailCache.shared.get(for: gifURL) != nil)
    }

    // MARK: - Helpers

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
