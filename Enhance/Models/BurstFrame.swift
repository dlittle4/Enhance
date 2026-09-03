import UIKit

/// One real frame of a BURST CAPTURE, with the faces found in it.
///
/// The generator's other inputs describe one still; a burst is a short stack of stills the
/// GIF plays through in order, effects and all. Faces are per frame because the person moved —
/// that is the point — and a filter pinned to frame 0's eyes would slide off by frame 10.
/// Empty `faces` means "not detected (yet)"; the generator then falls back to frame 0's.
struct BurstFrame {
    let image: UIImage
    var faces: [DetectedFace] = []
}
