import Testing
import Vision
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

    /// BIG HEAD over every photo in `EnhanceTests/Fixtures`, with the face data Vision found.
    ///
    /// The showcase corpus cannot reach the contour branch — see that folder's README — so this
    /// is the only test that exercises it. It renders rather than asserts, and reports the
    /// contour point count and landmark quality per face, because when a head region comes out
    /// wrong the first question is always whether the contour path ran at all or the ellipse
    /// fallback did.
    @Test func bigHead_onFixturePhotos() async throws {
        let fixtures = Bundle(for: BundleToken.self).urls(forResourcesWithExtension: nil, subdirectory: nil) ?? []
        let photos = fixtures.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix("showcase") }
        guard !photos.isEmpty else { return }

        var report = ["photo,faces,contourPoints,quality,subjectFound,instanceIndex,instances"]

        for url in photos.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data), let cg = image.cgImage else { continue }
            let name = url.deletingPathExtension().lastPathComponent

            let mask = try? SubjectSegmentationService().subjectMaskOrThrow(for: image)
            let faces = await FaceDetectionService().detectFaces(in: image)
            let f = faces.first
            var reportIndex = -1
            var instanceCount = 0
            defer { report.append("\(name),\(faces.count),\(f?.faceContourPoints.count ?? 0),\(f.map { "\($0.landmarkQuality)" } ?? "none"),\((mask ?? nil) != nil),\(reportIndex),\(instanceCount)") }

            guard let face = f else { continue }
            // Per-person silhouette, which is what the editor now passes. Rendering the shared
            // union here would exercise a path the app no longer takes.
            let instanceService = SubjectSegmentationService()
            let perFace = (try? instanceService.instanceMask(for: image, containing: face.faceCenter)) ?? nil
            // 0 means the lookup hit background and fell back to the union of everyone — the
            // thing that would enlarge every head in a group photo.
            reportIndex = instanceService.lastInstanceIndex
            instanceCount = instanceService.lastInstanceCount
            guard let mask = perFace ?? (mask ?? nil) else { continue }
            let source = CIImage(cgImage: cg)
            // `isCrowded` follows the real rule the editor uses, so the render exercises whichever
            // region model this photo would actually get.
            // All faces, so the render exercises the layered pass rather than a single head —
            // the overlap ordering only exists when the effect can see everyone.
            let effect = BigHeadEffect(intensity: 0.9, size: 0.5, mask: mask)
            let gif = writeGIF(frameCount: 8) { i, p in
                effect.apply(to: source, face: face, progress: p, frameIndex: i)
                    .cropped(to: source.extent)
            }
            if let gif { Attachment.record(gif, named: "fixture-\(name)-bighead.gif") }
        }

        Attachment.record(Data(report.joined(separator: "\n").utf8), named: "fixture-faces.csv")
    }

    /// BIG HEAD on a **human** face, where Vision returns a real contour and the hybrid head
    /// region is actually exercised. The cat above goes through the animal path, whose contour
    /// comes from body-pose joints, so it still falls back to the ellipse — which is exactly the
    /// split worth seeing side by side.
    @Test func bigHead_onAHumanFace() async throws {
        guard let image = UIImage(named: "showcase-3"), let cg = image.cgImage else { return }
        let source = CIImage(cgImage: cg)

        let mask = try SubjectSegmentationService().subjectMaskOrThrow(for: image)
        let faces = await FaceDetectionService().detectFaces(in: image)

        var report = ["face,contourPoints,quality"]
        for (i, f) in faces.enumerated() {
            report.append("\(i),\(f.faceContourPoints.count),\(f.landmarkQuality)")
        }
        Attachment.record(Data(report.joined(separator: "\n").utf8), named: "bighead-faces.csv")

        guard let face = faces.first else { return }
        let effect = BigHeadEffect(intensity: 0.8, size: 0.5, mask: mask)
        let data = writeGIF(frameCount: 8) { i, p in
            effect.apply(to: source, face: face, progress: p, frameIndex: i)
                .cropped(to: source.extent)
        }
        if let data { Attachment.record(data, named: "bighead-human.gif") }
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

    // MARK: - Stage 0 spike: VNGeneratePersonInstanceMaskRequest on the corpus

    /// **The gate for the person-mask rebuild (plan Stage 0).** Runs the person-instance
    /// request RAW — no service abstraction, deliberately, so the data is seen before any API
    /// shape is baked in — over every fixture photo, and reports:
    ///
    /// - how many person instances Vision returns (the foreground request returned ONE for
    ///   every group; this request is the reason to believe groups are separable at all),
    /// - which instance label sits at each detected face's centre (0 = miss),
    /// - a cutout render per instance and a tinted composite per photo, because edge quality
    ///   at hair and hats is a looking question,
    /// - cold vs warm request timing.
    ///
    /// The label lookup uses ORIENTED dimensions — the same fix `instanceIndex` needed, kept
    /// here in spike form because a wrong-orientation spike would mis-gate the whole feature.
    @Test func personRequestSpike_measuresTheCorpus() async throws {
        let fixtures = Bundle(for: BundleToken.self).urls(forResourcesWithExtension: nil, subdirectory: nil) ?? []
        let photos = fixtures
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix("showcase") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !photos.isEmpty else { return }

        var report = ["photo,detectedFaces,personInstances,labelsAtFaceCentres,coldMs,warmMs"]
        let tints: [CIColor] = [
            CIColor(red: 1, green: 0.2, blue: 0.2), CIColor(red: 0.2, green: 0.9, blue: 0.3),
            CIColor(red: 0.25, green: 0.5, blue: 1), CIColor(red: 1, green: 0.9, blue: 0.2),
            CIColor(red: 1, green: 0.4, blue: 0.9), CIColor(red: 0.3, green: 0.95, blue: 0.9)
        ]

        for url in photos {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data), let cgImage = image.cgImage else { continue }
            // Async, so it cannot live inside the autoreleasepool below.
            let faces = await FaceDetectionService().detectFaces(in: image)

          try autoreleasepool {
            let name = url.deletingPathExtension().lastPathComponent
            let fullSource = CIImage(cgImage: cgImage)
            // Attachments render at a capped size — a full-res PNG of a 24MP fixture is the
            // exact per-face-bitmap memory failure of constraint 6, relocated into the test.
            // The request itself still runs on the full-resolution image.
            let attachScale = min(1, 1200 / max(fullSource.extent.width, fullSource.extent.height))
            let source = attachScale < 1
                ? fullSource.transformed(by: CGAffineTransform(scaleX: attachScale, y: attachScale))
                : fullSource

            let orientation = Self.visionOrientation(from: image)
            let orientedSize: CGSize
            switch orientation {
            case .left, .right, .leftMirrored, .rightMirrored:
                orientedSize = CGSize(width: cgImage.height, height: cgImage.width)
            default:
                orientedSize = CGSize(width: cgImage.width, height: cgImage.height)
            }

            func runRequest() throws -> (VNInstanceMaskObservation?, VNImageRequestHandler, Double) {
                let request = VNGeneratePersonInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                let t0 = CFAbsoluteTimeGetCurrent()
                try handler.perform([request])
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                return (request.results?.first, handler, ms)
            }

            // Cold then warm: the first fixture pays the model load once for the whole test,
            // so per-photo cold/warm still shows the request's own cost.
            let (obs, handler, coldMs) = try runRequest()
            let (_, _, warmMs) = try runRequest()

            guard let obs else {
                report.append("\(name),\(faces.count),0,,\(Int(coldMs)),\(Int(warmMs))")
                return
            }

            // Label under each face centre, read straight from the instance buffer.
            let labels = faces.map { face -> String in
                let idx = Self.spikeInstanceIndex(
                    at: face.faceCenter, in: obs.instanceMask, imageSize: orientedSize
                )
                return String(idx)
            }.joined(separator: "|")
            report.append("\(name),\(faces.count),\(obs.allInstances.count),\(labels),\(Int(coldMs)),\(Int(warmMs))")

            // Per-instance cutouts, and one composite with every instance tinted differently.
            var composite = source.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0, kCIInputBrightnessKey: -0.2
            ])
            for instance in obs.allInstances.sorted() {
                guard let buffer = try? obs.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instance), from: handler
                ) else { continue }
                var mask = CIImage(cvPixelBuffer: buffer)
                if mask.extent.size != source.extent.size {
                    mask = mask.transformed(by: CGAffineTransform(
                        scaleX: source.extent.width / mask.extent.width,
                        y: source.extent.height / mask.extent.height
                    ))
                }
                let cutout = source.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0))
                        .cropped(to: source.extent),
                    kCIInputMaskImageKey: mask
                ])
                if let cg = ctx.createCGImage(cutout, from: source.extent) {
                    let rep = UIImage(cgImage: cg)
                    if let png = rep.pngData() {
                        Attachment.record(png, named: "person-\(name)-instance\(instance).png")
                    }
                }

                let tint = tints[(instance - 1) % tints.count]
                let tinted = source.applyingFilter("CIColorMonochrome", parameters: [
                    kCIInputColorKey: tint, kCIInputIntensityKey: 0.9
                ])
                composite = tinted.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: composite,
                    kCIInputMaskImageKey: mask
                ])
            }
            if let cg = ctx.createCGImage(composite.cropped(to: source.extent), from: source.extent),
               let png = UIImage(cgImage: cg).pngData() {
                Attachment.record(png, named: "person-\(name)-composite.png")
            }
          }
        }

        Attachment.record(Data(report.joined(separator: "\n").utf8), named: "person-spike.csv")
    }

    /// The oriented label-buffer read, spike-local so the spike bakes in no app API.
    private static func spikeInstanceIndex(
        at point: CGPoint, in buffer: CVPixelBuffer, imageSize: CGSize
    ) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0, imageSize.width > 0, imageSize.height > 0,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let nx = point.x / imageSize.width
        let ny = 1 - (point.y / imageSize.height)
        guard nx >= 0, nx < 1, ny >= 0, ny < 1 else { return 0 }
        let x = min(w - 1, max(0, Int(nx * CGFloat(w))))
        let y = min(h - 1, max(0, Int(ny * CGFloat(h))))
        return Int(base.assumingMemoryBound(to: UInt8.self)[y * CVPixelBufferGetBytesPerRow(buffer) + x])
    }

    private static func visionOrientation(from image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
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

/// Locates the test bundle so fixture photos can be read at runtime.
private final class BundleToken {}

#endif
