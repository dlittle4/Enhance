import SwiftUI
import CoreImage
import UIKit

/// A bench for dialling in BIG HEAD's mask against the real test corpus.
///
/// Same premise as the other labs: an ellipse size, a chin height and a feather cannot be
/// specified, only recognised. The photo strip carries the dev fixture corpus (bundled from
/// `Enhance/DevFixtures/`, gitignored), every knob is live against the **real** mask builder —
/// `BigHeadEffect.headMask` is the single source of truth the GIF path uses — and COPY
/// PARAMETERS hands back the Swift to paste into `HeadMaskTuning.default` once it looks right.
///
/// MASK mode tints each face's head mask a different colour over the photo, which is the
/// direct answer to "how are we detecting the face outline". RESULT mode runs the actual
/// batch API used by preview and GIF export, so group-photo judgements exercise the same
/// ownership and occlusion behaviour that ships.
///
/// **Scaffolding, and meant to be deleted** once the numbers graduate.
struct HeadMaskLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = HeadMaskTuningStore.shared
    @ObservedObject private var semanticSettings = SemanticHeadMaskSettings.shared

    private enum Mode: String, CaseIterable { case mask = "MASK", result = "RESULT" }

    @State private var mode: Mode = .mask
    @State private var fixtures: [URL] = []
    @State private var selectedFixture: URL?
    @State private var photo: UIImage?
    @State private var faces: [DetectedFace] = []
    @State private var subjectMask: CIImage?
    /// Per-person instance masks aligned with `faces` — the PERSON MASKS approach's input.
    @State private var personMasks: [CIImage?] = []
    @State private var semanticHeadMasks: [SemanticHeadMask?] = []
    @State private var semanticSuppressedFaceIDs: Set<UUID> = []
    @State private var overlay: UIImage?
    @State private var isPreparing = false
    @State private var statusNote: String?
    @State private var didCopy = false
    /// Intensity used by RESULT mode, so growth is judged at more than one strength.
    @State private var previewIntensity: Double = 0.9
    @State private var renderTask: Task<Void, Never>?
    @State private var manualHeadMode = false
    @State private var manualFaceIDs: [UUID] = []
    @State private var stageTimings = StageTimings()

    private let faceService = FaceDetectionService()
    private let segmentationService = SubjectSegmentationService()
    private let semanticService = SemanticHeadMaskService()
    private static let renderContext = CIContext(options: [.useSoftwareRenderer: false])
    private let labRegionBuilder = HeadRegionBuilder()

    private struct StageTimings {
        var detectionMs = 0
        var tileCount = 0
        var subjectMs = 0
        var personMs = 0
        var semanticMs = 0
        var renderMs = 0

        var label: String? {
            guard detectionMs + subjectMs + personMs + semanticMs + renderMs > 0 else {
                return nil
            }
            return "DETECT \(detectionMs)ms/\(tileCount)t · SUBJECT \(subjectMs)ms · "
                + "PERSON \(personMs)ms · HEAD \(semanticMs)ms · RENDER \(renderMs)ms"
        }
    }

    /// Distinct tints per face, matching the segmentation spike's convention.
    private static let tints: [CIColor] = [
        CIColor(red: 1, green: 0.25, blue: 0.25), CIColor(red: 0.25, green: 0.9, blue: 0.4),
        CIColor(red: 0.3, green: 0.55, blue: 1), CIColor(red: 1, green: 0.85, blue: 0.25),
        CIColor(red: 1, green: 0.45, blue: 0.9), CIColor(red: 0.35, green: 0.95, blue: 0.9)
    ]

    var body: some View {
        BottomSheet(isPresented: $isPresented, title: "HEAD MASK LAB", expandable: true) {
            VStack(spacing: 0) {
                // Pinned above the scroll view: the thing being judged must not move when you
                // reach for the control that changes it.
                preview
                    .padding(.horizontal, 16)

                fixtureStrip
                    .padding(.vertical, 10)

                divider

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        modeToggle
                        divider
                        approachToggles
                        if !semanticSettings.usesV2 {
                            divider
                            ellipseSliders
                                .disabled(store.tuning.useJawRegion)
                                .opacity(store.tuning.useJawRegion ? 0.35 : 1)
                            divider
                            chinSliders
                                .disabled(store.tuning.useJawRegion)
                                .opacity(store.tuning.useJawRegion ? 0.35 : 1)
                        }
                        divider
                        growthSliders
                        divider
                        actions
                    }
                    .padding(16)
                }
            }
        }
        .onAppear(perform: loadFixtures)
        .onChange(of: store.tuning) { _, _ in scheduleRender() }
        .onChange(of: semanticSettings.mode) { _, _ in
            if let selectedFixture { select(selectedFixture) }
        }
        .onChange(of: mode) { _, _ in scheduleRender() }
        .onChange(of: previewIntensity) { _, _ in scheduleRender() }
    }

    // MARK: - Preview

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.card).fill(Color.surfaceControl)
                if let overlay {
                    Image(uiImage: overlay)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.large))
                        .padding(6)
                } else if isPreparing {
                    ProgressView().tint(.enhanceMint)
                } else {
                    Text(statusNote ?? "PICK A PHOTO BELOW")
                        .font(.silkscreenCaption)
                        .foregroundColor(.textInactive)
                        .multilineTextAlignment(.center)
                        .padding(20)
                }
                if manualHeadMode, semanticSettings.usesV2 {
                    VStack {
                        HStack {
                            Text("TAP THE CENTRE OF EACH MISSED FACE / HEAD")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.surfacePrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.pill, style: .continuous).fill(Color.enhanceMint))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                }
                if let timing = stageTimings.label {
                    VStack {
                        Spacer()
                        Text(timing)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.small).fill(Color.black.opacity(0.72)))
                    }
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                addManualHead(at: tap.location, containerSize: proxy.size)
            })
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    private var fixtureStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fixtures, id: \.self) { url in
                    Button {
                        HapticService.selection()
                        select(url)
                    } label: {
                        thumbnail(for: url)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard)
                                    .stroke(selectedFixture == url ? Color.enhanceMint : .clear,
                                            lineWidth: 2)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 64)
    }

    private func thumbnail(for url: URL) -> some View {
        Group {
            if let thumb = Self.thumbnailCache[url] {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Color.surfaceControl
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.standard))
    }

    /// Tiny, loaded once — the strip must not decode 11 full photos to draw.
    private static var thumbnailCache: [URL: UIImage] = [:]

    // MARK: - Controls

    private var modeToggle: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    HapticService.selection()
                    mode = m
                } label: {
                    Text(m.rawValue)
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(mode == m ? .surfacePrimary : .textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.large)
                                .fill(mode == m ? Color.enhanceMint : Color.surfaceControl)
                        )
                }
            }
        }
    }

    private var approachToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("APPROACH")
            semanticModeSelector
            if semanticSettings.usesV2 {
                manualHeadControls
                Text("V2 selects person ownership, follows pose, fits the head outline, and stacks overlapping heads automatically.")
                    .font(.system(size: 10))
                    .foregroundColor(.textInactive)
            } else {
                labToggle("PERSON MASKS", isOn: $store.tuning.usePersonMasks,
                          hint: "per-person instance mask instead of the shared union")
                labToggle("JAW REGION", isOn: $store.tuning.useJawRegion,
                          hint: "bound below by traced facial landmarks; ellipse for animals")
                if store.tuning.useJawRegion {
                    labSlider("JAW DROP", value: $store.tuning.jawDrop, in: 0.0...0.4,
                              hint: "cut below the trace, × face height — 0 cuts on the trace")
                    labSlider("JAW FEATHER", value: $store.tuning.jawFeather, in: 0.01...0.3,
                              hint: "seam softness, × face width")
                    labSlider("JAW WIDTH", value: $store.tuning.jawWidth, in: 0.8...4.0,
                              hint: "side reach, × face width — how much hair and hat it admits")
                }
                labToggle("FOLLOW POSE", isOn: $store.tuning.followPose,
                          hint: "rotate with head roll; shift with yaw (ellipse mode)")
                if store.tuning.followPose {
                    labSlider("YAW SHIFT", value: $store.tuning.yawShift, in: 0.0...1.0,
                              hint: "push toward the back of a turned head, × face width at profile")
                }
                labToggle("STACKED PASS", isOn: $store.tuning.stackedPass,
                          hint: "groups: heads occlude instead of blurring — cut from the original, widest on top")
                labToggle("SILHOUETTE", isOn: $store.tuning.useSilhouette,
                          hint: "off = classic cutout: the feathered region alone, background and all")
                labToggle("AUTO FIT", isOn: $store.tuning.autoFit,
                          hint: "derive chin cut + ellipse from the silhouette: neck = narrowest row, crown = highest")
                labToggle("ACCURATE PERSON MATTE", isOn: Binding(
                    get: { store.tuning.unionSource == .personAccurate },
                    set: { store.tuning.unionSource = $0 ? .personAccurate : .foreground }
                ), hint: "person-segmentation .accurate — softer hair edges, people only")
                labToggle("PORTRAIT MATTE", isOn: Binding(
                    get: { store.tuning.unionSource == .portraitMatte },
                    set: { store.tuning.unionSource = $0 ? .portraitMatte : .foreground }
                ), hint: "the hair+skin mattes Portrait photos embed — best edges anywhere, when present")
            }
        }
    }

    private var semanticModeSelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("HEAD SOURCE").font(.silkscreenCaption).foregroundColor(.textPrimary)
            HStack(spacing: 6) {
                ForEach(SemanticHeadMaskSettings.Mode.allCases, id: \.rawValue) { mode in
                    Button {
                        HapticService.selection()
                        semanticSettings.mode = mode
                    } label: {
                        Text(mode.label)
                            .font(.silkscreenCaption)
                            .foregroundColor(
                                semanticSettings.mode == mode ? .surfacePrimary : .textPrimary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium).fill(
                                semanticSettings.mode == mode
                                    ? Color.enhanceMint : Color.surfaceControl
                            ))
                    }
                }
            }
            Text("V1 = semantic outline; V2 = more faces + stable owner + in-place growth")
                .font(.system(size: 10)).foregroundColor(.textInactive)
        }
    }

    private var manualHeadControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                HapticService.selection()
                manualHeadMode.toggle()
                if manualHeadMode { mode = .mask }
            } label: {
                Text(manualHeadMode ? "FINISH ADDING HEADS" : "TAP TO ADD MISSED HEADS")
                    .font(.silkscreenCaption)
                    .foregroundColor(manualHeadMode ? .surfacePrimary : .textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.medium).fill(
                        manualHeadMode ? Color.enhanceMint : Color.surfaceControl
                    ))
            }
            if !manualFaceIDs.isEmpty {
                Button {
                    HapticService.selection()
                    removeLastManualHead()
                } label: {
                    Text("UNDO ADDED HEAD (\(manualFaceIDs.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
            }
            Text("Lab only: tap a hat, profile, or turned head the detectors missed.")
                .font(.system(size: 10)).foregroundColor(.textInactive)
        }
    }

    private func labToggle(_ label: String, isOn: Binding<Bool>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(label).font(.silkscreenCaption).foregroundColor(.textPrimary)
            }
            .tint(.enhanceMint)
            Text(hint).font(.system(size: 10)).foregroundColor(.textInactive)
        }
    }

    private var ellipseSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ELLIPSE")
            labSlider("WIDTH", value: $store.tuning.ellipseWidth, in: 1.2...4.5,
                      hint: "× face width")
            labSlider("HEIGHT", value: $store.tuning.ellipseHeight, in: 1.2...4.5,
                      hint: "× face height")
            labSlider("CENTER Y", value: $store.tuning.centerYOffset, in: -0.5...1.0,
                      hint: "+ is up, × face height")
            labSlider("FEATHER", value: $store.tuning.feather, in: 0.02...1.0,
                      hint: "edge softness")
        }
    }

    private var chinSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("CHIN CUT")
            labSlider("HEIGHT", value: $store.tuning.chinCutOffset, in: -1.2...0.2,
                      hint: "0 = face centre, −0.5 = chin")
            labSlider("FADE", value: $store.tuning.chinFade, in: 0.02...1.0,
                      hint: "× face height")
        }
    }

    private var growthSliders: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("GROWTH (RESULT MODE)")
            labSlider("MAX", value: $store.tuning.growthMax, in: 0.2...2.0,
                      hint: "scale = 1 + i² × max")
            if !semanticSettings.usesV2 {
                labSlider("PIVOT Y", value: $store.tuning.pivotY, in: 0.0...0.6,
                          hint: "fraction up the ellipse")
            }
            labSlider("INTENSITY", value: $previewIntensity, in: 0.1...1.0,
                      hint: "preview only, not stored")
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !semanticSettings.usesV2 {
                Button {
                    UIPasteboard.general.string = swiftLiteral
                    didCopy = true
                    HapticService.selection()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                } label: {
                    Text(didCopy ? "COPIED ✓" : "COPY PARAMETERS")
                        .font(.silkscreenButtonLabel)
                        .foregroundColor(.surfacePrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.large).fill(Color.enhanceMint))
                }
            }
            Button {
                HapticService.selection()
                if semanticSettings.usesV2 {
                    store.tuning.growthMax = HeadMaskTuning.default.growthMax
                } else {
                    store.reset()
                }
            } label: {
                Text(semanticSettings.usesV2 ? "RESET MAX TO DEFAULT" : "RESET TO DEFAULT")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.large).fill(Color.surfaceControl))
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.silkscreenCaption).foregroundColor(.textInactive)
    }

    private func labSlider(
        _ label: String, value: Binding<Double>, in range: ClosedRange<Double>, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.silkscreenCaption).foregroundColor(.textPrimary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.silkscreenCaption).foregroundColor(.enhanceMint)
            }
            Slider(value: value, in: range).tint(.enhanceMint)
            Text(hint).font(.system(size: 10)).foregroundColor(.textInactive)
        }
    }

    private var swiftLiteral: String {
        let t = store.tuning
        return """
        HeadMaskTuning(
            ellipseWidth: \(String(format: "%.2f", t.ellipseWidth)),
            ellipseHeight: \(String(format: "%.2f", t.ellipseHeight)),
            centerYOffset: \(String(format: "%.2f", t.centerYOffset)),
            feather: \(String(format: "%.2f", t.feather)),
            chinCutOffset: \(String(format: "%.2f", t.chinCutOffset)),
            chinFade: \(String(format: "%.2f", t.chinFade)),
            growthMax: \(String(format: "%.2f", t.growthMax)),
            pivotY: \(String(format: "%.2f", t.pivotY))
        )
        """
    }

    // MARK: - Data

    private func loadFixtures() {
        guard fixtures.isEmpty else { return }
        let urls = (Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? [])
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        fixtures = urls
        if urls.isEmpty {
            statusNote = "NO DEV FIXTURES\nAdd photos to Enhance/DevFixtures/ and rebuild"
        }
        for url in urls where Self.thumbnailCache[url] == nil {
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                   kCGImageSourceThumbnailMaxPixelSize: 112,
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) {
                Self.thumbnailCache[url] = UIImage(cgImage: cg)
            }
        }
        if let first = urls.first { select(first) }
    }

    private func select(_ url: URL) {
        selectedFixture = url
        overlay = nil
        isPreparing = true
        statusNote = nil
        manualHeadMode = false
        manualFaceIDs = []
        stageTimings = StageTimings()
        Task {
            // Work from a ~1400px copy: masks are judged at screen size, and full-resolution
            // segmentation + per-tick rendering would make every slider drag a slideshow.
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceThumbnailMaxPixelSize: 1400,
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else {
                await MainActor.run { isPreparing = false; statusNote = "COULD NOT LOAD PHOTO" }
                return
            }
            let image = UIImage(cgImage: cg)
            let detectionStart = ProcessInfo.processInfo.systemUptime
            let detected = await faceService.detectFaces(
                in: image, includeFullRange: semanticSettings.usesV2
            )
            let detectionMs = Self.elapsedMilliseconds(since: detectionStart)
            let tileCount = faceService.lastFullRangeTileCount
            // PORTRAIT MATTE: hair+skin auxiliary mattes straight from the file, when the photo
            // carries them (Portrait mode embeds them; ordinary photos do not). Scaled to the
            // working copy by the union path's own rescale later.
            let subjectStart = ProcessInfo.processInfo.systemUptime
            var portraitUnion: CIImage? = nil
            if store.tuning.unionSource == .portraitMatte {
                let hair = CIImage(contentsOf: url, options: [.auxiliarySemanticSegmentationHairMatte: true])
                let skin = CIImage(contentsOf: url, options: [.auxiliarySemanticSegmentationSkinMatte: true])
                switch (hair, skin) {
                case let (h?, sk?):
                    portraitUnion = h.applyingFilter("CIMaximumCompositing", parameters: [
                        kCIInputBackgroundImageKey: sk.cropped(to: h.extent.union(sk.extent))
                    ])
                case let (h?, nil): portraitUnion = h
                case let (nil, sk?): portraitUnion = sk
                case (nil, nil): break
                }
            }
            let mask = portraitUnion ?? (try? segmentationService.subjectMask(
                for: image, source: store.tuning.unionSource == .portraitMatte
                    ? .foreground : store.tuning.unionSource
            )) ?? nil
            let subjectMs = Self.elapsedMilliseconds(since: subjectStart)
            // Fetched unconditionally: one warm request (~15ms) per photo, and having them on
            // hand makes the PERSON MASKS toggle instant rather than a second loading state.
            let personStart = ProcessInfo.processInfo.systemUptime
            let person = await segmentationService.personMasks(
                for: image,
                at: detected.map(\.faceCenter),
                radii: detected.map { $0.faceWidth * 0.5 }
            )
            let personMs = Self.elapsedMilliseconds(since: personStart)
            let semanticStart = ProcessInfo.processInfo.systemUptime
            let semanticMode = semanticSettings.mode
            let semantic: [SemanticHeadMask?]
            let suppressed: Set<UUID>
            switch semanticMode {
            case .legacy:
                semantic = []
                suppressed = []
            case .semanticV1:
                semantic = await semanticService.headMasks(for: image, faces: detected)
                suppressed = []
            case .semanticV2:
                let batch = await semanticService.headMasksV2(
                    for: image, faces: detected, personMasks: person
                )
                semantic = batch.masks
                suppressed = batch.suppressedFaceIDs
            }
            let semanticMs = Self.elapsedMilliseconds(since: semanticStart)
            await MainActor.run {
                photo = image
                faces = detected
                subjectMask = mask
                personMasks = person
                semanticHeadMasks = semantic
                semanticSuppressedFaceIDs = suppressed
                stageTimings = StageTimings(
                    detectionMs: detectionMs, tileCount: tileCount,
                    subjectMs: subjectMs, personMs: personMs, semanticMs: semanticMs
                )
                isPreparing = false
                if mask == nil {
                    statusNote = "NO SUBJECT MASK\n(segmentation needs a real device)"
                }
                if detected.isEmpty {
                    statusNote = "NO FACES DETECTED"
                }
                scheduleRender()
            }
        }
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1_000).rounded())
    }

    private func addManualHead(at location: CGPoint, containerSize: CGSize) {
        guard manualHeadMode, semanticSettings.usesV2, !isPreparing,
              let photo, containerSize.width > 12, containerSize.height > 12 else { return }
        let available = CGSize(width: containerSize.width - 12, height: containerSize.height - 12)
        let imageSize = photo.size
        let fit = min(available.width / imageSize.width, available.height / imageSize.height)
        guard fit > 0 else { return }
        let drawn = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        let imageRect = CGRect(
            x: (containerSize.width - drawn.width) / 2,
            y: (containerSize.height - drawn.height) / 2,
            width: drawn.width, height: drawn.height
        )
        guard imageRect.contains(location) else { return }
        let point = CGPoint(
            x: (location.x - imageRect.minX) / imageRect.width * imageSize.width,
            y: (1 - (location.y - imageRect.minY) / imageRect.height) * imageSize.height
        )
        guard let manual = faceService.estimatedFace(
            at: point, imageSize: imageSize, referenceFaces: faces
        ) else { return }
        let isDuplicate = faces.contains { known in
            hypot(known.faceCenter.x - manual.faceCenter.x,
                  known.faceCenter.y - manual.faceCenter.y)
                < max(known.faceWidth, manual.faceWidth) * 0.62
        }
        guard !isDuplicate else {
            HapticService.selection()
            return
        }

        HapticService.selection()
        faces.append(manual)
        manualFaceIDs.append(manual.id)
        rebuildMasksForManualFaces()
    }

    private func removeLastManualHead() {
        guard let id = manualFaceIDs.popLast(),
              let index = faces.firstIndex(where: { $0.id == id }) else { return }
        faces.remove(at: index)
        if index < personMasks.count { personMasks.remove(at: index) }
        if index < semanticHeadMasks.count { semanticHeadMasks.remove(at: index) }
        scheduleRender()
    }

    private func rebuildMasksForManualFaces() {
        guard let image = photo else { return }
        let preparedFaces = faces
        isPreparing = true
        Task {
            let personStart = ProcessInfo.processInfo.systemUptime
            let person = await segmentationService.personMasks(
                for: image,
                at: preparedFaces.map(\.faceCenter),
                radii: preparedFaces.map { $0.faceWidth * 0.5 }
            )
            let personMs = Self.elapsedMilliseconds(since: personStart)
            let semanticStart = ProcessInfo.processInfo.systemUptime
            let batch = await semanticService.headMasksV2(
                for: image, faces: preparedFaces, personMasks: person
            )
            let semanticMs = Self.elapsedMilliseconds(since: semanticStart)
            await MainActor.run {
                guard faces.map(\.id) == preparedFaces.map(\.id) else { return }
                personMasks = person
                semanticHeadMasks = batch.masks
                semanticSuppressedFaceIDs = batch.suppressedFaceIDs
                stageTimings.personMs = personMs
                stageTimings.semanticMs = semanticMs
                isPreparing = false
                scheduleRender()
            }
        }
    }

    /// Debounced so a slider drag renders the frames it can and skips the rest.
    private func scheduleRender() {
        renderTask?.cancel()
        let tuning = store.tuning
        let currentMode = mode
        let intensity = previewIntensity
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled else { return }
            await render(tuning: tuning, mode: currentMode, intensity: intensity)
        }
    }

    private func render(tuning: HeadMaskTuning, mode: Mode, intensity: Double) async {
        guard let photo, let cg = photo.cgImage, !faces.isEmpty else { return }
        let renderStart = ProcessInfo.processInfo.systemUptime
        let source = CIImage(cgImage: cg)
        let extent = source.extent
        let optionalUnion = subjectMask.map { scaledMask($0, to: extent) }
        let union = optionalUnion
            ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        // The approach toggle, applied exactly as the effect applies it: this face's own
        // instance when available, the union otherwise.
        func subject(for index: Int) -> CIImage {
            guard tuning.usePersonMasks, index < personMasks.count,
                  let personal = personMasks[index] else { return union }
            return scaledMask(personal, to: extent)
        }

        var output: CIImage
        switch mode {
        case .mask:
            // Photo dimmed, then each face's head mask tinted its own colour — the mask itself,
            // seen directly.
            output = source.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.35, kCIInputBrightnessKey: -0.08
            ])
            for (i, face) in faces.enumerated() {
                if semanticSettings.usesV2, semanticSuppressedFaceIDs.contains(face.id) {
                    continue
                }
                // AUTO FIT's inputs for the overlay: scan the same silhouette the mask will
                // intersect, so what is shown is what the effect computes.
                let mask: CIImage
                if semanticSettings.isEnabled, i < semanticHeadMasks.count,
                   let semantic = semanticHeadMasks[i] {
                    mask = scaledMask(semantic.mask, to: extent)
                } else {
                    let derived = HeadGeometryScanner.scan(
                        mask: subject(for: i), face: face, context: Self.renderContext
                    )
                    guard let legacy = BigHeadEffect.headMask(
                        for: face, subject: subject(for: i), extent: extent, tuning: tuning,
                        regionBuilder: labRegionBuilder,
                        neckY: derived.neckNormY.map { CGFloat($0) * extent.height },
                        crownY: derived.crownNormY.map { CGFloat($0) * extent.height }
                    ) else { continue }
                    mask = legacy
                }
                let tint = CIImage(color: Self.tints[i % Self.tints.count]).cropped(to: extent)
                let tinted = tint.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: output,
                    kCIInputMaskImageKey: mask.applyingFilter("CIColorControls", parameters: [
                        kCIInputContrastKey: 1.0, kCIInputBrightnessKey: -0.35
                    ])
                ])
                output = tinted
            }
        case .result:
            // The real effect through the real batch pass used by preview and GIF export.
            let perFace: [BigHeadEffect.PerFaceMask] = faces.enumerated().compactMap {
                index, face in
                if semanticSettings.isEnabled, index < semanticHeadMasks.count,
                   let semantic = semanticHeadMasks[index] {
                    return BigHeadEffect.PerFaceMask(
                        ownerID: face.id,
                        normCenter: CGPoint(x: face.faceCenter.x / extent.width,
                                            y: face.faceCenter.y / extent.height),
                        mask: semantic.mask,
                        neckNormY: semantic.neckNormY,
                        crownNormY: semantic.crownNormY,
                        isSemanticHeadMask: true
                    )
                }
                guard index < personMasks.count, let mask = personMasks[index] else { return nil }
                let derived = HeadGeometryScanner.scan(mask: mask, face: face, context: Self.renderContext)
                return BigHeadEffect.PerFaceMask(
                    ownerID: face.id,
                    normCenter: CGPoint(x: face.faceCenter.x / extent.width,
                                        y: face.faceCenter.y / extent.height),
                    mask: mask,
                    neckNormY: derived.neckNormY,
                    crownNormY: derived.crownNormY
                )
            }
            var effectTuning = tuning
            if semanticSettings.isEnabled { effectTuning.stackedPass = true }
            let effect = BigHeadEffect(
                intensity: intensity, size: 0.5,
                // V2 must match the editor: each detected face has either a semantic head matte
                // or the conservative per-face fallback, never the whole-image subject mask.
                mask: semanticSettings.usesV2 ? optionalUnion : union,
                perFace: perFace,
                suppressedFaceIDs: semanticSettings.usesV2
                    ? semanticSuppressedFaceIDs : [],
                collisionSafe: semanticSettings.usesV2,
                tuning: effectTuning
            )
            output = effect.apply(
                to: source, faces: faces, progress: 1.0, frameIndex: 5
            )
        }

        let final = output.cropped(to: extent)
        guard let outCG = Self.renderContext.createCGImage(final, from: extent) else { return }
        let ui = UIImage(cgImage: outCG)
        guard !Task.isCancelled else { return }
        let renderMs = Self.elapsedMilliseconds(since: renderStart)
        await MainActor.run {
            overlay = ui
            stageTimings.renderMs = renderMs
        }
    }

    private func scaledMask(_ mask: CIImage, to extent: CGRect) -> CIImage {
        guard mask.extent.width > 0, mask.extent.height > 0,
              mask.extent.size != extent.size else { return mask }
        return mask.transformed(by: CGAffineTransform(
            scaleX: extent.width / mask.extent.width,
            y: extent.height / mask.extent.height
        ))
    }

    private var divider: some View {
        Rectangle().fill(Color.surfaceControl).frame(height: 1)
    }
}
