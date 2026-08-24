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

    private struct WeakRef {
        weak var analyzer: VisionAnalyzer?
    }
    private static var table: [ObjectIdentifier: WeakRef] = [:]

    /// The analyzer running over `source`, creating it (and installing the
    /// source's tap) on first use.
    static func analyzer(for source: any FrameSource) -> VisionAnalyzer {
        observeTerminationOnce()
        table = table.filter { $0.value.analyzer != nil }
        let key = ObjectIdentifier(source)
        if let existing = table[key]?.analyzer { return existing }
        let analyzer = VisionAnalyzer()
        table[key] = WeakRef(analyzer: analyzer)
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
        guard !processIsTerminating.withLock({ $0 }) else { return }
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
