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
        detectedFaces: [DetectedFace]
    ) -> Data?
    
    func saveTempGIF(_ gifData: Data) -> URL?
}
