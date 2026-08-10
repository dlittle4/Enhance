import CoreGraphics

extension CGRect {
    /// True when origin and size are all finite. `CGRect` exposes `isInfinite`/`isNull`
    /// but no public `isFinite`, and Core Image transforms can produce non-finite extents.
    var hasFiniteComponents: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}

/// A logical source region on a detected face. Resolves to a polygon, bounds, and centre
/// in image coordinates (CIImage space) so the compositor can sample and place it.
///
/// Eyes fall back to the legacy pupil + eye-width fields when a precise polygon is missing
/// (rectangle-only, CIDetector, or animal detections), so THIRD EYE still works on an
/// estimated face. The mouth has no such fallback: an estimated lip position is not
/// trustworthy enough to copy, so it reports unavailable rather than inventing a shape.
enum FaceRegion {
    case leftEye
    case rightEye
    case mouth

    /// The region outline, or an empty array when no reliable landmark exists.
    func polygon(in face: DetectedFace) -> [CGPoint] {
        switch self {
        case .leftEye:  return face.regions.leftEye
        case .rightEye: return face.regions.rightEye
        case .mouth:    return face.regions.outerLips
        }
    }

    /// Source bounds to sample, or `nil` when the region cannot be resolved.
    ///
    /// Prefers the precise polygon's bounding box. For an eye with no polygon it synthesises
    /// a box from the pupil centre and eye width (eyes are roughly twice as wide as tall).
    func sourceBounds(in face: DetectedFace) -> CGRect? {
        let pts = polygon(in: face)
        if let box = boundingBox(of: pts), box.width >= 1, box.height >= 1 {
            return box
        }

        // Eye fallback from the flat fields. Mouth has none by design.
        switch self {
        case .leftEye:
            return eyeBox(pupil: face.leftPupilCenter, width: face.leftEyeWidth)
        case .rightEye:
            return eyeBox(pupil: face.rightPupilCenter, width: face.rightEyeWidth)
        case .mouth:
            return nil
        }
    }

    /// Centre of the source region, or `nil` when unavailable.
    func sourceCenter(in face: DetectedFace) -> CGPoint? {
        guard let bounds = sourceBounds(in: face) else { return nil }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func isAvailable(in face: DetectedFace) -> Bool {
        sourceBounds(in: face) != nil
    }

    // MARK: - Helpers

    private func eyeBox(pupil: CGPoint?, width: CGFloat) -> CGRect? {
        guard let pupil, width >= 1 else { return nil }
        let h = width * 0.55
        return CGRect(x: pupil.x - width / 2, y: pupil.y - h / 2, width: width, height: h)
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect? {
        guard points.count >= 2 else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
