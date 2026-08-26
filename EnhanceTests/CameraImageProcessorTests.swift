import Testing
import UIKit
@testable import Enhance

struct CameraImageProcessorTests {

    // MARK: - Fixtures

    /// A raw landscape bitmap, left half red and right half blue, wrapped in the given
    /// orientation — the asymmetry is what lets a test see rotation and mirroring.
    private func orientedImage(
        rawWidth: Int = 40,
        rawHeight: Int = 20,
        orientation: UIImage.Orientation,
        scale: CGFloat = 1
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let raw = UIGraphicsImageRenderer(
            size: CGSize(width: rawWidth, height: rawHeight), format: format
        ).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: rawWidth / 2, height: rawHeight))
            UIColor.blue.setFill()
            context.fill(CGRect(x: rawWidth / 2, y: 0, width: rawWidth - rawWidth / 2, height: rawHeight))
        }
        return UIImage(cgImage: raw.cgImage!, scale: scale, orientation: orientation)
    }

    private func rgb(of image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let pixel = image.cgImage!.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (data[0], data[1], data[2])
    }

    private func isRed(_ rgb: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        rgb.r > 150 && rgb.b < 100
    }

    private func isBlue(_ rgb: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        rgb.b > 150 && rgb.r < 100
    }

    // MARK: - normalizedUp

    @Test func upImage_passesThroughUntouched() {
        let image = orientedImage(orientation: .up)

        #expect(CameraImageProcessor.normalizedUp(image) === image)
    }

    @Test func rightOrientation_becomesUprightPortrait() {
        // `.right` is the rear camera's usual tagging: raw landscape, display = raw rotated
        // 90° CW, so the raw left half (red) becomes the top half.
        let image = orientedImage(orientation: .right)

        let normalized = CameraImageProcessor.normalizedUp(image)

        #expect(normalized.imageOrientation == .up)
        #expect(normalized.cgImage!.width == 20)
        #expect(normalized.cgImage!.height == 40)
        #expect(isRed(rgb(of: normalized, x: 10, y: 5)))
        #expect(isBlue(rgb(of: normalized, x: 10, y: 35)))
    }

    @Test func mirroredOrientation_bakesTheFlipIn() {
        // `.upMirrored` displays the raw flipped horizontally: raw left half (red) shows on
        // the right. The front camera's tagging composes this with a rotation; the flip is
        // the part worth its own test.
        let image = orientedImage(orientation: .upMirrored)

        let normalized = CameraImageProcessor.normalizedUp(image)

        #expect(normalized.imageOrientation == .up)
        #expect(isBlue(rgb(of: normalized, x: 5, y: 10)))
        #expect(isRed(rgb(of: normalized, x: 35, y: 10)))
    }

    @Test func leftMirroredOrientation_swapsDimensionsAndFlips() {
        // The front camera's portrait tagging. Raw (x, y) displays at (y, x) — transpose —
        // so the raw left half (red) becomes the top half, and columns become rows.
        let image = orientedImage(orientation: .leftMirrored)

        let normalized = CameraImageProcessor.normalizedUp(image)

        #expect(normalized.imageOrientation == .up)
        #expect(normalized.cgImage!.width == 20)
        #expect(normalized.cgImage!.height == 40)
        #expect(isRed(rgb(of: normalized, x: 10, y: 5)))
        #expect(isBlue(rgb(of: normalized, x: 10, y: 35)))
    }

    @Test func normalization_preservesScale() {
        let image = orientedImage(orientation: .right, scale: 2)

        let normalized = CameraImageProcessor.normalizedUp(image)

        #expect(normalized.scale == 2)
        // Pixel dimensions are unchanged by scale — only the point size shrinks.
        #expect(normalized.cgImage!.width == 20)
        #expect(normalized.cgImage!.height == 40)
    }

    // MARK: - centerSquareCrop

    @Test func landscapeCrop_isCenteredHorizontally() {
        // 40×30, left 10 columns red: the centered 30×30 window starts at x=5, so red
        // survives only in the first 5 columns.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 30))
        }

        let cropped = CameraImageProcessor.centerSquareCrop(image)

        #expect(cropped.cgImage!.width == 30)
        #expect(cropped.cgImage!.height == 30)
        #expect(isRed(rgb(of: cropped, x: 2, y: 15)))
        #expect(isBlue(rgb(of: cropped, x: 10, y: 15)))
    }

    @Test func squareImage_passesThroughUntouched() {
        let image = orientedImage(rawWidth: 30, rawHeight: 30, orientation: .up)

        #expect(CameraImageProcessor.centerSquareCrop(image) === image)
    }

    @Test func oddDimensions_stillProduceTheShortSideSquare() {
        let image = orientedImage(rawWidth: 41, rawHeight: 30, orientation: .up)

        let cropped = CameraImageProcessor.centerSquareCrop(image)

        #expect(cropped.cgImage!.width == 30)
        #expect(cropped.cgImage!.height == 30)
    }

    @Test func crop_preservesScale() {
        let image = orientedImage(rawWidth: 40, rawHeight: 20, orientation: .up, scale: 2)

        let cropped = CameraImageProcessor.centerSquareCrop(image)

        #expect(cropped.scale == 2)
        #expect(cropped.imageOrientation == .up)
        #expect(cropped.cgImage!.width == 20)
    }

    // MARK: - The pipeline the view model runs

    @Test func normalizeThenCrop_yieldsUprightSquare() {
        let capture = orientedImage(orientation: .right)

        let processed = CameraImageProcessor.centerSquareCrop(
            CameraImageProcessor.normalizedUp(capture)
        )

        #expect(processed.imageOrientation == .up)
        #expect(processed.cgImage!.width == 20)
        #expect(processed.cgImage!.height == 20)
    }
}
