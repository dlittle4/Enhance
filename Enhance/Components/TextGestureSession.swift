import Foundation

/// Collapses a burst of overlapping recognizers — a drag, a pinch and a rotate that begin and end
/// independently and in any order — into one editing session, so the whole burst records a single
/// undo entry and a single regeneration. See FEATURE-TEXT-EFFECTS.md §8.6.
///
/// A **counter, not a boolean**, is the crux: with a boolean, a pinch ending before an in-progress
/// rotate would close the session while the rotate is still moving the text, and the rotate's
/// remaining travel would never reach a commit. Counting keeps the session open until the *last*
/// recognizer lifts.
///
/// Deliberately free of UIKit so the counting logic sits on the directly-tested path (§12.7) rather
/// than behind a touch harness. It owns *only* the count; the view model owns the snapshot and the
/// undo history, reached through the injected closures. `capture` fires once, on the 0→1 edge;
/// `commit` fires once, on the →0 edge. Whether that commit actually pushes an undo entry is the
/// view model's call — it skips the push when the overlay is unchanged — so a cancelled or no-op
/// gesture leaves neither the undo stack nor the regeneration queue dirtied.
final class TextGestureSession {

    private(set) var activeCount = 0

    /// True between the first recognizer's `.began` and the last one's end.
    var isActive: Bool { activeCount > 0 }

    /// Called from every recognizer's `.began`. Only the 0→1 transition invokes `capture`.
    func begin(capture: () -> Void) {
        if activeCount == 0 { capture() }
        activeCount += 1
    }

    /// Called from every recognizer's `.ended` / `.cancelled` / `.failed`. Only the →0 transition
    /// invokes `commit`. A stray end with no active gesture is ignored, so the count cannot go
    /// negative.
    func end(commit: () -> Void) {
        guard activeCount > 0 else { return }
        activeCount -= 1
        if activeCount == 0 { commit() }
    }

    /// Force-drains the session, committing once if anything was active. Idempotent: a second call
    /// with nothing active does nothing, so the two teardown paths (resign-active and view removal)
    /// cannot double-commit. For backgrounding and view teardown mid-gesture.
    func abort(commit: () -> Void) {
        guard activeCount > 0 else { return }
        activeCount = 0
        commit()
    }
}
