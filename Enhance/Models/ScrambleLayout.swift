import CoreGraphics

/// One copied-feature placement, described by its endpoints. The effect interpolates from
/// `sourceCenter` to `destination` over the reveal and scales from `startScaleFraction` of
/// `finalScale` up to `finalScale`.
struct ScramblePlacementSpec {
    var region: FaceRegion
    var sourceCenter: CGPoint
    var destination: CGPoint
    var finalScale: CGFloat
    /// Scale at the start of the reveal, as a fraction of `finalScale`. Travelling copies
    /// start near full (they settle as they arrive); a copy that grows *in place* starts at 0.
    var startScaleFraction: CGFloat = 0.65
    /// Whether a soft glow of light radiates from this placement (THIRD EYE).
    var glows: Bool = false
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
    case noseSwap  = "NOSE SWAP"
    case shuffle   = "SHUFFLE"

    var id: String { rawValue }

    /// Whether this layout can be built from the face's landmarks. Mouth- and nose-based
    /// layouts need those precise landmarks (an estimated one is not trustworthy enough to
    /// copy); swaps need both eyes — a profile face with one eye falls back to THIRD EYE /
    /// EYE MOUTH only.
    func isAvailable(for face: DetectedFace) -> Bool {
        let hasLeft = FaceRegion.leftEye.isAvailable(in: face)
        let hasRight = FaceRegion.rightEye.isAvailable(in: face)
        let hasMouth = FaceRegion.mouth.isAvailable(in: face)
        let hasNose = FaceRegion.nose.isAvailable(in: face)

        switch self {
        case .thirdEye:  return hasLeft || hasRight
        case .eyeMouth:  return (hasLeft || hasRight) && hasMouth
        case .noseSwap:  return hasNose && hasMouth
        case .mouthEyes: return hasLeft && hasRight && hasMouth
        case .shuffle:   return hasLeft && hasRight && hasMouth && hasNose
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
        case .noseSwap:  return [.nose, .mouth]
        case .mouthEyes: return [.leftEye, .rightEye]
        case .shuffle:   return [.leftEye, .rightEye, .nose, .mouth]
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
                  let forehead = foreheadCenter(for: face) else { return [] }
            // Grows out of the forehead in place (source == destination, scale 0 → full)
            // with a radiating glow, rather than travelling from the real eye.
            return [ScramblePlacementSpec(
                region: eye, sourceCenter: forehead, destination: forehead,
                finalScale: 0.6 + size * 0.9, startScaleFraction: 0, glows: true
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

        case .noseSwap:
            guard let noseCenter = FaceRegion.nose.sourceCenter(in: face),
                  let mouthCenter = FaceRegion.mouth.sourceCenter(in: face) else { return [] }
            // Swap the nose and the mouth.
            return [
                placement(from: .nose, at: noseCenter, to: mouthCenter,
                          fitting: .mouth, in: face, size: size),
                placement(from: .mouth, at: mouthCenter, to: noseCenter,
                          fitting: .nose, in: face, size: size)
            ]

        case .shuffle:
            guard let leftCenter = FaceRegion.leftEye.sourceCenter(in: face),
                  let rightCenter = FaceRegion.rightEye.sourceCenter(in: face),
                  let noseCenter = FaceRegion.nose.sourceCenter(in: face),
                  let mouthCenter = FaceRegion.mouth.sourceCenter(in: face) else { return [] }
            // A four-way cycle: left eye → right, right eye → nose, nose → mouth, mouth → left.
            return [
                placement(from: .leftEye, at: leftCenter, to: rightCenter,
                          fitting: .rightEye, in: face, size: size),
                placement(from: .rightEye, at: rightCenter, to: noseCenter,
                          fitting: .nose, in: face, size: size),
                placement(from: .nose, at: noseCenter, to: mouthCenter,
                          fitting: .mouth, in: face, size: size),
                placement(from: .mouth, at: mouthCenter, to: leftCenter,
                          fitting: .leftEye, in: face, size: size)
            ]
        }
    }

    // MARK: - Geometry

    /// A feature-to-feature placement scaled so the copy fits *within* the destination
    /// feature, with SIZE modulating around that fit. Uses the smaller of the width and
    /// height ratios (uniform scale keeps the copy's own aspect): a wide mouth and a tall
    /// nose have very different aspect ratios, so fitting by width alone would balloon the
    /// nose into a blob when it lands on the mouth.
    private func placement(
        from region: FaceRegion, at sourceCenter: CGPoint, to destination: CGPoint,
        fitting destRegion: FaceRegion, in face: DetectedFace, size: CGFloat
    ) -> ScramblePlacementSpec {
        let src = region.sourceBounds(in: face) ?? .zero
        let dest = destRegion.sourceBounds(in: face) ?? src
        let fitW = src.width > 0 ? dest.width / src.width : 1
        let fitH = src.height > 0 ? dest.height / src.height : 1
        let fit = max(0.01, min(fitW, fitH))
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
