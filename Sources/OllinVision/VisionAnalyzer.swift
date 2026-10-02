import CoreGraphics
import Foundation
import Ollin
import os
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Set once when the app begins terminating; read from the capture thread. A
/// frame that arrives past this point must be dropped before it reaches the
/// concurrency runtime: the runtime tears down with the process, and starting
/// a task from the capture thread inside that window crashes (SIGBUS in the
/// runtime's task-creation tracing).
private let processIsTerminating = OSAllocatedUnfairLock(initialState: false)

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

    /// Have whatever the first analysis needs ready: a model loaded, a model
    /// warmed past the answers it gives while it loads. Awaited before every
    /// analysis on an export's clock, and only there, where a frame that passes
    /// by while a model loads would be a frame some runs read and others did
    /// not; a tracker that stamps its frames with a time learns here that the
    /// next one is on that clock. The live path never waits for it: there,
    /// frames pass by while a model loads, so the source's other trackers are
    /// not held up behind the load.
    func prepare(for cgImage: CGImage) async
}

extension VisionTracking {
    func prepare(for cgImage: CGImage) async {}
}

/// The availability surface every tracker shares: whether its Vision request
/// can actually run on this Mac, and the human-readable reason when it can't
/// (the heavier neural models need a compute device some Macs lack). Trackers
/// start assumed available and flip on the first capability failure — so a
/// sketch reports the state instead of staying silently empty:
///
/// ```swift
/// if let reason = tracker.unavailableReason {
///     return drawStatus(reason, style: .warning)
/// }
/// ```
public protocol VisionAvailability: AnyObject {
    /// Whether the tracker's model can run on this Mac.
    var isAvailable: Bool { get }
    /// Why the tracker can't run here, or `nil` while it can.
    var unavailableReason: String? { get }
}

extension BarcodeScanner: VisionAvailability {}
extension BodyTracker: VisionAvailability {}
extension ConceptTracker: VisionAvailability {}
extension BodyTracker3D: VisionAvailability {}
extension ContourDetector: VisionAvailability {}
extension DepthTracker: VisionAvailability {}
extension FaceTracker: VisionAvailability {}
extension FlowTracker: VisionAvailability {}
extension HandTracker: VisionAvailability {}
extension ImageClassifier: VisionAvailability {}
extension ModelTracker: VisionAvailability {}
extension ObjectTracker: VisionAvailability {}
extension PersonSegmenter: VisionAvailability {}
extension PointSegmenter: VisionAvailability {}
extension RectangleDetector: VisionAvailability {}
extension SaliencyTracker: VisionAvailability {}
extension SubjectSegmenter: VisionAvailability {}
extension TextRecognizer: VisionAvailability {}
extension TrajectoryTracker: VisionAvailability {}

/// Tracks whether a tracker's Vision request can actually run on this machine,
/// so the live path doesn't fail *silently*.
///
/// Some Vision models (body pose, segmentation, …) need a compute device — a
/// Neural Engine or a capable GPU — that not every Mac has. When `perform` fails
/// with that, a sketch would otherwise just see empty results forever with no
/// explanation. Each tracker owns one of these: it records the failure, exposes
/// it to the sketch (`isAvailable` / `unavailableReason`), and logs it once so
/// it's also visible from `swift run`.
final class VisionStatus: @unchecked Sendable {

    private struct State {
        var reason: String?
        var logged = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let label: String

    init(_ label: String) { self.label = label }

    /// Whether the tracker's model has run (it starts assumed available; a
    /// capability failure flips it).
    var isAvailable: Bool { state.withLock { $0.reason == nil } }

    /// A human-readable reason the tracker can't run here, or `nil` when it can.
    var reason: String? { state.withLock { $0.reason } }

    /// A successful run clears any prior unavailability (a one-off error recovers).
    func recordSuccess() {
        state.withLock { if $0.reason != nil { $0.reason = nil } }
    }

    /// A failed run. A permanent-capability error (no compute device) marks the
    /// tracker unavailable and logs once; a transient error (a bad frame) is
    /// ignored, so a single hiccup doesn't flip the flag.
    func recordFailure(_ error: Error) {
        guard let reason = VisionStatus.capabilityReason(error, label: label) else { return }
        markUnavailable(reason)
    }

