import Ollin
import Vision
import CoreGraphics
import Foundation
import os

extension MotionField {
    /// Wrap a Vision flow observation. The core's `MotionField` reads through a
    /// closure, so the dense map is never converted up front: each query reads
    /// straight out of the observation, which is what keeps a camera-resolution
    /// field free to hold.
    init(_ observation: OpticalFlowObservation) {
        self.init(width: Int(observation.size.width), height: Int(observation.size.height),
                  confidence: Double(observation.confidence)) { point in
            visionFlowNormalized(observation, at: point)
        }
    }
}

/// The motion at a normalized point (`0…1`, lower-left origin) read off a Vision
/// observation, in the same normalized units (+y up).
private func visionFlowNormalized(_ observation: OpticalFlowObservation,
                                  at point: Vector2) -> Vector2 {
    let w = Double(observation.size.width)
    let h = Double(observation.size.height)
    guard w > 0, h > 0 else { return .zero }
    // Two facts about Vision's `flow(at:)`, both pinned empirically. It
    // indexes the map **top-down** (it takes row/column fractions, not a
    // point in Vision's usual lower-left normalized space), so the query's
    // y flips here (a real bug: queries used to read the vertically
    // mirrored spot, hidden by the uniform-shift test fixtures, which are
    // invariant under the flip). And it does no bounds clamping of its
    // own: it rounds the scaled coordinate to the nearest pixel
    // (nearest-neighbor, not bilinear) and traps when that rounds past the
    // last one, any x >= (w - 0.5)/w, so even 0.999999, or a particle
    // sitting on the frame's right edge. Clamp to the last pixel's exact
    // coordinate.
    let query = NormalizedPoint(x: min(max(point.x, 0), (w - 1) / w),
                                y: min(max(1 - point.y, 0), (h - 1) / h))
    let (dx, dy) = observation.flow(at: query)
    // The raw map is the *backward* displacement in flow-map pixels with the
    // image's own y (down): where each pixel of the newer frame came from.
    // Negating gives the motion itself, and the y flip lands it in
    // normalized (y up) space, so both components come out of `-dx, dy`.
    return Vector2(-Double(dx) / w, Double(dy) / h)
}

/// Measures optical flow across a source's frames: how every part of the picture
/// is moving, as a dense field of motion vectors a sketch samples anywhere.
///
/// Where `ObjectTracker` follows one patch and `TrajectoryTracker` finds arcs,
/// this one reports *all* the motion — wave a hand and the pixels under it get
/// vectors, pan the camera and the whole field drifts together. It's classical
/// (no neural model), so it runs on any Mac.
///
/// ```swift
/// let camera = Camera()
/// lazy var flow = FlowTracker(camera)
///
/// override func draw() {
///     guard let frame = camera.frame else { return }
///     let view = camera.fittedRectangle(in: bounds) ?? bounds
///     drawImage(frame, in: view)
///     if let field = flow.field {
///         stroke(.white)
///         for s in field.samples(in: view, every: 36) {
///             drawLine(s.position, s.position + s.flow * 3)
///         }
///     }
/// }
/// ```
///
/// The field measures motion *between consecutive analyzed frames* (analysis
/// drops frames it can't keep up with, so the interval breathes with load) —
/// treat magnitudes as a signal to scale by a gain of your own, not as a
/// calibrated speed.
public final class FlowTracker: VisionTracking, @unchecked Sendable {

    /// The speed/quality trade for the flow computation. `.medium` is the live
    /// default; `.low` is the low-latency end (a coarser field) and `.veryHigh`
    /// the finest, at still-image cost.
    public enum Quality: Sendable {
        case low, medium, high, veryHigh

        var visionAccuracy: TrackOpticalFlowRequest.ComputationAccuracy {
            switch self {
            case .low:      return .low
            case .medium:   return .medium
            case .high:     return .high
            case .veryHigh: return .veryHigh
            }
        }
    }

    private struct State {
        /// The live request — built and owned on the analysis task, kept between
        /// frames so each perform measures against the frame before it. A reset
        /// clears it so the next frame starts fresh.
        var request: TrackOpticalFlowRequest?
        var result: MotionField?
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let status = VisionStatus("optical flow")
    private let quality: Quality

    /// The flow field between the two most recent analyzed frames, or `nil`
    /// before the first pair (flow needs two frames, so the first analyzed frame
    /// produces nothing).
    public var field: MotionField? { lock.withLock { $0.result } }

    /// Whether optical flow can run here (it's classical, so effectively always
    /// `true`); `unavailableReason` would explain a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why optical flow can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Measure optical flow across `source`'s frames — the live camera, a
    /// playing video, or any frame source.
    @MainActor
    public init(_ source: any FrameSource, quality: Quality = .medium) {
        self.quality = quality
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Forget the previous frame and start fresh — call after the scene jumps
    /// (a video loop or seek), so a discontinuity isn't read as one huge motion.
    public func reset() {
        lock.withLock { state in
            state.request = nil
            state.result = nil
        }
    }

    // MARK: Offline

    /// The flow between two still images — how the picture moved from
    /// `previous` to `current`. The camera-free path, at still-image accuracy by
    /// default. Returns `nil` if the pair produced no field.
    public static func detect(from previous: Image, to current: Image,
                            quality: Quality = .high) async throws -> MotionField? {
        let request = TrackOpticalFlowRequest()
        request.computationAccuracy = quality.visionAccuracy
        let handler = TargetedImageRequestHandler(source: previous.currentCGImage(),
                                                  target: current.currentCGImage())
        guard let observation = try await handler.perform(request) else { return nil }
        return MotionField(observation)
    }

    /// Measure flow across an explicit ordered sequence of frames, returning one
    /// field per frame (the first is `nil` — flow needs a frame before it). The
    /// camera-free sequence path — run a recorded clip's frames through the same
    /// stateful request the live path uses, and how that path is tested.
    public static func detect(across images: [Image],
                            quality: Quality = .medium) async throws -> [MotionField?] {
        let request = TrackOpticalFlowRequest()
        request.computationAccuracy = quality.visionAccuracy
        var results: [MotionField?] = []
        for image in images {
            let observation = try await request.perform(on: image.currentCGImage())
            results.append(observation.map(MotionField.init))
        }
        return results
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }

        let request: TrackOpticalFlowRequest = lock.withLock { state in
            if state.request == nil {
                let request = TrackOpticalFlowRequest()
                request.computationAccuracy = quality.visionAccuracy
                state.request = request
            }
            return state.request!
        }

        do {
            let observation = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { state in
                // A reset mid-flight replaced the request; drop this stale result.
                guard state.request === request else { return }
                if let observation { state.result = MotionField(observation) }
            }
        } catch {
            status.recordFailure(error)
        }
    }
}
