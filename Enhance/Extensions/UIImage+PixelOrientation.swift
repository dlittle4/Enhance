import CoreImage
import ImageIO
import UIKit

extension UIImage {
    /// Core Image works on the underlying CG pixels and does not consistently apply a
    /// `UIImage`'s display orientation. Return an origin-zero image whose pixels are physically
    /// upright, so Vision coordinates, semantic crops, previews and GIF rendering share one
    /// coordinate space for camera photos stored with EXIF rotation.
    func orientationAppliedCIImage() -> CIImage? {
        let source: CIImage
        if let cgImage {
            source = CIImage(cgImage: cgImage)
        } else if let ciImage {
            source = ciImage
        } else {
            return nil
        }
        let oriented = source.oriented(cgImagePropertyOrientation)
        return oriented.transformed(by: CGAffineTransform(
            translationX: -oriented.extent.minX,
            y: -oriented.extent.minY
        ))
    }

    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
