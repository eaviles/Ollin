import Ollin
import CoreML
import CoreGraphics
import Foundation
import Vision
import os

/// Depth that holds still: temporally consistent relative depth from any frame
/// source (the webcam, a playing video), one frame at a time, over a fetched
/// *video* depth model. A single-image depth model (the `DepthRelief` example's)
/// re-decides every frame on its own, so a still scene shimmers and a slow
/// move wobbles; this one carries a cache of the frames it has seen and reads
/// each new frame against them, so the map moves with the scene and nothing
/// else. The map reads `0` far … `1` near, like every depth surface here.
///
/// ```swift
/// let camera = Camera()
/// lazy var depth = DepthTracker(camera, modelAt: URL(fileURLWithPath:
///     "Models/VideoDepthAnythingSmallF16.mlpackage"))
/// override func draw() {
///     guard let rect = drawFrame(camera) else { return }
///     let near = depth.value(at: Vector2(mouseX, mouseY), in: rect)   // 0 far … 1 near
///     if let map = depth.map { drawImage(map, in: rect) }             // tintable
/// }
/// ```
///
/// The depth is *relative*: the model answers "nearer than" and "farther
/// than", not meters, and it keeps that scale consistent across a session by
/// anchoring on the session's first frame. `reset()` starts a new session on
/// the next frame, for when the camera moves to a different scene. `map` and
/// `value(at:in:)` map the model's own values through a range that follows the
/// scene slowly (`range`), widening at once when something nearer or farther
/// appears and narrowing over a few seconds, so the picture never re-scales
/// from one frame to the next.
///
/// The model weights aren't in the repo (`Scripts/fetch-models.sh` puts them in
/// `Models/`), and the frames are read squashed to the model's landscape input,
/// so a portrait source is reasoned about a little stretched. Loading and
/// availability behave like `ModelTracker`'s: the first-ever load specializes
/// the model for this Mac, `isLoaded` flips when it's ready, and a missing file
/// surfaces through `unavailableReason`. The model needs Apple silicon.
public final class DepthTracker: VisionTracking, @unchecked Sendable {

    /// The loaded model and the session state it reads and writes each frame.
    private struct Loaded {
        var model: MLModel
        var session: MLState
        var imageConstraint: MLImageConstraint
    }

    private struct State {
        var loaded: Loaded?
        var loadTask: Task<Void, Never>?
        /// The next analyzed frame starts a new session (the first frame, or a
        /// `reset()` since).
        var needsReset = true
        var mapBytes: MapBytes?
        var map: Image?
        var sourceFrame: Image?
        var wantsMap = false
        var wantsValues = false
        var wantsSourceFrame = false
        /// The model values currently read as `0` and `1`, or `nil` before the
        /// first result of a session.
        var range: ClosedRange<Double>?
        var analyzedFrames = 0
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("video depth")
    private let modelURL: URL

