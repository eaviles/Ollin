import CoreGraphics
import os

/// One captured frame, carried across threads. The `CGImage` is immutable once
/// made, so handing it from the capture queue to an analysis task (and to the
/// main thread for drawing) is safe even though the compiler can't prove it — the
/// box is the promise, the same way `OllinOSC` boxes its connections.
struct FrameBox: @unchecked Sendable {
    let cgImage: CGImage
    let width: Int
    let height: Int

    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
        self.width = cgImage.width
        self.height = cgImage.height
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

/// The latest display frame, written on the capture queue and read on the main
/// thread (`Camera.frame`). A locked hand-off, the same producer/reader split the
/// audio analyzer uses.
final class FrameStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<FrameBox?>(initialState: nil)
    func store(_ box: FrameBox) { lock.withLock { $0 = box } }
    var latest: FrameBox? { lock.withLock { $0 } }
}

/// Something that looks at a frame and updates itself — every tracker
/// (`FaceTracker`, and the ones that follow) conforms. `analyze` runs off the
/// main thread on the analysis task, so a conformer keeps its published results
/// behind its own lock and is `Sendable`.
protocol VisionTracking: AnyObject, Sendable {
    func analyze(_ cgImage: CGImage, size: CGSize) async
}

/// Runs the registered trackers over the camera's frames.
///
/// It does one thing the live path needs and the still-image path doesn't:
/// **drop frames it can't keep up with**. Recognition is slower than the camera's
/// frame rate, so each incoming frame is analyzed only if the previous analysis
/// has finished; otherwise it's skipped and the next one is tried. The display
/// frame is never dropped (the camera publishes every one) — only the analysis
/// is throttled, which is what keeps a sketch responsive while a model runs.
///
/// `@unchecked Sendable`: all mutable state lives under `lock`, and the trackers
/// it drives are themselves `Sendable`.
final class VisionAnalyzer: @unchecked Sendable {

    private struct Weak {
        weak var tracker: (any VisionTracking)?
    }

    private struct State {
        var trackers: [Weak] = []
        var processing = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Add a tracker. Held weakly, so dropping it from the sketch unregisters it.
    func register(_ tracker: any VisionTracking) {
        lock.withLock { state in
            state.trackers.removeAll { $0.tracker == nil || $0.tracker === tracker }
            state.trackers.append(Weak(tracker: tracker))
        }
    }

    /// Offer a frame for analysis. Returns immediately; if no analysis is in
    /// flight and at least one tracker is live, it kicks one off on a detached
    /// task and the frame is processed in the background. Otherwise the frame is
    /// dropped.
    func submit(_ box: FrameBox) {
        let trackers: [any VisionTracking] = lock.withLock { state in
            state.trackers.removeAll { $0.tracker == nil }
            guard !state.processing, !state.trackers.isEmpty else { return [] }
            state.processing = true
            return state.trackers.compactMap { $0.tracker }
        }
        guard !trackers.isEmpty else { return }

        Task.detached { [weak self] in
            for tracker in trackers {
                await tracker.analyze(box.cgImage, size: box.size)
            }
            self?.lock.withLock { $0.processing = false }
        }
    }
}
