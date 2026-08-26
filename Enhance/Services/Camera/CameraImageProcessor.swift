import UIKit

/// Turns a raw capture into the image the rest of the app expects.
///
/// Camera frames arrive sideways (EXIF orientation) and, from the front camera, mirrored.
/// Everything downstream — `GIFGenerator.fixImageOrientation`'s `.up` short-circuit, Vision
/// face detection, subject segmentation — is exercised daily against `.up` picker images, so
/// captures are normalized here once rather than teaching each consumer about orientation.
enum CameraImageProcessor {

    /// Bakes `imageOrientation` (rotation *and* mirroring) into the bitmap, returning `.up`.
    static func normalizedUp(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true // camera frames carry no alpha

        // `size` is already orientation-adjusted, so a 90° capture comes out portrait.
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Centered square crop in pixel space. Expects a `.up` image — call `normalizedUp` first
    /// so the rect math never reasons about EXIF orientation.
    ///
    /// The viewfinder shows the frame `.resizeAspectFill`ed into a square, which is exactly
    /// the centered square of the sensor image — so this crop keeps what the user saw.
    static func centerSquareCrop(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width != height else { return image }

        let side = min(width, height)
        let rect = CGRect(
            x: (width - side) / 2,
            y: (height - side) / 2,
            width: side,
            height: side
        )
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}