    /// A permanent failure established outside `perform` — a model file that's
    /// missing or won't load. Marks the tracker unavailable with `reason` and
    /// logs once.
    func markUnavailable(_ reason: String) {
        let shouldLog = state.withLock { state -> Bool in
            state.reason = reason
            if state.logged { return false }
            state.logged = true
            return true
        }
        if shouldLog {
            FileHandle.standardError.write(Data("⚠️ OllinVision: \(reason)\n".utf8))
        }
    }

    /// A friendly reason for a permanent capability failure, or `nil` for an error
    /// treated as transient.
    private static func capabilityReason(_ error: Error, label: String) -> String? {
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        if text.contains("compute device") {
            return "\(label) can't run on this Mac — the Vision model needs a Neural Engine or a more capable GPU (it runs on Apple silicon)."
        }
        return nil
    }
}

/// One shared analyzer per frame source, created the first time a tracker
/// attaches to that source. Trackers constructed over the same `FrameSource`
/// (the same camera, the same video player) share one analyzer, so the source
/// is tapped once and its frames fan out to every tracker.
///
/// Lifetime: the analyzer is held strongly by the tap closure installed on the
/// source, so it lives exactly as long as the source does; this table only
/// remembers it weakly so the next tracker finds it.
@MainActor
enum SourceAnalyzers {

    /// The source is remembered beside its analyzer, and both weakly: a key
    /// is an address, and a source made where a freed one stood has the same
    /// address. An analyzer can outlive its source (a tap a source's own thread
    /// still holds keeps it), so the address alone would hand a new source the
    /// old analyzer, and the new source would never be tapped at all.
    private struct WeakRef {
        weak var analyzer: VisionAnalyzer?
        weak var source: AnyObject?
    }
    private static var table: [ObjectIdentifier: WeakRef] = [:]

    /// The analyzer running over `source`, creating it (and installing the
    /// source's tap) on first use.
    static func analyzer(for source: any FrameSource) -> VisionAnalyzer {
        observeTerminationOnce()
        table = table.filter { $0.value.analyzer != nil && $0.value.source != nil }
        let key = ObjectIdentifier(source)
        if let entry = table[key], entry.source === source, let existing = entry.analyzer {
            return existing
        }
        let analyzer = VisionAnalyzer()
        table[key] = WeakRef(analyzer: analyzer, source: source)
        source.frameTap = makeFrameTap(analyzer)
        return analyzer
    }

    private static var terminationObserved = false

    /// Arm the terminating flag the first time any analyzer exists. The flag is
    /// what lets `submit` refuse frames that arrive while the process exits.
    private static func observeTerminationOnce() {
        guard !terminationObserved else { return }
        terminationObserved = true
        #if canImport(AppKit)
        let name = NSApplication.willTerminateNotification
        #elseif canImport(UIKit)
        let name = UIApplication.willTerminateNotification
        #endif
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            processIsTerminating.withLock { $0 = true }
        }
    }
}

/// Formed in a free function, never inside a `@MainActor` context, so the tap
/// carries no actor isolation — the source calls it from its capture/decode
/// thread (the same render-thread rule the audio taps follow).
private func makeFrameTap(_ analyzer: VisionAnalyzer) -> FrameTap {
    { cgImage in analyzer.submit(FrameBox(cgImage)) }
}

