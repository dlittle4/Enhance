import Testing
import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Enhance

/// MP4 EXPORT: the frame schedule honours delays and loops, and a real GIF transcodes to a
/// playable movie of the expected length.
struct VideoExporterTests {

    /// A three-frame GIF with distinct delays.
    private func makeGIF(delays: [Double]) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, delays.count, nil)!
        for (i, delay) in delays.enumerated() {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
            let image = renderer.image { ctx in
                UIColor(hue: CGFloat(i) / CGFloat(delays.count), saturation: 1, brightness: 1, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            }
            let props: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay]
            ]
            CGImageDestinationAddImage(dest, image.cgImage!, props as CFDictionary)
        }
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    @Test func scheduleRepeatsTheLoopWithEachFrameDelay() {
        let gif = makeGIF(delays: [0.1, 0.2, 0.3])
        let source = CGImageSourceCreateWithData(gif as CFData, nil)!
        let plan = VideoExporter.schedule(source: source, count: 3, loops: 2)
        #expect(plan.map(\.index) == [0, 1, 2, 0, 1, 2])
        #expect(abs(VideoExporter.duration(of: plan) - 1.2) < 1e-6)
        #expect(VideoExporter.schedule(source: source, count: 3, loops: 0).count == 3)
    }

    @Test func exportsAPlayableMovieOfTheRightLength() async throws {
        let gif = makeGIF(delays: [0.1, 0.1, 0.1, 0.1])
        let url = try await VideoExporter.exportMP4(gifData: gif, loops: 3, bitrateMbps: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1.2) < 0.05, "duration \(duration.seconds)")

        // The renderer draws at the screen scale, so compare with the GIF's own frame rather
        // than the nominal 64.
        let source = CGImageSourceCreateWithData(gif as CFData, nil)!
        let frame = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks.first?.load(.naturalSize)
        #expect(size == CGSize(width: frame.width, height: frame.height))
    }

    @Test func rejectsGarbage() async {
        do {
            _ = try await VideoExporter.exportMP4(gifData: Data([1, 2, 3]), loops: 1, bitrateMbps: 2)
            #expect(Bool(false), "should have thrown")
        } catch {
            #expect(true)
        }
    }
}
