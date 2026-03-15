import CoreImage
import UIKit

/// Simulates rising heat distortion with animated sine-wave displacement.
/// Each row of the image is shifted horizontally by a time-varying sine wave.
struct HeatHazeEffect: VisualEffect {
    private let maxAmplitude: CGFloat

    init(intensity: Double = 0.5) {
        self.maxAmplitude = CGFloat(max(1.0, 8.0 * intensity))
    }

    func apply(to image: CIImage, progress: CGFloat, frameIndex: Int) -> CIImage {
        let amplitude = maxAmplitude * min(1.0, progress * progress)
        guard amplitude > 0.3 else { return image }

        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return image }

        let phase = CGFloat(frameIndex) * 0.35
        let frequency: CGFloat = 0.015

        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let cgImage = CIContext().createCGImage(image, from: extent) else { return image }
        guard let context = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var outputData = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            let shift = amplitude * sin(CGFloat(y) * frequency + phase)
            let intShift = Int(shift)

            for x in 0..<width {
                let srcX = min(max(x + intShift, 0), width - 1)
                let srcIdx = y * bytesPerRow + srcX * 4
                let dstIdx = y * bytesPerRow + x * 4

                outputData[dstIdx] = pixelData[srcIdx]
                outputData[dstIdx + 1] = pixelData[srcIdx + 1]
                outputData[dstIdx + 2] = pixelData[srcIdx + 2]
                outputData[dstIdx + 3] = pixelData[srcIdx + 3]
            }
        }

        guard let outContext = CGContext(
            data: &outputData,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let outCG = outContext.makeImage() else { return image }

        return CIImage(cgImage: outCG).transformed(
            by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y)
        )
    }
}
