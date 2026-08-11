import CoreGraphics

/// One copied-feature placement, described by its endpoints. The effect interpolates from
/// `sourceCenter` to `destination` over the reveal and scales toward `finalScale`.
struct ScramblePlacementSpec {
    var region: FaceRegion
    var sourceCenter: CGPoint
    var destination: CGPoint
    var finalScale: CGFloat
}

/// The arrangement Feature Scrambler copies a face's features into. THIRD EYE is V1; the
/// rest are the Stage E layout pack. Each layout resolves to a list of placement specs from
/// a `DetectedFace`, and reports whether the face's landmarks can support it.
///
/// Stored as a dedicated typed property on the view model and `EditorSnapshot`, never in the
/// `[String: Double]` parameter store — an enum has no home there, and a case index would let
/// reordering silently reinterpret saved state. Persisted (if ever) by raw value, not index.
enum ScrambleLayout: String, CaseIterable, Identifiable, Hashable {
    case thirdEye  = "THIRD EYE"
    case mouthEyes = "MOUTH EYES"
    case eyeMouth  = "EYE MOUTH"
    case shuffle   = "SHUFFLE"

    var id: String { rawValue }

    /// Whether this layout can be built from the face's landmarks. Mouth-based layouts need
    /// precise lips (an estimated mouth is not trustworthy enough to copy), and swaps need
    /// both eyes — a profile face with one eye falls back to THIRD EYE / EYE MOUTH only.
    func isAvailable(for face: DetectedFace) -> Bool {
        let hasLeft = FaceRegion.leftEye.isAvailable(in: face)
        let hasRight = FaceRegion.rightEye.isAvailable(in: face)
        let hasMouth = FaceRegion.mouth.isAvailable(in: face)

        switch self {
        case .thirdEye:  return hasLeft || hasRight
        case .eyeMouth:  return (hasLeft || hasRight) && hasMouth
        case .mouthEyes: return hasLeft && hasRight && hasMouth
        case .shuffle:   return hasLeft && hasRight && hasMouth
        }
    }

    /// Original feature regions to cover with skin before compositing the moved features, so
    /// a replaced feature does not show through underneath its copy. THIRD EYE heals nothing
    /// — it is an addition, not a move, so the real eyes stay. The others cover whatever they
    /// replace at the destination.
    func healRegions() -> [FaceRegion] {
        switch self {
        case .thirdEye:  return []
        case .eyeMouth:  return [.mouth]
        case .mouthEyes: return [.leftEye, .rightEye]
        case .shuffle:   return [.leftEye, .rightEye, .mouth]
        }
    }

    /// The placements this layout copies, in composite order. Empty when the layout is
    /// unavailable for the face (the effect then no-ops).
    ///
    /// - Parameter size: the SIZE slider, `0...1`.
    func placements(for face: DetectedFace, size: CGFloat) -> [ScramblePlacementSpec] {
        guard isAvailable(for: face) else { return [] }

        switch self {
        case .thirdEye:
            guard let eye = bestEye(in: face),
                  let eyeCenter = eye.sourceCenter(in: face),
                  let forehead = foreheadCenter(for: face) else { return [] }
            // Preserve V1's tuned life-size mapping to the forehead exactly.
            return [ScramblePlacementSpec(
                region: eye, sourceCenter: eyeCenter, destination: forehead,
                finalScale: 0.6 + size * 0.9
            )]

        case .eyeMouth:
            guard let eye = bestEye(in: face),
                  let eyeCenter = eye.sourceCenter(in: face),
                  let mouthCenter = FaceRegion.mouth.sourceCenter(in: face) else { return [] }
            return [placement(from: eye, at: eyeCenter, to: mouthCenter,
                              fitting: .mouth, in: face, size: size)]

        case .mouthEyes:
            guard let mouthCenter = FaceRegion.mouth.sourceCenter(in: face),
                  let leftCenter = FaceRegion.leftEye.sourceCenter(in: face),
                  let rightCenter = FaceRegion.rightEye.sourceCenter(in: face) else { return [] }
            // The mouth copied onto each eye, each fitted to that eye's size.
            return [
                placement(from: .mouth, at: mouthCenter, to: leftCenter,
                          fitting: .leftEye, in: face, size: size),
                placement(from: .mouth, at: mouthCenter, to: rightCenter,
                          fitting: .rightEye, in: face, size: size)
            ]

        case .shuffle:
            guard let leftCenter = FaceRegion.leftEye.sourceCenter(in: face),
                  let rightCenter = FaceRegion.rightEye.sourceCenter(in: face),
                  let mouthCenter = FaceRegion.mouth.sourceCenter(in: face) else { return [] }
            // A three-way cycle: left eye → right, right eye → mouth, mouth → left eye.
            return [
                placement(from: .leftEye, at: leftCenter, to: rightCenter,
                          fitting: .rightEye, in: face, size: size),
                placement(from: .rightEye, at: rightCenter, to: mouthCenter,
                          fitting: .mouth, in: face, size: size),
                placement(from: .mouth, at: mouthCenter, to: leftCenter,
                          fitting: .leftEye, in: face, size: size)
            ]
        }
    }

    // MARK: - Geometry

    /// A feature-to-feature placement scaled so the copy roughly fills the destination
    /// feature, with SIZE modulating around that fit.
    private func placement(
        from region: FaceRegion, at sourceCenter: CGPoint, to destination: CGPoint,
        fitting destRegion: FaceRegion, in face: DetectedFace, size: CGFloat
    ) -> ScramblePlacementSpec {
        let srcW = region.sourceBounds(in: face)?.width ?? 1
        let destW = destRegion.sourceBounds(in: face)?.width ?? srcW
        let fit = srcW > 0 ? destW / srcW : 1
        return ScramblePlacementSpec(
            region: region, sourceCenter: sourceCenter, destination: destination,
            finalScale: fit * (0.7 + size * 0.6)
        )
    }

    /// The eye to copy for single-eye layouts: prefer the more complete precise polygon,
    /// else whichever eye resolves (so a profile face with one visible eye still works).
    private func bestEye(in face: DetectedFace) -> FaceRegion? {
        let left = FaceRegion.leftEye, right = FaceRegion.rightEye
        if left.polygon(in: face).count >= right.polygon(in: face).count, left.isAvailable(in: face) { return left }
        if right.isAvailable(in: face) { return right }
        if left.isAvailable(in: face) { return left }
        return nil
    }

    /// Forehead target: face-centre X, Y between the brow line and the top of the face box
    /// (CIImage space is bottom-left origin, so "top" is the larger Y).
    private func foreheadCenter(for face: DetectedFace) -> CGPoint? {
        let brows = face.leftEyebrowPoints + face.rightEyebrowPoints
        let browTopY = brows.map(\.y).max() ?? (face.faceCenter.y + face.faceHeight * 0.18)
        let faceTopY = face.boundingBox.maxY
        guard faceTopY > browTopY else { return nil }
        return CGPoint(x: face.faceCenter.x, y: browTopY + (faceTopY - browTopY) * 0.5)
    }
}
