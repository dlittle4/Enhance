import UIKit

/// Abstraction over GIF generation for testability.
/// EditorViewModel depends on this protocol rather than GIFGenerator directly.
protocol GIFGenerating {
    func generateGIF(
        from image: UIImage,
        currentScale: CGFloat,
        visibleRect: CGRect,
        animator: Animator,
        speed: Double,
        pauseDuration: Double,
        visualEffects: [VisualEffect],
        faceEffect: FaceEffect?,
        detectedFaces: [DetectedFace],
        textOverlay: TextOverlay?
    ) -> Data?
    
    func saveTempGIF(_ gifData: Data) -> URL?

    /// BURST CAPTURE: the same GIF, built from a stack of real frames played through in order.
    /// A protocol requirement with a default so the test stubs need not know about bursts.
    func generateGIF(
        frames: [BurstFrame],
        currentScale: CGFloat,
        visibleRect: CGRect,
        animator: Animator,
        speed: Double,
        pauseDuration: Double,
        visualEffects: [VisualEffect],
        faceEffect: FaceEffect?,
        textOverlay: TextOverlay?
    ) -> Data?
}

extension GIFGenerating {
    func generateGIF(
        frames: [BurstFrame],
        currentScale: CGFloat,
        visibleRect: CGRect,
        animator: Animator,
        speed: Double,
        pauseDuration: Double,
        visualEffects: [VisualEffect],
        faceEffect: FaceEffect?,
        textOverlay: TextOverlay?
    ) -> Data? {
        guard let first = frames.first else { return nil }
        return generateGIF(
            from: first.image, currentScale: currentScale, visibleRect: visibleRect, animator: animator,
            speed: speed, pauseDuration: pauseDuration, visualEffects: visualEffects,
            faceEffect: faceEffect, detectedFaces: first.faces, textOverlay: textOverlay
        )
    }
}
