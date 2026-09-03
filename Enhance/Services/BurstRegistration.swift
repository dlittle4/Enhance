import CoreGraphics
import Vision

/// The camera track's measurement: how far the whole frame shifted between two consecutive
/// burst frames, from Vision's translational registration (FEATURE-MOTION-EFFECTS.md §1d).
///
/// Cheap at the lab's MASK SIZE (a few ms per pair), and honest about failure: any error or
/// an absent observation is zero motion, never a throw, so a burst whose frames Vision cannot
/// align simply reads as still. Run on the shrunk copies the masks use, so the two agree.
enum BurstRegistration {

    /// The shift from `previous` to `next`, in normalized units of `previous`'s width and
    /// height. Vision's translation is in `previous`'s pixels; the sign convention follows
    /// Vision's image coordinates, which is fine for every reader here — magnitudes and
    /// symmetric angles — and is documented rather than corrected.
    static func translation(from previous: CGImage, to next: CGImage) -> CGVector {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: next, options: [:])
        let handler = VNImageRequestHandler(cgImage: previous, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .zero
        }
        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else { return .zero }
        let t = observation.alignmentTransform
        let w = CGFloat(max(1, previous.width)), h = CGFloat(max(1, previous.height))
        let v = CGVector(dx: t.tx / w, dy: t.ty / h)
        return v.dx.isFinite && v.dy.isFinite ? v : .zero
    }
}
