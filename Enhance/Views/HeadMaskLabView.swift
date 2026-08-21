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
/// effect through the same sequential pass the pipeline uses — deliberately, so group-photo
/// judgements are made against what ships, overlap artifacts included.
///
/// **Scaffolding, and meant to be deleted** once the numbers graduate.
struct HeadMaskLabView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store = HeadMaskTuningStore.shared

    private enum Mode: String, CaseIterable { case mask = "MASK", result = "RESULT" }

    @State private var mode: Mode = .mask
    @State private var fixtures: [URL] = []
    @State private var selectedFixture: URL?
    @State private var photo: UIImage?
    @State private var faces: [DetectedFace] = []
    @State private var subjectMask: CIImage?
    /// Per-person instance masks aligned with `faces` — the PERSON MASKS approach's input.
    @State private var personMasks: [CIImage?] = []
    @State private var overlay: UIImage?
    @State private var isPreparing = false
    @State private var statusNote: String?
    @State private var didCopy = false
    /// Intensity used by RESULT mode, so growth is judged at more than one strength.
    @State private var previewIntensity: Double = 0.9
    @State private var renderTask: Task<Void, Never>?

    private let faceService = FaceDetectionService()
    private let segmentationService = SubjectSegmentationService()
    private static let renderContext = CIContext(options: [.useSoftwareRenderer: false])
    private let labRegionBuilder = HeadRegionBuilder()

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
                        divider
                        ellipseSliders
                            .disabled(store.tuning.useJawRegion)
                            .opacity(store.tuning.useJawRegion ? 0.35 : 1)
                        divider
                        chinSliders
                            .disabled(store.tuning.useJawRegion)
                            .opacity(store.tuning.useJawRegion ? 0.35 : 1)
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
        .onChange(of: mode) { _, _ in scheduleRender() }
        .onChange(of: previewIntensity) { _, _ in scheduleRender() }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.surfaceControl)
            if let overlay {
                Image(uiImage: overlay)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                RoundedRectangle(cornerRadius: 8)
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                            RoundedRectangle(cornerRadius: 12)
                                .fill(mode == m ? Color.enhanceMint : Color.surfaceControl)
                        )
                }
            }
        }
    }

    private var approachToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("APPROACH")
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
            labSlider("PIVOT Y", value: $store.tuning.pivotY, in: 0.0...0.6,
                      hint: "fraction up the ellipse")
            labSlider("INTENSITY", value: $previewIntensity, in: 0.1...1.0,
                      hint: "preview only, not stored")
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.enhanceMint))
            }
            Button {
                HapticService.selection()
                store.reset()
            } label: {
                Text("RESET TO DEFAULT")
                    .font(.silkscreenButtonLabel)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surfaceControl))
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
            let detected = await faceService.detectFaces(in: image)
            // PORTRAIT MATTE: hair+skin auxiliary mattes straight from the file, when the photo
            // carries them (Portrait mode embeds them; ordinary photos do not). Scaled to the
            // working copy by the union path's own rescale later.
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
            // Fetched unconditionally: one warm request (~15ms) per photo, and having them on
            // hand makes the PERSON MASKS toggle instant rather than a second loading state.
            let person = await segmentationService.personMasks(
                for: image,
                at: detected.map(\.faceCenter),
                radii: detected.map { $0.faceWidth * 0.5 }
            )
            await MainActor.run {
                photo = image
                faces = detected
                subjectMask = mask
                personMasks = person
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
        let source = CIImage(cgImage: cg)
        let extent = source.extent
        let union = subjectMask.map { scaledMask($0, to: extent) }
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
                // AUTO FIT's inputs for the overlay: scan the same silhouette the mask will
                // intersect, so what is shown is what the effect computes.
                let derived = HeadGeometryScanner.scan(
                    mask: subject(for: i), face: face, context: Self.renderContext
                )
                guard let mask = BigHeadEffect.headMask(
                    for: face, subject: subject(for: i), extent: extent, tuning: tuning,
                    regionBuilder: labRegionBuilder,
                    neckY: derived.neckNormY.map { CGFloat($0) * extent.height },
                    crownY: derived.crownNormY.map { CGFloat($0) * extent.height }
                ) else { continue }
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
            // The real effect through the real sequential pass — group overlap artifacts
            // included, because that is what ships.
            let perFace: [BigHeadEffect.PerFaceMask] = zip(faces, personMasks).compactMap {
                face, mask in
                guard let mask else { return nil }
                let derived = HeadGeometryScanner.scan(mask: mask, face: face, context: Self.renderContext)
                return BigHeadEffect.PerFaceMask(
                    normCenter: CGPoint(x: face.faceCenter.x / extent.width,
                                        y: face.faceCenter.y / extent.height),
                    mask: mask,
                    neckNormY: derived.neckNormY,
                    crownNormY: derived.crownNormY
                )
            }
            let effect = BigHeadEffect(
                intensity: intensity, size: 0.5, mask: union, perFace: perFace, tuning: tuning
            )
            output = source
            for face in faces {
                output = effect.apply(to: output, face: face, progress: 1.0, frameIndex: 5)
            }
        }

        let final = output.cropped(to: extent)
        guard let outCG = Self.renderContext.createCGImage(final, from: extent) else { return }
        let ui = UIImage(cgImage: outCG)
        guard !Task.isCancelled else { return }
        await MainActor.run { overlay = ui }
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