    /// Run the video depth model at `url` (the fetched `.mlpackage`, or its
    /// compiled `.mlmodelc`) over `source`'s frames, in the order they arrive.
    @MainActor
    public init(_ source: any FrameSource, modelAt url: URL) {
        self.modelURL = url
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// A tracker bound to no source, fed frames by hand (the tests).
    init(modelAt url: URL) {
        self.modelURL = url
    }

    // MARK: Reading

    /// The depth map from the most recent analyzed frame, white with alpha
    /// `0` far … `1` near, sized to the model's output; draw it into the same
    /// rectangle as the frame and it lines up. `nil` before the first result.
    /// The first read arms the conversion, so it can stay `nil` until the next
    /// analyzed frame publishes.
    public var map: Image? {
        lock.withLockUnchecked { state in
            state.wantsMap = true
            return state.map
        }
    }

    /// The frame the most recent map was computed *from*, lagging the live feed
    /// by the model's latency but in step with `map`, so drawing this frame
    /// under the map lines the two up exactly. The first read arms the capture.
    public var sourceFrame: Image? {
        lock.withLockUnchecked { state in
            state.wantsSourceFrame = true
            return state.sourceFrame
        }
    }

    /// The model's own values that `map` and `value(at:in:)` currently read as
    /// `0` (far) and `1` (near), or `nil` before the first result. The model
    /// answers in *relative inverse depth* (larger is nearer, no unit), on a
    /// scale anchored by the session's first frame; this range follows it
    /// slowly so the picture never re-scales from one frame to the next.
    public var range: ClosedRange<Double>? { lock.withLockUnchecked { $0.range } }

    /// How many frames the model has read in this session.
    public var analyzedFrames: Int { lock.withLockUnchecked { $0.analyzedFrames } }

    /// Whether the model has finished loading. `false` covers both "still
    /// loading" (the first-ever load specializes the model for this Mac, which
    /// can take several seconds) and "failed"; `unavailableReason` tells the
    /// two apart.
    public var isLoaded: Bool { lock.withLockUnchecked { $0.loaded != nil } }

    /// Whether the model can run here: the file exists, loaded, and the compute
    /// device can execute it. When `false`, `unavailableReason` says why.
    public var isAvailable: Bool { status.isAvailable }
    /// Why the model can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// The depth under `point` (a canvas point inside `rect`, the rectangle you
    /// drew the frame into), `0` far … `1` near, from the most recent analyzed
    /// frame; `0` before the first result. Out-of-range points clamp to the
    /// edge. Set `mirrored` when the frame is drawn flipped left-to-right (the
    /// selfie orientation). The first query arms the byte plane, so it can
    /// answer `0` until the next analyzed frame publishes.
    public func value(at point: Vector2, in rect: Rectangle,
                      mirrored: Bool = false) -> Double {
        guard let mapBytes = armedMapBytes() else { return 0 }
        return mapBytes.value(at: VisionSpace.normalizedPoint(point, in: rect, mirrored: mirrored))
    }

    /// The depth at a normalized point (`0…1`, lower-left origin), the raw
    /// surface; most sketches want `value(at:in:)`.
    public func valueNormalized(at point: Vector2) -> Double {
        armedMapBytes()?.value(at: point) ?? 0
    }

    /// Start a new session on the next frame: the model forgets the frames it
    /// has seen and re-anchors its depth scale on that frame. For when the
    /// camera moves to a different scene, or a clip starts over.
    public func reset() {
        lock.withLockUnchecked { state in
            state.needsReset = true
            state.range = nil
            state.analyzedFrames = 0
        }
    }

    private func armedMapBytes() -> MapBytes? {
        lock.withLockUnchecked { state in
            state.wantsValues = true
            return state.mapBytes
        }
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        guard let loaded = lock.withLockUnchecked({ $0.loaded }) else {
            _ = ensureLoading()
            return
        }
        let reset = lock.withLockUnchecked { state -> Bool in
            defer { state.needsReset = false }
            return state.needsReset
        }
        do {
            let depth = try Self.predict(cgImage, reset: reset, with: loaded)
            status.recordSuccess()
            let (wantsMap, wantsValues, wantsSourceFrame, previous) = lock.withLockUnchecked {
                ($0.wantsMap, $0.wantsValues, $0.wantsSourceFrame, $0.range)
            }
            let range = Self.followedRange(of: depth.values, after: reset ? nil : previous)
            var mapBytes: MapBytes?
            var map: Image?
            if wantsMap || wantsValues {
                let bytes = Self.bytes(from: depth.values, range: range)
                mapBytes = MapBytes(bytes: bytes, width: depth.width, height: depth.height)
            }
            if wantsMap, let mapBytes {
                map = SegmentationImages.matteImage(fromGray: mapBytes.bytes,
                                                    width: mapBytes.width,
                                                    height: mapBytes.height)
            }
            let sourceFrame = wantsSourceFrame ? Image(cgImage: cgImage) : nil
            lock.withLockUnchecked { state in
                state.range = range
                state.analyzedFrames += 1
                if wantsMap || wantsValues { state.mapBytes = mapBytes }
                if wantsMap { state.map = map }
                if wantsSourceFrame { state.sourceFrame = sourceFrame }
            }
        } catch {
            status.recordFailure(error)
        }
    }

    /// One depth map, row-major from the top-left in the model's own units.
    struct Depth {
        var values: [Float]
        var width: Int
        var height: Int
    }

    /// One step of the model: the frame squashed onto its input, the session
    /// state carried through, one map out.
    private static func predict(_ cgImage: CGImage, reset: Bool, with loaded: Loaded) throws -> Depth {
        let image = try MLFeatureValue(
            cgImage: cgImage, constraint: loaded.imageConstraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let flag = try MLMultiArray(shape: [1], dataType: .float32)
        flag[0] = reset ? 1 : 0
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": image,
            "reset": MLFeatureValue(multiArray: flag),
        ])
        let output = try loaded.model.prediction(from: input, using: loaded.session)
        guard let depth = output.featureValue(for: "depth")?.multiArrayValue,
              depth.shape.count == 4 else {
            throw Error.unavailable("The model produced no depth map.")
        }
        let height = depth.shape[2].intValue
        let width = depth.shape[3].intValue
        let values = depth.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        return Depth(values: values, width: width, height: height)
    }