/// Runs the registered trackers over a frame source's frames.
///
/// It does one thing the live path needs and the still-image path doesn't:
/// **drop frames it can't keep up with**. Recognition is slower than the source's
/// frame rate, so each incoming frame is analyzed only if the previous analysis
/// has finished; otherwise it's skipped and the next one is tried. The display
/// frame is never dropped (the source publishes every one) — only the analysis
/// is throttled, which is what keeps a sketch responsive while a model runs.
///
/// An export is the other way round. Its frames are drawn on a clock of their
/// own, so a reading that lands whenever the analysis happens to finish lands
/// on a different frame in every run. A frame offered on the main thread while
/// an export drives the sketch (a source following the export's clock offers
/// it there) is analyzed before the drive moves on: every tracker, every
/// frame, models loaded first, nothing dropped.
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
        /// The newest frame the source offered, for a tracker that joins
        /// during an export: it reads that frame at once rather than starting
        /// blank until the source's next one.
        var latest: FrameBox?
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Entered for each background analysis and left when it ends, so an
    /// export's first frame can wait out one the live path started before
    /// the drive began, and its answer cannot land after the export's own.
    private let inFlight = DispatchGroup()

    /// Add a tracker. Held weakly, so dropping it from the sketch unregisters it.
    /// During an export, the tracker reads the source's newest frame before
    /// this returns.
    func register(_ tracker: any VisionTracking) {
        let latest = lock.withLock { state in
            state.trackers.removeAll { $0.tracker == nil || $0.tracker === tracker }
            state.trackers.append(Weak(tracker: tracker))
            return state.latest
        }
        if let latest, Self.followsExportClock {
            analyzeInExport(latest, trackers: [tracker])
        }
    }

    /// Offer a frame for analysis. Returns immediately; if no analysis is in
    /// flight and at least one tracker is live, it kicks one off on a detached
    /// task and the frame is processed in the background. Otherwise the frame is
    /// dropped. During an export, on the main thread, the frame is analyzed
    /// before this returns instead.
    func submit(_ box: FrameBox) {
        guard !processIsTerminating.withLock({ $0 }) else { return }
        if Self.followsExportClock {
            let trackers: [any VisionTracking] = lock.withLock { state in
                state.latest = box
                state.trackers.removeAll { $0.tracker == nil }
                return state.trackers.compactMap { $0.tracker }
            }
            analyzeInExport(box, trackers: trackers)
            return
        }
        // Entered under the lock that claims the analysis, so an export's
        // first frame either sees this one in flight and waits for it, or
        // comes after it has ended.
        let inFlight = inFlight
        let trackers: [any VisionTracking] = lock.withLock { state in
            state.latest = box
            state.trackers.removeAll { $0.tracker == nil }
            guard !state.processing, !state.trackers.isEmpty else { return [] }
            state.processing = true
            inFlight.enter()
            return state.trackers.compactMap { $0.tracker }
        }
        guard !trackers.isEmpty else { return }

        // User-initiated: the analysis feeds a live sketch's next frames. At
        // the default priority it starves behind bulk work on a busy machine,
        // and the sketch's trackers go quiet while the picture keeps moving.
        Task.detached(priority: .userInitiated) { [weak self] in
            for tracker in trackers {
                await tracker.analyze(box.cgImage, size: box.size)
            }
            self?.lock.withLock { $0.processing = false }
            inFlight.leave()
        }
    }

    /// Whether a frame offered now belongs to an export's clock: the export
    /// flag is up, and the offer comes from the thread that drives it, which
    /// is the only thread that flag is believed on. A benchmark run is
    /// headless too, but its frames stand in for a window's, so it keeps the
    /// live path.
    private static var followsExportClock: Bool {
        Thread.isMainThread && OllinApp.isExporting
    }

    /// One frame through `trackers`, each model loaded first, with the main
    /// thread held until the last answer is published. An analysis the live
    /// path started before the export began finishes first, so it can never
    /// land on top of this one.
    private func analyzeInExport(_ box: FrameBox, trackers: [any VisionTracking]) {
        guard !trackers.isEmpty else { return }
        inFlight.wait()
        waitOnMainThread {
            for tracker in trackers {
                await tracker.prepare(for: box.cgImage)
                await tracker.analyze(box.cgImage, size: box.size)
            }
        }
    }

    /// Runs one frame through the registered trackers inline, awaiting the
    /// whole analysis: the same trackers and the same `analyze` calls as
    /// `submit`, with no dependence on a background task being scheduled. The
    /// deterministic drive for tests, where a fixed deadline over `submit`
    /// reads a saturated machine as a failure. Skips the drop gate on purpose
    /// (every tracker publishes behind its own lock, so an overlap with an
    /// in-flight `submit` pass is safe).
    func analyzeNow(_ box: FrameBox) async {
        let trackers: [any VisionTracking] = lock.withLock { state in
            state.trackers.removeAll { $0.tracker == nil }
            return state.trackers.compactMap { $0.tracker }
        }
        for tracker in trackers {
            await tracker.analyze(box.cgImage, size: box.size)
        }
    }
}

/// Run `work` on a detached task and hold the calling thread until it ends.
/// Only the main thread, during an export, ever waits here: it is no worker of
/// the cooperative pool, so parking it cannot starve the task it waits for,
/// and nothing a tracker's analysis or a model's load awaits runs on the main
/// actor. A free function, so the closure carries no actor isolation.
func waitOnMainThread(_ work: @escaping @Sendable () async -> Void) {
    let done = DispatchSemaphore(value: 0)
    Task.detached(priority: .userInitiated) {
        await work()
        done.signal()
    }
    done.wait()
}
