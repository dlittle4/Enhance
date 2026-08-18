import Testing
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit
@testable import Enhance

// Device-only. `VNGenerateForegroundInstanceMaskRequest` throws on the Simulator, so this
// whole file is compiled out there — CI runs on the Simulator and must stay green.
#if !targetEnvironment(simulator)

/// The §1g device pass: the one thing the spike could not answer.
///
/// Segmentation has been seen working on macOS (via `Tools/segmentation-spike.swift`) and seen
/// throwing on the Simulator, and has never run on iOS. This measures the real path on real
/// hardware and reports numbers that can be diffed against the macOS run, which is what turns
/// the 7-of-8 hit rate from indicative into real.
///
/// **It reports rather than asserts.** Only one thing is asserted — that Vision does not throw,
/// i.e. the capability exists at all. Coverage percentages are recorded as an attachment
/// instead of being pinned, because a threshold invented here would be a guess, and per
/// EFFECTS.md a green test cannot see a wrong-looking cutout anyway.
///
/// Results land in the `.xcresult` bundle on the Mac that ran the test. See ROADMAP §1g.
struct SubjectSegmentationDeviceTests {

    private static let corpus = (1...8).map { "showcase-\($0)" }

    private let ctx = CIContext(options: [.useSoftwareRenderer: false])

    /// Runs the real Vision path over the showcase corpus and attaches the measurements.
    @Test func devicePass_measuresTheRealVisionPath() async throws {
        var report: [String] = []
        report.append("device: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
        report.append("image,found,instances,subjectPct,backgroundPct,edgePct,edgePx,requestMs")

        var found = 0
        var attempted = 0

        for name in Self.corpus {
            guard let image = UIImage(named: name) else {
                report.append("\(name),MISSING_ASSET,,,,,,")
                continue
            }
            attempted += 1

            let service = SubjectSegmentationService()
            let start = Date()
            // Throwing here is the headline failure: it would mean iOS behaves like the
            // Simulator and the whole §2f family is unbuildable as designed.
            let mask = try service.subjectMaskOrThrow(for: image)
            let ms = Int(Date().timeIntervalSince(start) * 1000)

            guard let mask else {
                report.append("\(name),no,0,0,0,0,0,\(ms)")
                continue
            }
            found += 1

            let stats = coverage(of: mask)
            report.append(String(
                format: "%@,yes,1,%.1f,%.1f,%.2f,%d,%d",
                name, stats.subject, stats.background, stats.edge, stats.edgePx, ms
            ))

            // One cutout through the real export path, so the look can be judged rather than
            // inferred from percentages. Same composite the macOS spike used.
            if let gif = cutoutGIF(image: image, mask: mask) {
                Attachment.record(gif, named: "\(name)-cutout.gif")
            }
        }

        report.append("summary: \(found)/\(attempted) found a subject (macOS spike: 7/8)")
        Attachment.record(Data(report.joined(separator: "\n").utf8), named: "device-report.csv")

        #expect(attempted > 0, "No showcase assets were loadable from the test host bundle.")
    }

    // MARK: - Measurement

    private func coverage(of mask: CIImage) -> (subject: Double, background: Double, edge: Double, edgePx: Int) {
        guard let cg = ctx.createCGImage(mask, from: mask.extent) else { return (0, 0, 0, 0) }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h)
        guard let bctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return (0, 0, 0, 0) }
        bctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var solid = 0, empty = 0, partial = 0
        for v in buf {
            if v > 240 { solid += 1 } else if v < 15 { empty += 1 } else { partial += 1 }
        }
        let total = Double(w * h)
        guard total > 0 else { return (0, 0, 0, 0) }
        return (Double(solid) / total * 100, Double(empty) / total * 100,
                Double(partial) / total * 100, partial)
    }

    /// The naive cutout the spike used — subject held, background desaturated and blurred —
    /// pushed through the app's real GIF settings so palettisation is included.
    private func cutoutGIF(image: UIImage, mask: CIImage) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let source = CIImage(cgImage: cg)
        let background = source
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0])
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 8.0])
            .cropped(to: source.extent)
        let composite = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, 8, nil
        ) else { return nil }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,
                kCGImagePropertyGIFHasGlobalColorMap as String: true
            ]
        ] as CFDictionary)

        for i in 0..<8 {
            let p = CGFloat(i) / 7.0
            let zoom = 1.0 + 0.35 * p
            let c = CGPoint(x: source.extent.midX, y: source.extent.midY)
            let t = CGAffineTransform(translationX: c.x, y: c.y)
                .scaledBy(x: zoom, y: zoom)
                .translatedBy(x: -c.x, y: -c.y)
            let frame = composite.transformed(by: t).cropped(to: source.extent)
            guard let out = ctx.createCGImage(frame, from: frame.extent) else { continue }
            CGImageDestinationAddImage(dest, out, [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: 0.06,
                    kCGImagePropertyGIFHasGlobalColorMap as String: true
                ]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

#endif
