import CoreImage
import ImageIO
import UIKit

/// Renders the effect-picker card thumbnails — one function per family, used by the editor's
/// carousels and by EFFECTS LAB's live card alike.
///
/// Extracted from `EditorViewModel` so the lab cannot show a card the editor would render
/// differently: the values, the tint, the frame index and the crop are decided here once. With
/// an identity `EffectLabLookup` the output is byte-identical to what the view model produced
/// inline before the lab existed (`EffectLabTests` pins that).
struct EffectThumbnailRenderer {
    let context: CIContext

    /// The frame each family's card is rendered at. Visual effects at 3 so per-frame noise
    /// (HEAT HAZE, SLICE SHIFT) has settled; face effects at 5 for the animated eye effects.
    static let visualFrameIndex = 3
    static let faceFrameIndex = 5

    /// The colours the cards have always used: a purple tint so EDGES and ECHO read as coloured
    /// against any photo, and red lasers.
    static let visualTint: LaserColor = .purple
    static let faceLaser: LaserColor = .red

    /// The longest side of a visual-effect card's source.
    static let thumbnailDimension = 120

    /// The parameter ids each family's factory reads, in slot order — the ids the lab windows
    /// and the thumbnail preset can carry. Listed here rather than read from `.parameters` so
    /// the renderer never allocates a declaration array.
    static let visualParamIDs = [
        EffectParameter.intensityID, EffectParameter.sizeID, EffectParameter.tertiaryID,
        EffectParameter.quaternaryID, EffectParameter.quinaryID
    ]
    static let faceParamIDs = [EffectParameter.intensityID, EffectParameter.secondaryID]

    // MARK: - Sources

    /// A JPEG-recompressed, downscaled copy of the photo for the visual-effect cards.
    ///
    /// Recompressed on purpose: `CGImageSourceCreateThumbnailAtIndex` is the fast path for
    /// a downscale, and it wants an encoded source. Quality 0.7 is invisible at 120px.
    static func thumbnailSource(from source: UIImage, maxPixel: Int = thumbnailDimension) -> CGImage? {
        downscaled(source, maxPixel: maxPixel, quality: 0.7)
    }

    /// The same downscale at the live preview's resolution — what the face cards are cut from,
    /// since a 120px source would lose the eyes.
    static func previewSource(from source: UIImage, maxPixel: Int) -> CGImage? {
        downscaled(source, maxPixel: maxPixel, quality: 0.9)
    }

    private static func downscaled(_ source: UIImage, maxPixel: Int, quality: CGFloat) -> CGImage? {
        guard let data = source.jpegData(compressionQuality: quality),
              let imgSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return source.cgImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(imgSource, 0, options as CFDictionary) ?? source.cgImage
    }

    /// The face cards' crop: ~1.8× the face box, so the crop carries enough surrounding context
    /// to read as a portrait rather than a disembodied feature. `.null` when the face is outside
    /// the image or too small to crop.
    static func faceCrop(for face: DetectedFace, in extent: CGRect) -> CGRect {
        let box = face.boundingBox
        let crop = box
            .insetBy(dx: -box.width * 0.4, dy: -box.height * 0.4)
            .intersection(extent)
        guard !crop.isNull, crop.width > 1, crop.height > 1 else { return .null }
        return crop
    }

    // MARK: - Rendering

    /// One visual-effect card: the preset's slider values, each through its window, built by
    /// the same factory the editor uses.
    func render(_ type: VisualEffectType, source: CGImage, lab: EffectLabLookup) -> UIImage? {
        let (values, progress) = lab.thumbnailValues(
            for: type, paramIDs: Self.visualParamIDs, previewProgress: type.previewProgress)
        func resolved(_ id: String) -> Double { lab.remap(values[id] ?? 0.5, paramID: id, for: type) }

        let options = EffectOptions(
            size: resolved(EffectParameter.sizeID),
            tertiary: resolved(EffectParameter.tertiaryID),
            quaternary: resolved(EffectParameter.quaternaryID),
            quinary: resolved(EffectParameter.quinaryID),
            tintColor: Self.visualTint,
            gradientStops: .default,
            pixelShape: .square
        )
        let effect = type.effect(intensity: resolved(EffectParameter.intensityID), options: options)
        let output = effect.apply(to: CIImage(cgImage: source), progress: progress, frameIndex: Self.visualFrameIndex)
        return context.createCGImage(output, from: output.extent).map(UIImage.init(cgImage:))
    }

    /// One face-filter card. `face` must already be in `base`'s coordinate space and `crop` is
    /// what `faceCrop` returned for it.
    func render(_ filter: FaceFilterType, base: CIImage, face: DetectedFace, crop: CGRect, lab: EffectLabLookup) -> UIImage? {
        guard !crop.isNull else { return nil }
        let (values, progress) = lab.thumbnailValues(
            for: filter, paramIDs: Self.faceParamIDs, previewProgress: filter.previewProgress)
        func resolved(_ id: String) -> Double { lab.remap(values[id] ?? 0.5, paramID: id, for: filter) }

        let effect = filter.effect(
            intensity: resolved(EffectParameter.intensityID),
            secondValue: resolved(EffectParameter.secondaryID),
            laserColor: Self.faceLaser
        )
        let output = effect.apply(to: base, face: face, progress: progress, frameIndex: Self.faceFrameIndex)
        return context.createCGImage(output, from: crop).map(UIImage.init(cgImage:))
    }
}
