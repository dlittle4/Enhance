import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UIKit

/// MP4 EXPORT: turns a finished GIF into an H.264 movie.
///
/// Built from the GIF rather than from the generator's frames so every path that has a GIF —
/// a fresh render, an existing asset reopened from the gallery — can export without a second
/// render, and so the video is exactly what the preview showed. Each GIF frame becomes one
/// video frame at that frame's own delay; the loop is played `loops` times because a 2s movie
/// that plays once is a very different thing from a GIF that never stops.
enum VideoExporter {

    enum ExportError: Error {
        case unreadableGIF
        case noFrames
        case writerFailed(String)
    }

    /// Writes an `.mp4` beside the app's other temp files and returns its URL.
    ///
    /// - Parameters:
    ///   - loops: how many times the GIF's loop is laid down, ≥ 1.
    ///   - bitrateMbps: H.264 average bitrate. 600px square at 25fps is comfortable at 4–8.
    static func exportMP4(gifData: Data, loops: Int, bitrateMbps: Double) async throws -> URL {
        guard let source = CGImageSourceCreateWithData(gifData as CFData, nil) else {
            throw ExportError.unreadableGIF
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0, let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExportError.noFrames
        }

        // H.264 wants even dimensions; the generator's 600 square is, but an existing GIF from
        // anywhere might not be.
        let width = first.width - first.width % 2
        let height = first.height - first.height % 2

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("enhance_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(max(0.5, bitrateMbps) * 1_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw ExportError.writerFailed("cannot add input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        // Frame times on a millisecond clock — GIF delays are centiseconds, so this is exact.
        let timescale: CMTimeScale = 1000
        var timeMs: Int64 = 0
        let plan = schedule(source: source, count: count, loops: max(1, loops))

        for (index, delay) in plan {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let buffer = pixelBuffer(from: cgImage, width: width, height: height, pool: adaptor.pixelBufferPool) else {
                continue
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let time = CMTime(value: timeMs, timescale: timescale)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw ExportError.writerFailed(writer.error?.localizedDescription ?? "append")
            }
            timeMs += Int64((delay * 1000).rounded())
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: timeMs, timescale: timescale))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "finishWriting")
        }
        return url
    }

    /// The frames to write, in order, with each one's delay — the GIF's loop `loops` times.
    /// Pure, so the timing can be tested without writing a movie.
    static func schedule(source: CGImageSource, count: Int, loops: Int) -> [(index: Int, delay: TimeInterval)] {
        let delays = (0..<count).map { AnimatedGifView.frameDurationAtIndex($0, source: source) }
        var plan: [(Int, TimeInterval)] = []
        plan.reserveCapacity(count * loops)
        for _ in 0..<max(1, loops) {
            for i in 0..<count { plan.append((i, delays[i])) }
        }
        return plan
    }

    /// Total playing time a schedule adds up to.
    static func duration(of plan: [(index: Int, delay: TimeInterval)]) -> TimeInterval {
        plan.reduce(0) { $0 + $1.delay }
    }

    private static func pixelBuffer(from image: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