    /// The range `map` reads through, following the scene: it jumps out to take
    /// in something nearer or farther the moment it appears, and creeps back in
    /// over a few seconds once it's gone, measured on the 1st and 99th
    /// percentiles so one bright pixel can't swing it. A session's first frame
    /// (`previous == nil`) takes its own percentiles outright.
    static func followedRange(of values: [Float], after previous: ClosedRange<Double>?) -> ClosedRange<Double> {
        let (low, high) = percentiles(of: values, 0.01, 0.99)
        guard let previous else { return low...max(high, low + 1e-6) }
        let out = 0.5, back = 0.02
        var lower = previous.lowerBound, upper = previous.upperBound
        lower += (low - lower) * (low < lower ? out : back)
        upper += (high - upper) * (high > upper ? out : back)
        return lower...max(upper, lower + 1e-6)
    }

    /// Two percentiles of a plane, by a 256-bin histogram over its extent.
    private static func percentiles(of values: [Float], _ a: Double, _ b: Double) -> (Double, Double) {
        guard let first = values.first else { return (0, 1) }
        var minimum = first, maximum = first
        for v in values {
            if v < minimum { minimum = v }
            if v > maximum { maximum = v }
        }
        guard maximum > minimum else { return (Double(minimum), Double(maximum)) }
        var histogram = [Int](repeating: 0, count: 256)
        let scale = 255 / (maximum - minimum)
        for v in values {
            histogram[Int((v - minimum) * scale)] += 1
        }
        func level(_ fraction: Double) -> Double {
            let target = Int(Double(values.count) * fraction)
            var seen = 0
            for (bin, count) in histogram.enumerated() {
                seen += count
                if seen >= target { return Double(minimum) + Double(bin) / Double(scale) }
            }
            return Double(maximum)
        }
        return (level(a), level(b))
    }

    /// The plane as bytes through `range`: `0` at the far end, `255` at the
    /// near end, clamped beyond.
    static func bytes(from values: [Float], range: ClosedRange<Double>) -> [UInt8] {
        let low = Float(range.lowerBound)
        let scale = 255 / Float(range.upperBound - range.lowerBound)
        return values.map { v in
            UInt8(min(max((v - low) * scale, 0), 255))
        }
    }

    // MARK: Loading

    /// Why the model couldn't run.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// The model isn't usable here; the text is `unavailableReason`.
        case unavailable(String)

        public var description: String {
            switch self {
            case .unavailable(let reason): return reason
            }
        }
    }

    /// The one background load, started by the first frame.
    @discardableResult
    func ensureLoading() -> Task<Void, Never> {
        lock.withLockUnchecked { state in
            if let task = state.loadTask { return task }
            let task = Task.detached { [weak self] in
                guard let self else { return }
                await self.load()
            }
            state.loadTask = task
            return task
        }
    }

    private func load() async {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            status.markUnavailable(
                "Model file not found: \(modelURL.path). Run Scripts/fetch-models.sh and relaunch.")
            return
        }
        do {
            let compiled = try await ModelTracker.compiledModelURL(for: modelURL)
            let model = try await ModelLoader.shared.load(contentsOf: compiled,
                                                          computeUnits: .cpuAndGPU)
            guard let constraint = model.modelDescription
                    .inputDescriptionsByName["image"]?.imageConstraint,
                  model.modelDescription.stateDescriptionsByName["cache_0"] != nil else {
                status.markUnavailable(
                    "The model at \(modelURL.path) isn't a video depth model (no image input or session state).")
                return
            }
            let loaded = Loaded(model: model, session: model.makeState(), imageConstraint: constraint)
            lock.withLockUnchecked { $0.loaded = loaded }
        } catch {
            status.markUnavailable(
                "The model at \(modelURL.path) couldn't load: \(error.localizedDescription)")
        }
    }
}
