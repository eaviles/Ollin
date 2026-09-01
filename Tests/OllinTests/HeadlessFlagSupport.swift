@testable import Ollin
import Foundation

/// Runs `body` on a thread that is not the main one, and does not return until
/// it has finished.
///
/// `OllinApp.isRenderingHeadless` is process-global, and its whole contract is
/// that a headless drive sets it, drives, and clears it synchronously on one
/// thread. A test that sets it and then *awaits* breaks exactly that: the main
/// actor is released with the flag still up, and every main-actor test that
/// happens to be scheduled during the suspension reads somebody else's export as
/// its own. On CI that failed two `SessionRecorderTests` with `isRecording`
/// false, the recorder having refused to start while a feed test elsewhere in
/// this target sat suspended with the flag set (2026-09-01).
///
/// Joining a plain thread keeps the work off the main one without yielding the
/// main actor at all. The thread is a real one rather than a cooperative worker,
/// so the join cannot park the pool. `body` must not need the main actor, which
/// is true of the two `start()` calls this serves: both are deliberately
/// nonisolated so they never hop.
func startOffTheMainThread(_ body: @escaping @Sendable () -> Void) {
    let finished = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        body()
        finished.signal()
    }
    finished.wait()
}
