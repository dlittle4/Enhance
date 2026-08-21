import CoreImage

/// Finds a head's **neck** and **crown** by scanning the silhouette itself, so the mask can fit
/// each photo instead of asking one set of slider constants to fit them all.
///
/// The problem it solves is recorded on §2a: every mask parameter is a constant in face units,
/// but where a head actually ends varies per photo — a cap adds a face-height, a bob hides the
/// jaw — so settings tuned on one photo miss on the next *(user-observed in the lab)*. The two
/// numbers no landmark measures are exactly the two this derives from the mask:
///
/// - **Neck**: the narrowest silhouette row between the chin and the shoulder flare. Scanning
///   rows of the segmentation mask for a width minimum is the standard technique — a face-
///   augmentation patent describes head-bounds detection by exactly this kind of horizontal
///   scan over the initial segmentation mask.
/// - **Crown**: the highest row above the face whose width still reads as head, which measures
///   hats and hair rather than guessing at them.
///
/// One small render per face (a 48×160 grayscale band), run where masks are fetched — never in
/// the frame loop. Results are returned **normalized to the mask's image space** (0…1, y-up) so
/// they survive the preview's downsampling the same way `PerFaceMask.normCenter` does.
enum HeadGeometryScanner {

    struct Derived: Equatable {
        /// Narrowest row below the chin, normalized y-up. nil when no clear minimum exists.
        let neckNormY: Double?
        /// Highest row that still reads as head, normalized y-up. nil when the band is empty.
        let crownNormY: Double?
    }

    /// Band raster size. Narrow and short on purpose: this reads shape, not detail.
    static let bandWidth = 48
    static let bandHeight = 160

    /// Scans `mask` (any silhouette: union, per-person, or matte) around `face`.
    ///
    /// - Parameters:
    ///   - face: in the same pixel space as `mask`.
    ///   - context: rendering happens here, once per call — callers own the cadence.
    static func scan(mask: CIImage, face: DetectedFace, context: CIContext) -> Derived {
        let maskExtent = mask.extent
        guard maskExtent.width > 1, maskExtent.height > 1,
              face.faceWidth > 1, face.faceHeight > 1 else {
            return Derived(neckNormY: nil, crownNormY: nil)
        }

        // The band: a face-and-hair-wide column from well below the chin to well above the
        // crown. ±1.3 face-widths catches hair without pulling in a neighbour's torso.
        let band = CGRect(
            x: face.faceCenter.x - face.faceWidth * 1.3,
            y: face.faceCenter.y - face.faceHeight * 1.9,
            width: face.faceWidth * 2.6,
            height: face.faceHeight * 4.4
        ).intersection(maskExtent)
        guard band.width > 4, band.height > 4 else {
            return Derived(neckNormY: nil, crownNormY: nil)
        }

        // Render the band at scan resolution.
        let sx = CGFloat(bandWidth) / band.width
        let sy = CGFloat(bandHeight) / band.height
        let small = mask
            .cropped(to: band)
            .transformed(by: CGAffineTransform(translationX: -band.origin.x, y: -band.origin.y))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        var buf = [UInt8](repeating: 0, count: bandWidth * bandHeight)
        context.render(
            small,
            toBitmap: &buf, rowBytes: bandWidth,
            bounds: CGRect(x: 0, y: 0, width: bandWidth, height: bandHeight),
            format: .R8, colorSpace: nil
        )

        // Row widths, indexed bottom-up in band space (bitmap row 0 is the TOP of the band).
        func width(ofRow y: Int) -> Int {
            let bitmapRow = bandHeight - 1 - y
            let start = bitmapRow * bandWidth
            var count = 0
            for x in 0..<bandWidth where buf[start + x] > 96 { count += 1 }
            return count
        }
        var widths = [Int](repeating: 0, count: bandHeight)
        for y in 0..<bandHeight { widths[y] = width(ofRow: y) }

        func bandY(toImage y: Int) -> Double {
            Double((band.origin.y + (CGFloat(y) + 0.5) / sy) / maskExtent.height)
        }

        // Chin row in band space: the face box's bottom edge.
        let chinImageY = face.faceCenter.y - face.faceHeight * 0.5
        let chinRow = Int((chinImageY - band.origin.y) * sy)

        // NECK: narrowest row in the window below the chin, down to 1.3 face-heights under it.
        // Guards: the row must be non-empty (an empty row is the mask ending, not a neck) and
        // the minimum must be a real pinch — at least 12% narrower than the widest row above
        // it in the window — or a straight-sided silhouette invents a neck where there is none.
        let neckLow = max(1, chinRow - Int(1.3 * Double(sy) * face.faceHeight))
        let neckHigh = min(bandHeight - 2, max(neckLow + 1, chinRow - Int(0.05 * Double(sy) * face.faceHeight)))
        var neck: Int? = nil
        if neckHigh > neckLow {
            var minW = Int.max
            var minRow = neckLow
            var maxW = 0
            for y in neckLow...neckHigh {
                let w = widths[y]
                if w > 0, w < minW { minW = w; minRow = y }
                maxW = max(maxW, w)
            }
            if minW < Int.max, maxW > 0, Double(minW) < Double(maxW) * 0.88 {
                neck = minRow
            }
        }

        // CROWN: highest row above the face centre whose width clears a noise floor.
        let crownLow = min(bandHeight - 1, max(0, chinRow + Int(0.5 * Double(sy) * face.faceHeight)))
        var crown: Int? = nil
        if crownLow < bandHeight {
            for y in stride(from: bandHeight - 1, through: crownLow, by: -1) where widths[y] >= 3 {
                crown = y
                break
            }
        }

        return Derived(
            neckNormY: neck.map(bandY(toImage:)),
            crownNormY: crown.map(bandY(toImage:))
        )
    }
}
