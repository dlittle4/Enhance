import UIKit

/// Lightweight wrapper around UIFeedbackGenerator for consistent haptic feedback.
enum HapticService {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func light() {
        lightGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.impactOccurred()
    }

    static func heavy() {
        heavyGenerator.impactOccurred()
    }

    static func selection() {
        selectionGenerator.selectionChanged()
    }

    /// Warms the selection generator so the *first* tick of a burst is not late.
    ///
    /// The Taptic Engine idles, and `selectionChanged()` on a cold generator can lag by enough to
    /// feel disconnected from the touch. Called at the start of a slider drag, where the first
    /// detent is crossed within a few milliseconds of the finger landing. Harmless if the drag
    /// never moves — the engine simply idles again.
    static func prepareSelection() {
        selectionGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
    }
}
