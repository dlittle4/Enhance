import CryptoKit
import Foundation
import Testing
import UIKit
@testable import Enhance

@Suite(.serialized)
struct SemanticHeadMaskTests {

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private enum FixtureVersion: String {
        case v1
        case v2
    }

    @Test func bundledModel_hasExpectedIdentity() throws {
        let url = Bundle.main.url(
            forResource: "selfie_multiclass_256x256", withExtension: "tflite",
            subdirectory: "Models"
        ) ?? Bundle.main.url(forResource: "selfie_multiclass_256x256", withExtension: "tflite")
        let modelURL = try #require(url)
        let data = try Data(contentsOf: modelURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0")
    }

    @Test func bundledFullRangeFaceModel_hasExpectedIdentity() throws {
        let url = Bundle.main.url(
            forResource: "blaze_face_full_range", withExtension: "tflite",
            subdirectory: "Models"
        ) ?? Bundle.main.url(forResource: "blaze_face_full_range", withExtension: "tflite")
        let modelURL = try #require(url)
        let data = try Data(contentsOf: modelURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "3698b18f063835bc609069ef052228fbe86d9c9a6dc8dcb7c7c2d69aed2b181b")
    }

    @Test func portraitExifFixtures_produceOneSemanticV2HeadEach() async throws {
        for name in ["IMG_0911", "IMG_0914"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "jpeg"))
            let data = try Data(contentsOf: url)
            let image = try #require(UIImage(data: data))
            let source = try #require(normalizedSource(from: image))
            #expect(source.extent.height > source.extent.width)

            let faces = await FaceDetectionService().detectFaces(
                in: image, includeFullRange: true
            )
            #expect(faces.count == 1, "\(name) should merge Vision and BlazeFace identity.")
            let person = await SubjectSegmentationService().personMasks(
                for: image, at: faces.map(\.faceCenter),
                radii: faces.map { $0.faceWidth * 0.5 }
            )
            let batch = await SemanticHeadMaskService().headMasksV2(
                for: image, faces: faces, personMasks: person
            )
            #expect(batch.masks.compactMap { $0 }.count == 1)
        }
    }

    @Test func distantEdgeFace_isRecoveredByFullRangeTiling() async throws {
        let name = "80888671014__DB387F63-6499-4937-9F4F-1FADDFDB02C7"
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "jpeg"))
        let image = try #require(UIImage(data: Data(contentsOf: url)))
        let source = try #require(normalizedSource(from: image))
        let faces = await FaceDetectionService().detectFaces(in: image, includeFullRange: true)

        #expect(faces.count == 2, "The bicycle helmet must not be accepted as a third face.")
        #expect(
            faces.contains { $0.faceCenter.x / source.extent.width > 0.75 },
            "The small person near the right edge must not disappear from a group photo."
        )
    }

    @Test func offCentreCloseupStillFindsItsSmallBackgroundFace() async throws {
        let name = "IMG_3228 Edited"
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "jpg"))
        let image = try #require(UIImage(data: Data(contentsOf: url)))
        let faces = await FaceDetectionService().detectFaces(in: image, includeFullRange: true)

        #expect(faces.count >= 2, "Adaptive tiling must retain the small background face.")
    }

    @Test func fullRangeDetector_meetsFixtureCoverageMinimums() async throws {
        let minimumFaces = [
            "6": 7,
            "80888671014__DB387F63-6499-4937-9F4F-1FADDFDB02C7": 2,
            "IMG_0168_SnapseedCopy": 10,
            "IMG_0558_SnapseedCopy": 5,
            "IMG_0624": 1,
            "IMG_0911": 1,
            "IMG_0914": 1,
            "IMG_0956": 2,
            "IMG_1250": 1,
            "IMG_2334": 3,
            "IMG_3228 Edited": 2
        ]
        let photoExtensions = Set(["jpg", "jpeg", "png", "heic"])
        let photos = (Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? [])
            .filter { photoExtensions.contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix("showcase-") }
            .filter { !$0.lastPathComponent.hasPrefix("AppIcon") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(photos.count >= 10)

        for url in photos {
            guard let image = UIImage(data: try Data(contentsOf: url)) else { continue }
            let faces = await FaceDetectionService().detectFaces(
                in: image, includeFullRange: true
            )
            let name = url.deletingPathExtension().lastPathComponent
            if let minimum = minimumFaces[name] {
                #expect(faces.count >= minimum, "\(name) lost a known test head.")
            }
        }
    }

    @Test func experimentalMode_roundTripsAndMigratesTheV1Switch() throws {
        let suite = try #require(UserDefaults(suiteName: "SemanticHeadMaskTests"))
        suite.removePersistentDomain(forName: "SemanticHeadMaskTests")
        let settings = SemanticHeadMaskSettings(defaults: suite)
        #expect(settings.mode == .legacy)
        settings.mode = .semanticV2
        #expect(SemanticHeadMaskSettings(defaults: suite).mode == .semanticV2)

        suite.removePersistentDomain(forName: "SemanticHeadMaskTests")
        suite.set(true, forKey: SemanticHeadMaskSettings.storageKey)
        #expect(SemanticHeadMaskSettings(defaults: suite).mode == .semanticV1)
        suite.removePersistentDomain(forName: "SemanticHeadMaskTests")
    }

    /// Runs the real face detector, MediaPipe model, semantic post-processing and batch BIG HEAD
    /// compositor over every local fixture photo. Mask shape remains a visual claim, so each
    /// successful row records a mask overlay and final render for inspection. V2 also has a
    /// structural gate: every distinct detector result must receive either a semantic matte or
    /// the conservative small-face fallback. A group member may not silently disappear.
    @Test func fixtureCorpus_rendersSemanticHeadComparisons() async throws {
        try await runFixtureCorpus(version: .v1)
    }

    @Test func fixtureCorpus_v2RendersEveryTestImage() async throws {
        try await runFixtureCorpus(version: .v2)
    }

    @Test func crowdedV2_ignoresSharedTranslucentPersonInstances() async throws {
        let url = try #require(Bundle.main.url(forResource: "IMG_0677", withExtension: "jpeg"))
        let image = try #require(UIImage(data: Data(contentsOf: url)))
        let source = try #require(normalizedSource(from: image))
        let faces = await FaceDetectionService().detectFaces(in: image, includeFullRange: true)
        #expect(faces.count > 3, "The shared-instance regression fixture must remain a group.")

        let service = SemanticHeadMaskService()
        let baseline = await service.headMasksV2(
            for: image, faces: faces, personMasks: Array(repeating: nil, count: faces.count)
        )
        // Reproduce the physical-device failure mode: Vision may return one soft person instance
        // for several face seeds even though each person needs an independent semantic owner.
        let shared = CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1))
            .cropped(to: source.extent)
        let withSharedInstance = await service.headMasksV2(
            for: image,
            faces: faces,
            personMasks: Array(repeating: Optional(shared), count: faces.count)
        )

        #expect(baseline.masks.count == withSharedInstance.masks.count)
        for index in faces.indices {
            let baselineMask = try #require(baseline.masks[index])
            let sharedMask = try #require(withSharedInstance.masks[index])
            let baselineStats = maskStats(baselineMask.mask)
            let sharedStats = maskStats(sharedMask.mask)
            #expect(abs(baselineStats.meanPercent - sharedStats.meanPercent) < 0.01)
            #expect(abs(baselineStats.activePercent - sharedStats.activePercent) < 0.01)
            #expect(
                maskValue(sharedMask.mask, at: faces[index].faceCenter) >= 0.95,
                "A crowded V2 owner must remain opaque through the detected face center."
            )
            for otherIndex in faces.indices where otherIndex != index {
                #expect(
                    maskValue(sharedMask.mask, at: faces[otherIndex].faceCenter) <= 0.05,
                    "A crowded V2 mask must not claim a neighbouring detected face center."
                )
            }
        }
    }

    private func runFixtureCorpus(version: FixtureVersion) async throws {
        let photoExtensions = Set(["jpg", "jpeg", "png", "heic"])
        let photos = (Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? [])
            .filter { photoExtensions.contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix("showcase-") }
            .filter { !$0.lastPathComponent.hasPrefix("AppIcon") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(photos.count >= 10, "The local BIG HEAD fixture corpus was not bundled.")

        let semanticService = SemanticHeadMaskService()
        let personService = SubjectSegmentationService()
        var report = [
            "version,photo,pixels,faces,semanticMasks,suppressed,personMs,semanticMs,face,status,centerX,centerY,faceW,faceH,maskPct,activePct,confidence,neckY,crownY"
        ]
        var totalFaces = 0
        var totalMasks = 0
        var totalSuppressed = 0

        for url in photos {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data),
                  let source = normalizedSource(from: image) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let faces = await FaceDetectionService().detectFaces(
                in: image, includeFullRange: version == .v2
            )
            totalFaces += faces.count

            let personStart = Date()
            let person = version == .v2
                ? await personService.personMasks(
                    for: image, at: faces.map(\.faceCenter),
                    radii: faces.map { $0.faceWidth * 0.5 }
                )
                : []
            let personMs = Int(Date().timeIntervalSince(personStart) * 1_000)
            let semanticStart = Date()
            let semantic: [SemanticHeadMask?]
            let suppressed: Set<UUID>
            switch version {
            case .v1:
                semantic = await semanticService.headMasks(for: image, faces: faces)
                suppressed = []
            case .v2:
                let batch = await semanticService.headMasksV2(
                    for: image, faces: faces, personMasks: person
                )
                semantic = batch.masks
                suppressed = batch.suppressedFaceIDs
            }
            let semanticMs = Int(Date().timeIntervalSince(semanticStart) * 1_000)
            let found = semantic.compactMap { $0 }.count
            totalMasks += found
            totalSuppressed += suppressed.count

            if version == .v2 {
                #expect(
                    found == faces.count,
                    "Semantic V2 skipped a detected face in \(name): \(found)/\(faces.count) masks."
                )
                #expect(
                    suppressed.isEmpty,
                    "Semantic V2 must composite every distinct group member in \(name)."
                )
            }

            if faces.isEmpty {
                report.append("\(version.rawValue),\(name),\(Int(source.extent.width))x\(Int(source.extent.height)),0,0,0,\(personMs),\(semanticMs),,NO_FACE,,,,,,,,,")
                continue
            }

            var entries: [BigHeadEffect.PerFaceMask] = []
            var aggregate: CIImage?
            for index in faces.indices {
                if suppressed.contains(faces[index].id) {
                    report.append(String(format: "%@,%@,%dx%d,%d,%d,%d,%d,%d,%d,SUPPRESSED,%.1f,%.1f,%.1f,%.1f,,,,,", version.rawValue, name, Int(source.extent.width), Int(source.extent.height), faces.count, found, suppressed.count, personMs, semanticMs, index, faces[index].faceCenter.x, faces[index].faceCenter.y, faces[index].faceWidth, faces[index].faceHeight))
                    continue
                }
                guard index < semantic.count, let head = semantic[index] else {
                    report.append(String(format: "%@,%@,%dx%d,%d,%d,%d,%d,%d,%d,MISSING,%.1f,%.1f,%.1f,%.1f,,,,,", version.rawValue, name, Int(source.extent.width), Int(source.extent.height), faces.count, found, suppressed.count, personMs, semanticMs, index, faces[index].faceCenter.x, faces[index].faceCenter.y, faces[index].faceWidth, faces[index].faceHeight))
                    continue
                }
                let stats = maskStats(head.mask)
                let status = head.confidence == 0 ? "FALLBACK" : "READY"
                report.append(String(
                    format: "%@,%@,%dx%d,%d,%d,%d,%d,%d,%d,%@,%.1f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%.3f",
                    version.rawValue, name, Int(source.extent.width), Int(source.extent.height),
                    faces.count, found, suppressed.count, personMs, semanticMs, index, status,
                    faces[index].faceCenter.x, faces[index].faceCenter.y,
                    faces[index].faceWidth, faces[index].faceHeight,
                    stats.meanPercent, stats.activePercent, head.confidence, head.neckNormY,
                    head.crownNormY
                ))
                entries.append(BigHeadEffect.PerFaceMask(
                    ownerID: faces[index].id,
                    normCenter: CGPoint(
                        x: faces[index].faceCenter.x / source.extent.width,
                        y: faces[index].faceCenter.y / source.extent.height
                    ),
                    mask: head.mask,
                    neckNormY: head.neckNormY,
                    crownNormY: head.crownNormY,
                    isSemanticHeadMask: true
                ))
                aggregate = aggregate.map {
                    head.mask.applyingFilter("CIMaximumCompositing", parameters: [
                        kCIInputBackgroundImageKey: $0
                    ])
                } ?? head.mask
            }

            guard !entries.isEmpty, let aggregate else { continue }
            let tint = CIImage(color: CIColor(red: 0.1, green: 1, blue: 0.25, alpha: 1))
                .cropped(to: source.extent)
            let overlay = tint.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: source,
                kCIInputMaskImageKey: aggregate
            ])
            if let jpeg = jpegData(overlay, maxSide: 1400) {
                Attachment.record(jpeg, named: "\(name)-semantic-\(version.rawValue)-mask.jpg")
            }

            // Preserve per-owner diagnostics for every group. A union overlay can look complete
            // while one matte has borrowed a neighbour; the individual layers make that
            // ownership error visible without changing the production pipeline.
            if version == .v2, faces.count > 1 {
                for (index, entry) in entries.enumerated() {
                    let ownerOverlay = tint.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: source,
                        kCIInputMaskImageKey: entry.mask
                    ])
                    if let jpeg = jpegData(ownerOverlay, maxSide: 1400) {
                        Attachment.record(
                            jpeg, named: "\(name)-semantic-v2-owner-\(index)-mask.jpg"
                        )
                    }
                }
            }

            var tuning = HeadMaskTuning.default
            tuning.stackedPass = true
            let effect = BigHeadEffect(
                intensity: 0.9, size: 0.5, mask: nil, perFace: entries,
                suppressedFaceIDs: suppressed, collisionSafe: version == .v2, tuning: tuning
            )
            let mid = effect.apply(
                to: source, faces: faces, progress: 0.55, frameIndex: 4
            ).cropped(to: source.extent)
            if let jpeg = jpegData(mid, maxSide: 1400) {
                Attachment.record(jpeg, named: "\(name)-semantic-\(version.rawValue)-mid.jpg")
            }
            let final = effect.apply(
                to: source, faces: faces, progress: 1, frameIndex: 7
            ).cropped(to: source.extent)
            if let jpeg = jpegData(final, maxSide: 1400) {
                Attachment.record(jpeg, named: "\(name)-semantic-\(version.rawValue)-final.jpg")
            }
        }

        report.append("summary,version=\(version.rawValue),photos=\(photos.count),faces=\(totalFaces),masks=\(totalMasks),suppressed=\(totalSuppressed)")
        let csv = report.joined(separator: "\n")
        print("SEMANTIC_\(version.rawValue.uppercased())_FIXTURE_REPORT\n\(csv)")
        Attachment.record(
            Data(csv.utf8), named: "semantic-\(version.rawValue)-fixture-report.csv"
        )

        #expect(totalFaces > 0, "Face detection found no faces in the fixture corpus.")
        #expect(totalMasks > 0, "Semantic \(version.rawValue) produced no head masks.")
    }

    private func normalizedSource(from image: UIImage) -> CIImage? {
        image.orientationAppliedCIImage()
    }

    private func maskStats(_ mask: CIImage) -> (meanPercent: Double, activePercent: Double) {
        let scale = min(1, 384 / max(mask.extent.width, mask.extent.height))
        let reduced = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = reduced.extent.integral
        let width = max(1, Int(bounds.width))
        let height = max(1, Int(bounds.height))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            reduced, toBitmap: &bytes, rowBytes: width * 4, bounds: bounds,
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var total = 0
        var active = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let value = Int(bytes[index])
            total += value
            if value >= 26 { active += 1 }
        }
        let pixels = Double(width * height)
        return (
            Double(total) / (pixels * 255) * 100,
            Double(active) / pixels * 100
        )
    }

    private func maskValue(_ mask: CIImage, at point: CGPoint) -> Double {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            mask, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: floor(point.x), y: floor(point.y), width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return Double(bytes[0]) / 255
    }

    private func jpegData(_ image: CIImage, maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(image.extent.width, image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = scaled.extent.integral
        guard let cg = context.createCGImage(scaled, from: bounds) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.88)
    }
}
