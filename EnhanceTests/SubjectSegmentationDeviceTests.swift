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

    /// Renders BACKGROUND ONLY through the real feature path — the shipped effect, the shipped
    /// `BackgroundOnlyEffect` wrapper, the shipped GIF settings — so the look can be judged
    /// rather than argued about. §1g found the palettisation cost lands on background *banding*,
    /// so this deliberately pairs a colour-flattening effect (MONOTONE) against one that leaves
    /// a smooth gradient (MOTION BLUR) and one that distorts geometry (SWIRL), which is the case
    /// where the subject is sampled from an undistorted frame and could show a seam.
    @Test func backgroundOnly_rendersThroughTheRealEffectPath() async throws {
        let candidates: [(String, VisualEffectType)] = [
            ("monotone", .monotone),      // flattens — expected to survive palettisation best
            ("motionBlur", .motionBlur),  // smooth gradient — expected to band
            ("swirl", .swirl)             // geometric — the seam risk
        ]

        for imageName in ["showcase-7", "showcase-3"] {
            guard let image = UIImage(named: imageName) else { continue }
            let service = SubjectSegmentationService()
            guard let mask = try service.subjectMaskOrThrow(for: image) else { continue }

            for (label, type) in candidates {
                let base = type.effect(intensity: 0.7, options: EffectOptions())
                let wrapped = BackgroundOnlyEffect(wrapped: base, mask: mask)
                if let gif = effectGIF(image: image, effect: wrapped) {
                    Attachment.record(gif, named: "\(imageName)-\(label)-bgonly.gif")
                }
                // The same effect with no mask, as the control — this is what the card looks
                // like with the toggle off, and the pair is the only honest comparison.
                if let plain = effectGIF(image: image, effect: base) {
                    Attachment.record(plain, named: "\(imageName)-\(label)-plain.gif")
                }
            }
        }
    }

    /// The export path, end to end: real segmentation, the shipped `BackgroundOnlyEffect`, and
    /// `GIFGenerator` building its own `FrameGeometry`.
    ///
    /// This is the combination that shipped broken — the preview composited correctly while the
    /// exported GIF did not, because `GIFGenerator` was the only thing constructing a real
    /// geometry and nothing exercised it with a mask. Rendering through the generator rather
    /// than a hand-rolled frame loop is the whole point of this case.
    @Test func backgroundOnly_survivesTheRealExportPath() async throws {
        guard let image = UIImage(named: "showcase-7") else { return }
        let service = SubjectSegmentationService()
        guard let mask = try service.subjectMaskOrThrow(for: image) else { return }

        let effect = BackgroundOnlyEffect(wrapped: MonotoneEffect(intensity: 1.0), mask: mask)
        let data = GIFGenerator().generateGIF(
            from: image, currentScale: 1.6,
            visibleRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            animator: ZoomInAnimator(),
            visualEffects: [effect]
        )
        if let data {
            Attachment.record(data, named: "export-path-bgonly.gif")
        }
        #expect(data != nil)
    }

    /// BITMAP at three cell sizes, and BIG HEAD at two strengths.
    ///
    /// BITMAP's whole claim is that the midtones resolve into a *crosshatch* rather than noise,
    /// which is a property of the matrix and only visible at the right cell size — hence three.
    @Test func bigHeadAndBitmap_render() async throws {
        guard let image = UIImage(named: "showcase-7"), let cg = image.cgImage else { return }
        let source = CIImage(cgImage: cg)

        // Contrast is the row added after the first render read muddy, so it is what varies.
        for (label, contrast) in [("flat", 0.15), ("mid", 0.5), ("hard", 0.95)] {
            let effect = BitmapEffect(intensity: 0.6, size: 0.45, contrast: contrast, stops: .default)
            if let data = effectGIF(image: image, effect: effect) {
                Attachment.record(data, named: "bitmap-\(label).gif")
            }
        }

        let service = SubjectSegmentationService()
        let mask = try service.subjectMaskOrThrow(for: image)
        let faces = await FaceDetectionService().detectFaces(in: image)
        guard let face = faces.first else { return }
        for (label, intensity) in [("gentle", 0.45), ("strong", 0.95)] {
            let effect = BigHeadEffect(intensity: intensity, size: 0.5, mask: mask)
            let data = writeGIF(frameCount: 8) { i, p in
                effect.apply(to: source, face: face, progress: p, frameIndex: i)
                    .cropped(to: source.extent)
            }
            if let data { Attachment.record(data, named: "bighead-\(label).gif") }
        }
    }

    /// ECHO — outlines of the subject radiating outward. Rendered at three spreads because the
    /// whole question is whether the rings read as emanation or as a registration error, and
    /// that depends almost entirely on how far apart they sit.
    @Test func subjectEcho_rendersRadiatingOutlines() async throws {
        for imageName in ["showcase-7", "showcase-3"] {
            guard let image = UIImage(named: imageName), let cg = image.cgImage else { continue }
            let service = SubjectSegmentationService()
            guard let mask = try service.subjectMaskOrThrow(for: image) else { continue }

            let source = CIImage(cgImage: cg)
            for (label, spread, colour) in [
                ("tight", 0.25, LaserColor.red),
                ("wide", 0.7, LaserColor.red),
                ("wide-white", 0.7, LaserColor.allCases.last ?? .red)
            ] {
                let effect = SubjectEchoEffect(
                    intensity: 0.7, spread: spread, color: colour, mask: mask
                )
                if let data = effectGIF(image: image, effect: effect) {
                    Attachment.record(data, named: "echo-\(imageName)-\(label).gif")
                }
                _ = source
            }
        }
    }

    /// ANIME with the real silhouette against ANIME with its original elliptical cutout.
    /// The pair is the point: the upgrade is only worth having if the difference is visible.
    @Test func animeBackground_realMaskVersusEllipse() async throws {
        guard let image = UIImage(named: "showcase-7"), let cg = image.cgImage else { return }
        let service = SubjectSegmentationService()
        let mask = try service.subjectMaskOrThrow(for: image)

        // A face is required to centre the burst; the cat's head is what detection finds here.
        let faces = await FaceDetectionService().detectFaces(in: image)
        guard let face = faces.first else { return }

        let source = CIImage(cgImage: cg)
        for (label, effect) in [
            ("ellipse", AnimeBackgroundEffect(intensity: 0.6, lineDensity: 0.5)),
            ("silhouette", AnimeBackgroundEffect(intensity: 0.6, lineDensity: 0.5, subjectMask: mask))
        ] {
            let data = writeGIF(frameCount: 8) { i, p in
                effect.apply(to: source, face: face, progress: p, frameIndex: i)
                    .cropped(to: source.extent)
            }
            if let data { Attachment.record(data, named: "anime-\(label).gif") }
        }
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

    /// Runs a `VisualEffect` over a zooming frame sequence and writes the app's GIF format,
    /// so what comes out is what the feature actually produces.
    ///
    /// **The geometry has to describe the zoom this method applies.** An earlier version passed
    /// `.identity` while zooming the content itself, and the render showed the mask staying put
    /// while the subject grew past it — the cat's ears and paws taking the background treatment.
    /// That was this harness lying to the effect, not the effect being wrong, but it is a
    /// faithful picture of what a wrong `FrameGeometry` produces, which is why
    /// `SubjectMaskCompositor` documents it as the failure to watch for.
    ///
    /// `contentRect` is the source's extent under the same transform the loop applies, which
    /// is exactly what `GIFGenerator` computes for the real pipeline.
    private func effectGIF(image: UIImage, effect: VisualEffect) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let source = CIImage(cgImage: cg)
        let c = CGPoint(x: source.extent.midX, y: source.extent.midY)

        return writeGIF(frameCount: 8) { i, p in
            let zoom = 1.0 + 0.35 * p
            let t = CGAffineTransform(translationX: c.x, y: c.y)
                .scaledBy(x: zoom, y: zoom)
                .translatedBy(x: -c.x, y: -c.y)
            let frame = source.transformed(by: t).cropped(to: source.extent)
            // The content rect this loop actually draws: the source scaled about its centre,
            // which is where `contentRect` has to point for the mask to land on the subject.
            let geometry = FrameGeometry(
                scale: zoom,
                contentOrigin: CGPoint(x: c.x * (1 - zoom), y: c.y * (1 - zoom)),
                contentRect: source.extent.applying(t)
            )
            return effect.apply(to: frame, progress: p, frameIndex: i,
                                viewportCenter: nil, geometry: geometry)
                .cropped(to: source.extent)
        }
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

        return writeGIF(frameCount: 8) { _, p in
            let zoom = 1.0 + 0.35 * p
            let c = CGPoint(x: source.extent.midX, y: source.extent.midY)
            let t = CGAffineTransform(translationX: c.x, y: c.y)
                .scaledBy(x: zoom, y: zoom)
                .translatedBy(x: -c.x, y: -c.y)
            return composite.transformed(by: t).cropped(to: source.extent)
        }
    }

    /// The app's GIF settings — `CGImageDestination` with one global colour map, matching
    /// `GIFGenerator.swift:128-141`. Shared so every attachment in this file is palettised the
    /// same way the export is; an approximation here would hide the banding §1g found.
    private func writeGIF(frameCount: Int, frame: (Int, CGFloat) -> CIImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frameCount, nil
        ) else { return nil }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,
                kCGImagePropertyGIFHasGlobalColorMap as String: true
            ]
        ] as CFDictionary)

        for i in 0..<frameCount {
            let p = CGFloat(i) / CGFloat(max(1, frameCount - 1))
            let image = frame(i, p)
            guard let out = ctx.createCGImage(image, from: image.extent) else { continue }
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
