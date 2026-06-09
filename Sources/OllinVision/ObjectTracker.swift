import Ollin
import Vision
import Foundation
import os

/// A region being followed across frames — where it is right now and how sure the
/// tracker is. Unlike the detectors (which find things on their own each frame),
/// tracking starts from a box *you* hand it and reports that same patch as it
/// moves; the box comes back in normalized coordinates, mapped to the canvas with
/// the `in:` helpers.
public struct TrackedObject: Sendable {

    /// How confident the tracker is in this frame's result, `0…1`. It stays high
    /// while the patch is clearly in view and falls as the object is occluded,
    /// leaves the frame, or changes too fast — a good value to fade an overlay by,
    /// or to threshold on to decide it's been lost.
    public let confidence: Double

    /// The tracked box in normalized coordinates (`0…1`, lower-left origin). Most
    /// sketches want `bounds(in:)` instead, which maps it to canvas space.
    public let boundingBoxNormalized: Rectangle

    init(confidence: Double, boundingBoxNormalized: Rectangle) {
        self.confidence = confidence
        self.boundingBoxNormalized = boundingBoxNormalized
    }

    init(_ observation: DetectedObjectObservation) {
        let r = observation.boundingBox.cgRect
        self.confidence = Double(observation.confidence)
        self.boundingBoxNormalized = Rectangle(x: Double(r.origin.x), y: Double(r.origin.y),
                                               width: Double(r.width), height: Double(r.height))
    }

    /// The tracked box mapped into `rect` (canvas space). Set `mirrored` when the
    /// frame is drawn flipped left-to-right (the selfie orientation).
    public func bounds(in rect: Rectangle, mirrored: Bool = false) -> Rectangle {
        VisionSpace.rectangle(boundingBoxNormalized, in: rect, mirrored: mirrored)
    }

    /// The center of the tracked box, mapped into `rect`.
    public func center(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        bounds(in: rect, mirrored: mirrored).center
    }
}

/// Follows one region across the camera's frames once you point it at something.
///
/// The other trackers *detect* — they find faces or rectangles on their own. This
/// one *tracks*: you seed it with a box (where the thing is right now, e.g. from a
/// click, or from another detector's `bounds(in:)`), and it reports that same
/// patch frame to frame as it moves, so you can follow an object the recognizers
/// don't have a model for. It's a classical tracker (no neural model), so it runs
/// on any Mac.
///
/// ```swift
/// let camera = Camera()
/// lazy var tracker = ObjectTracker(camera)
/// var view = Rectangle(x: 0, y: 0, width: 1, height: 1)
///
/// override func draw() {
///     guard let frame = camera.frame else { return }
///     view = camera.fittedRect(in: bounds) ?? bounds
///     drawImage(frame, in: view)
///     if let object = tracker.trackedObject {
///         noFill(); stroke(.green)
///         drawRect(object.bounds(in: view))
///     }
/// }
///
/// override func mousePressed() {
///     // Lock onto whatever is under the cursor.
///     tracker.track(centeredAt: Vector2(mouseX, mouseY), size: 160, in: view)
/// }
/// ```
public final class ObjectTracker: VisionTracking, @unchecked Sendable {

    private struct State {
        /// A normalized seed (lower-left origin) waiting to (re)start tracking, set
        /// from the main thread and consumed on the analysis task.
        var pendingSeed: Rectangle?
        /// The live tracking request — built and owned on the analysis task, kept
        /// between frames so its internal state accumulates. A re-seed clears it so
        /// the next frame rebuilds.
        var request: TrackObjectRequest?
        var tracking = false
        var result: TrackedObject?
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let status = VisionStatus("object tracking")

    /// The tracked region in the most recent analyzed frame, or `nil` before the
    /// first result (or after `stop()`).
    public var trackedObject: TrackedObject? { lock.withLock { $0.result } }

    /// Whether a target is currently seeded (between `track(…)` and `stop()`).
    /// `trackedObject` can still be `nil` for a frame or two right after seeding,
    /// before the first result lands.
    public var isTracking: Bool { lock.withLock { $0.tracking } }

    /// Whether object tracking can run here (it's classical, so effectively always
    /// `true`); `unavailableReason` would explain a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why object tracking can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Track an object in `camera`'s live feed. Nothing is tracked until you seed a
    /// target with one of the `track(…)` methods.
    @MainActor
    public init(_ camera: Camera) {
        camera.register(self)
    }

    // MARK: Seeding

    /// Start tracking the patch inside `region` (a box in canvas space), where
    /// `frameRect` is the rectangle you drew the frame into (the same one you map
    /// results back through). Set `mirrored` to match a flipped feed. Call again to
    /// re-target.
    public func track(_ region: Rectangle, in frameRect: Rectangle, mirrored: Bool = false) {
        seed(VisionSpace.normalizedRectangle(region, in: frameRect, mirrored: mirrored))
    }

    /// Start tracking a square of side `size` (canvas points) centered at `point` —
    /// the click-to-lock convenience. `frameRect` is the rectangle you drew the
    /// frame into.
    public func track(centeredAt point: Vector2, size: Double,
                      in frameRect: Rectangle, mirrored: Bool = false) {
        let half = size / 2
        let region = Rectangle(corner: Vector2(point.x - half, point.y - half),
                               width: size, height: size)
        track(region, in: frameRect, mirrored: mirrored)
    }

    /// Start tracking from a raw normalized box (`0…1`, lower-left origin) — the
    /// escape hatch when you already have normalized coordinates.
    public func track(normalized box: Rectangle) {
        seed(box)
    }

    /// Stop tracking and clear the result.
    public func stop() {
        lock.withLock { state in
            state.tracking = false
            state.pendingSeed = nil
            state.request = nil
            state.result = nil
        }
    }

    private func seed(_ normalized: Rectangle) {
        lock.withLock { state in
            state.pendingSeed = normalized
            state.request = nil    // supersede any in-flight request; rebuild next frame
            state.result = nil
            state.tracking = true
        }
    }

    // MARK: Offline

    /// Track `seed` (a normalized box, lower-left origin) across an explicit ordered
    /// sequence of frames, returning the result per frame. The camera-free path —
    /// follow an object through a recorded clip, and how the behavior is tested.
    public static func track(_ seed: Rectangle,
                             across images: [Image]) async throws -> [TrackedObject] {
        let observation = DetectedObjectObservation(boundingBox: NormalizedRect(
            x: seed.x, y: seed.y, width: seed.width, height: seed.height))
        let request = TrackObjectRequest(detectedObject: observation)
        var results: [TrackedObject] = []
        for image in images {
            if let r = try await request.perform(on: image.currentCGImage()) {
                results.append(TrackedObject(r))
            }
        }
        return results
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }

        // Pull the request to run (rebuilding from a pending seed) without holding
        // the lock across the await.
        let request: TrackObjectRequest? = lock.withLock { state in
            guard state.tracking else { state.request = nil; return nil }
            if let seed = state.pendingSeed {
                let observation = DetectedObjectObservation(boundingBox: NormalizedRect(
                    x: seed.x, y: seed.y, width: seed.width, height: seed.height))
                state.request = TrackObjectRequest(detectedObject: observation)
                state.pendingSeed = nil
            }
            return state.request
        }
        guard let request else { return }

        do {
            let observation = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { state in
                // A re-seed mid-flight replaced the request; drop this stale result.
                guard state.request === request else { return }
                if let observation { state.result = TrackedObject(observation) }
            }
        } catch {
            status.recordFailure(error)
        }
    }
}
