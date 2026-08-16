import Ollin
import CoreML
import Vision
import CoreGraphics
import Foundation
import os

/// One thing an object-detection model found: what it is, how sure the model
/// is, and where — a labeled box, in normalized coordinates until the `in:`
/// helpers map it onto the canvas.
public struct DetectedObject: Sendable {

    /// What the model says the object is — one of *that model's* labels (a
    /// COCO-trained detector says `"person"`, `"dog"`, `"bicycle"`, …).
    public let label: String

    /// How confident the model is in the label, `0…1`.
    public let confidence: Double

    /// The bounding box in normalized coordinates (lower-left origin).
    let boundsN: Rectangle

    /// The object's bounding box mapped into `rect` (the rectangle you drew the
    /// frame into), ready to `drawRect`.
    public func bounds(in rect: Rectangle, mirrored: Bool = false) -> Rectangle {
        VisionSpace.rectangle(boundsN, in: rect, mirrored: mirrored)
    }

    /// The center of the bounding box, mapped into `rect`.
    public func center(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        let b = bounds(in: rect, mirrored: mirrored)
        return Vector2(b.x + b.width / 2, b.y + b.height / 2)
    }
}

/// An image-typed model output held as bytes Ollin extracted itself: one gray
/// 8-bit plane, top-left origin — the same plane the drawable `map` is built
/// from, so point queries and the picture agree by construction.
///
/// Load-bearing: queries never go through Vision's
/// `PixelBufferObservation.pixel(at:)`. On a **multi-channel** (BGRA) output —
/// what an image-to-image Core ML model like a depth estimator produces —
/// `pixel(at:)` misindexes the buffer (pinned by probe: only 13 of 100 grid
/// points agree with the observation's own `cgImage`, the rest land at
/// scattered offsets — read live as diagonal banding). The observation's
/// `cgImage` is stride-aware and upright, so the bytes come from it instead.
/// (`pixel(at:)` behaves on *single-channel* buffers — the saliency heat map,
/// optical flow — where it stays in use.)
struct MapBytes: Sendable {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    /// The value at a normalized point (`0…1`, lower-left origin), `0…1` at
    /// 8-bit resolution. Integer clamping, so any query is safe.
    func value(at point: Vector2) -> Double {
        guard width > 0, height > 0 else { return 0 }
        let col = min(max(Int(point.x * Double(width)), 0), width - 1)
        let row = min(max(Int((1 - point.y) * Double(height)), 0), height - 1)
        return Double(bytes[row * width + col]) / 255
    }
}

/// Everything one model run produced, decoded by output kind — the still-image
/// counterpart of `ModelTracker`'s live surfaces. A model fills only the
/// surfaces its outputs match: a classifier fills `labels`, an image-to-image
/// model fills `map` (and answers `value(at:in:)`), an object detector fills
/// `objects`, a semantic segmenter fills `classMask`.
///
/// `@unchecked Sendable`: `Image` is a class, but the map is freshly created by
/// the run and handed over whole — nothing else holds or mutates it.
public struct ModelOutput: @unchecked Sendable {

    /// What the model classified, strongest first — empty unless the model is a
    /// classifier.
    public let labels: [Classification]

    /// What an object-detection model found — empty unless the model reports
    /// labeled boxes.
    public let objects: [DetectedObject]

    /// An image-typed output as a drawable `Image` — white, with alpha = the
    /// output value (`0…1`) — or `nil` when the model has none. At the model's
    /// own resolution; drawing it into the source's rectangle stretches it onto
    /// the picture, and `tint(_:)` recolors it.
    public let map: Image?

    /// The same image-typed output at face value — full color, the picture an
    /// image-to-image model painted (a style-transfer model's stylized frame) —
    /// or `nil` when the model has none. `map` reads the output as a gray
    /// value map; this keeps the model's own colors.
    public let outputImage: Image?

    /// What a semantic-segmentation model labeled, pixel by pixel — or `nil`
    /// when the model's output isn't a class-index plane.
    public let classMask: ClassMask?

    let mapBytes: MapBytes?

    /// The map's value under `point` (a canvas point inside `rect`, the
    /// rectangle you drew the source into), `0…1` — `0` when the model has no
    /// image-typed output. Out-of-range points clamp to the edge.
    public func value(at point: Vector2, in rect: Rectangle,
                      mirrored: Bool = false) -> Double {
        guard let mapBytes else { return 0 }
        return mapBytes.value(at: VisionSpace.normalizedPoint(point, in: rect, mirrored: mirrored))
    }

    /// The map's value at a normalized point (`0…1`, lower-left origin) — the
    /// raw surface, for when you're working in Vision's coordinate space
    /// yourself.
    public func valueNormalized(at point: Vector2) -> Double {
        mapBytes?.value(at: point) ?? 0
    }
}

/// Runs **your own Core ML model** over a camera's frames (or a still image) —
/// the open end of the tracker catalog. Anything converted to Core ML
/// (`.mlpackage` or `.mlmodel`) drops in: point the tracker at the file and
/// read the surfaces matching what the model outputs, decoded the same way the
/// built-in trackers decode theirs.
///
/// ```swift
/// let camera = Camera()
/// lazy var depth = ModelTracker(camera, modelAt: URL(fileURLWithPath:
///     "Models/DepthAnythingV2SmallF16.mlpackage"))
/// override func draw() {
///     guard let rect = drawFrame(camera) else { return }
///     let near = depth.value(at: Vector2(mouseX, mouseY), in: rect)  // 0…1
///     if let map = depth.map { drawImage(map, in: rect) }            // tintable
/// }
/// ```
///
/// Four result surfaces, by output kind — a model fills the ones it matches:
/// - **Classifier** (label + confidence outputs): `labels` / `top` /
///   `confidence(of:)`, like `ImageClassifier` but over your model's own
///   vocabulary.
/// - **Image-to-image** (a depth estimator, a custom matte, a style-transfer
///   model): `map` — a white-alpha `Image` like the segmentation matte — plus
///   `value(at:in:)`, the value under any canvas point; and `outputImage`, the
///   same output at face value — full color, for a model that paints a
///   picture rather than a value map.
/// - **Object detector** (a model with its non-maximum-suppression head, the
///   form Apple's model gallery ships): `objects` — labeled boxes mapped by
///   `bounds(in:)`.
/// - **Semantic segmenter** (a class-index plane, the DeepLabV3 form):
///   `classMask` — every pixel labeled with a class, queryable by point,
///   name, or as per-class drawable masks (`ClassMask`).
///
/// Loading happens in the background, off the frame loop: `isLoaded` flips when
/// the model is ready (the **first-ever** load of a model also specializes it
/// for this Mac's compute device, which can take several seconds; the compiled
/// result is cached, so every later launch starts in milliseconds). The model
/// runs on whatever Core ML schedules best — on Apple silicon, typically the
/// Neural Engine. A model file that's missing or can't load surfaces through
/// `isAvailable` / `unavailableReason` instead of failing silently.
public final class ModelTracker: VisionTracking, @unchecked Sendable {

    /// Why a model run couldn't happen.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// The model isn't usable here — the file is missing or failed to
        /// load; the text is `unavailableReason`.
        case unavailable(String)

        public var description: String {
            switch self {
            case .unavailable(let reason): return reason
            }
        }
    }

    private struct State {
        /// The live request — built once the model loads, re-performed every
        /// frame (the loaded container is what carries the model's cost).
        var request: CoreMLRequest?
        /// The one background load, started on the first frame (or `detect`).
        var loadTask: Task<Void, Never>?
        /// A pre-loaded model handed to `init(_:model:)`, consumed by the load.
        var pendingModel: MLModel?
        var labels: [Classification] = []
        var objects: [DetectedObject] = []
        var map: Image?
        var outputImage: Image?
        var mapBytes: MapBytes?
        var classMask: ClassMask?
        var sourceFrame: Image?
        var wantsMap = false
        var wantsValues = false
        var wantsOutputImage = false
        var wantsClassMask = false
        var wantsSourceFrame = false
        /// The model's declared class vocabulary (the segmentation preview
        /// metadata), parsed once at load.
        var modelLabels: [String] = []
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status: VisionStatus
    private let modelURL: URL?
    private let label: String

    /// What the most recent analyzed frame classified, strongest first — empty
    /// unless the model is a classifier.
    public var labels: [Classification] { lock.withLockUnchecked { $0.labels } }

    /// The single strongest label, or `nil` while there is none.
    public var top: Classification? { labels.first }

    /// The confidence for one label by name, `0…1` — `0` when the model didn't
    /// score it. Spaces work in place of underscores.
    public func confidence(of label: String) -> Double {
        let wanted = label.lowercased().replacingOccurrences(of: " ", with: "_")
        return lock.withLockUnchecked {
            $0.labels.first { $0.label.lowercased() == wanted }?.confidence ?? 0
        }
    }

    /// What the most recent analyzed frame's object detection found — empty
    /// unless the model reports labeled boxes.
    public var objects: [DetectedObject] { lock.withLockUnchecked { $0.objects } }

    /// The model's image-typed output from the most recent analyzed frame —
    /// white, alpha = the output value — or `nil` before the first result (or
    /// when the model has none). The first read arms the conversion, so it can
    /// stay `nil` until the next analyzed frame publishes.
    public var map: Image? {
        lock.withLockUnchecked { state in
            state.wantsMap = true
            return state.map
        }
    }

    /// The camera frame the most recent result was computed *from* — the source
    /// image that produced this frame's `map`/`labels`/etc., or `nil` before the
    /// first result. Because analysis runs behind the live feed, this frame lags
    /// the camera by the inference latency, but it's perfectly in step with the
    /// result: draw it (instead of the live frame) under an overlay or a depth
    /// scene and the two line up exactly, with no relative lag. The first read arms
    /// the capture, so it can stay `nil` until the next analyzed frame.
    public var sourceFrame: Image? {
        lock.withLockUnchecked { state in
            state.wantsSourceFrame = true
            return state.sourceFrame
        }
    }

    /// The model's image-typed output from the most recent analyzed frame at
    /// face value — full color, the picture an image-to-image model painted (a
    /// style-transfer model's stylized frame) — or `nil` before the first
    /// result (or when the model has none). The first read arms the
    /// conversion, so it can stay `nil` until the next analyzed frame
    /// publishes. `map` reads the same output as a gray white-alpha map; this
    /// surface keeps the model's own colors.
    public var outputImage: Image? {
        lock.withLockUnchecked { state in
            state.wantsOutputImage = true
            return state.outputImage
        }
    }

    /// What a semantic-segmentation model labeled in the most recent analyzed
    /// frame, pixel by pixel — or `nil` before the first result (or when the
    /// model's output isn't a class-index plane). The first read arms the
    /// conversion, so it can stay `nil` until the next analyzed frame
    /// publishes.
    public var classMask: ClassMask? {
        lock.withLockUnchecked { state in
            state.wantsClassMask = true
            return state.classMask
        }
    }

    /// Whether the model has finished loading. `false` covers both "still
    /// loading" (the first-ever load specializes the model for this Mac, which
    /// can take several seconds) and "failed" — `unavailableReason` tells the
    /// two apart.
    public var isLoaded: Bool { lock.withLockUnchecked { $0.request != nil } }

    /// Whether the model can run here: the file exists, loaded, and the compute
    /// device can execute it. When `false`, `unavailableReason` says why.
    public var isAvailable: Bool { status.isAvailable }
    /// Why the model can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Run the Core ML model at `url` (an `.mlpackage`, `.mlmodel`, or already-
    /// compiled `.mlmodelc`) over `source`'s frames — the live camera, or a
    /// playing video.
    @MainActor
    public init(_ source: any FrameSource, modelAt url: URL) {
        self.modelURL = url
        self.label = url.deletingPathExtension().lastPathComponent
        self.status = VisionStatus(self.label)
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Run an already-loaded `MLModel` over `source`'s frames — for a model
    /// you configured yourself (compute units, custom options).
    @MainActor
    public init(_ source: any FrameSource, model: MLModel) {
        self.modelURL = nil
        self.label = "Core ML model"
        self.status = VisionStatus(self.label)
        lock.withLockUnchecked { $0.pendingModel = model }
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// A tracker bound to no frame source, for still images only — call
    /// `detect(in:)`.
    public init(modelAt url: URL) {
        self.modelURL = url
        self.label = url.deletingPathExtension().lastPathComponent
        self.status = VisionStatus(self.label)
    }

    /// The map's value under `point` (a canvas point inside `rect`, the
    /// rectangle you drew the frame into), `0…1`, from the most recent analyzed
    /// frame — `0` before the first result. Out-of-range points clamp to the
    /// edge. Set `mirrored` when the frame is drawn flipped left-to-right (the
    /// selfie orientation). The first query arms the byte conversion, so it can
    /// answer `0` until the next analyzed frame publishes.
    public func value(at point: Vector2, in rect: Rectangle,
                      mirrored: Bool = false) -> Double {
        guard let mapBytes = armedMapBytes() else { return 0 }
        return mapBytes.value(at: VisionSpace.normalizedPoint(point, in: rect, mirrored: mirrored))
    }

    /// The map's value at a normalized point (`0…1`, lower-left origin) — the
    /// raw surface. Most sketches want `value(at:in:)`, which queries and
    /// answers in canvas space.
    public func valueNormalized(at point: Vector2) -> Double {
        armedMapBytes()?.value(at: point) ?? 0
    }

    private func armedMapBytes() -> MapBytes? {
        lock.withLockUnchecked { state in
            state.wantsValues = true
            return state.mapBytes
        }
    }

    /// Run the model on a still image, once — waits for the model to load on
    /// the first call. Throws `Error.unavailable` when the model can't load
    /// (the file is missing) or can't run here.
    public func detect(in image: Image) async throws -> ModelOutput {
        await ensureLoading().value
        guard let request = lock.withLockUnchecked({ $0.request }) else {
            throw Error.unavailable(status.reason ?? "The model isn't available.")
        }
        let observations = try await request.perform(on: image.currentCGImage())
        let decoded = Self.decode(observations)
        let outputCGImage = decoded.observation.flatMap { try? $0.cgImage }
        let mapBytes = outputCGImage.flatMap(Self.mapBytes(from:))
        let map = mapBytes.flatMap {
            SegmentationImages.matteImage(fromGray: $0.bytes, width: $0.width, height: $0.height)
        }
        let outputImage = outputCGImage.flatMap(SegmentationImages.colorImage(from:))
        let modelLabels = lock.withLockUnchecked { $0.modelLabels }
        let classMask = decoded.featureValue.flatMap {
            ClassMask(featureValue: $0, labels: modelLabels)
        }
        return ModelOutput(labels: decoded.labels, objects: decoded.objects,
                           map: map, outputImage: outputImage, classMask: classMask,
                           mapBytes: mapBytes)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Once the model is known unavailable, stop — it won't recover this
        // session, and re-trying every frame just wastes work.
        guard status.isAvailable else { return }
        // While the model loads (in its own task, so the source's other
        // trackers aren't stalled behind it), frames simply pass by.
        guard let request = lock.withLockUnchecked({ $0.request }) else {
            _ = ensureLoading()
            return
        }
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            let decoded = Self.decode(observations)
            // Convert the image-typed output only once some read has armed it
            // (value queries arm the byte plane; a `map` read additionally arms
            // the gray drawable; an `outputImage` read arms the full-color
            // decode; a `classMask` read arms the class-plane decode) — a
            // sketch reading only labels never pays a conversion.
            let (wantsMap, wantsValues, wantsOutputImage, wantsClassMask, wantsSourceFrame, modelLabels) =
                lock.withLockUnchecked {
                    ($0.wantsMap, $0.wantsValues, $0.wantsOutputImage,
                     $0.wantsClassMask, $0.wantsSourceFrame, $0.modelLabels)
                }
            var outputCGImage: CGImage?
            if wantsMap || wantsValues || wantsOutputImage {
                outputCGImage = decoded.observation.flatMap { try? $0.cgImage }
            }
            var mapBytes: MapBytes?
            var map: Image?
            var outputImage: Image?
            if wantsMap || wantsValues {
                mapBytes = outputCGImage.flatMap(Self.mapBytes(from:))
            }
            if wantsMap, let mapBytes {
                map = SegmentationImages.matteImage(fromGray: mapBytes.bytes,
                                                    width: mapBytes.width,
                                                    height: mapBytes.height)
            }
            if wantsOutputImage {
                outputImage = outputCGImage.flatMap(SegmentationImages.colorImage(from:))
            }
            var classMask: ClassMask?
            if wantsClassMask {
                classMask = decoded.featureValue.flatMap {
                    ClassMask(featureValue: $0, labels: modelLabels)
                }
            }
            let sourceFrame = wantsSourceFrame ? Image(cgImage: cgImage) : nil
            lock.withLockUnchecked { state in
                state.labels = decoded.labels
                state.objects = decoded.objects
                if wantsMap || wantsValues { state.mapBytes = mapBytes }
                if wantsMap { state.map = map }
                if wantsOutputImage { state.outputImage = outputImage }
                if wantsClassMask { state.classMask = classMask }
                if wantsSourceFrame { state.sourceFrame = sourceFrame }
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Loading

    /// The one background load — started by the first frame (or `detect`),
    /// shared by everything that waits on it.
    private func ensureLoading() -> Task<Void, Never> {
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
        do {
            let model: MLModel
            if let pending = lock.withLockUnchecked({ $0.pendingModel }) {
                model = pending
                lock.withLockUnchecked { $0.pendingModel = nil }
            } else if let url = modelURL {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    status.markUnavailable(
                        "Model file not found: \(url.path) — download the model and relaunch.")
                    return
                }
                let compiled = try await Self.compiledModelURL(for: url)
                model = try await MLModel.load(contentsOf: compiled, configuration: .init())
            } else {
                status.markUnavailable("No model was provided.")
                return
            }
            let labels = Self.declaredClassLabels(of: model)
            let request = CoreMLRequest(model: try CoreMLModelContainer(model: model))
            lock.withLockUnchecked { state in
                state.modelLabels = labels
                state.request = request
            }
        } catch {
            status.markUnavailable(
                "The model at \(modelURL?.path ?? "?") couldn't load: \(error.localizedDescription)")
        }
    }

    /// The compiled (`.mlmodelc`) form of the model, compiled once and cached
    /// at a **stable path**. Load-bearing: Core ML specializes a model for this
    /// Mac's compute device on first load and caches that work keyed to the
    /// compiled files — loading the same stable path again takes milliseconds,
    /// while recompiling to a fresh temporary path every launch re-specializes
    /// every time (~10 s for a small depth model). The cache key carries the
    /// source's path, modification time, and size, so replacing the model file
    /// compiles anew.
    static func compiledModelURL(for url: URL) async throws -> URL {
        if url.pathExtension == "mlmodelc" { return url }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Ollin/CompiledModels", isDirectory: true)
        let name = url.deletingPathExtension().lastPathComponent
        // A compiled model is a directory; saying so keeps the URL identical
        // whether or not it exists yet (`appendingPathComponent` otherwise adds
        // the trailing slash only once it does).
        let cached = dir.appendingPathComponent("\(name)-\(stamp(for: url)).mlmodelc",
                                                isDirectory: true)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        let compiled = try await MLModel.compileModel(at: url)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Copy to a private name, then move into place: the move is atomic, so
        // a concurrent load never reads a half-copied model directory (two
        // trackers loading the same model at once is the ordinary case for a
        // paired-encoder model).
        let staging = dir.appendingPathComponent("staging-\(UUID().uuidString).mlmodelc",
                                                 isDirectory: true)
        try FileManager.default.copyItem(at: compiled, to: staging)
        do {
            try FileManager.default.moveItem(at: staging, to: cached)
        } catch CocoaError.fileWriteFileExists {
            // A concurrent load won the move; theirs is identical.
            try? FileManager.default.removeItem(at: staging)
        }
        return cached
    }

    /// A deterministic fingerprint of the model file (path, modification time,
    /// size) for the compile cache — FNV-1a, stable across launches (unlike
    /// `Hasher`, which is seeded per process).
    private static func stamp(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? Int) ?? 0
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(url.path)|\(modified)|\(size)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: Decoding

    private struct Decoded {
        var labels: [Classification] = []
        var objects: [DetectedObject] = []
        var observation: PixelBufferObservation?
        var featureValue: MLSendableFeatureValue?
    }

    /// Split whatever the model produced by observation kind. A classifier
    /// yields one `ClassificationObservation` per label (its whole vocabulary,
    /// like the built-in classifier); a detector yields one
    /// `RecognizedObjectObservation` per found object; an image-to-image model
    /// yields a `PixelBufferObservation`; a semantic segmenter yields its
    /// class plane as a `CoreMLFeatureValueObservation` (a multiarray —
    /// `ClassMask` decodes it, and rejects multiarrays that aren't one).
    private static func decode(_ observations: [any VisionObservation]) -> Decoded {
        var decoded = Decoded()
        for observation in observations {
            switch observation {
            case let classification as ClassificationObservation:
                decoded.labels.append(Classification(
                    label: classification.identifier,
                    confidence: Double(classification.confidence)))
            case let object as RecognizedObjectObservation:
                let box = object.boundingBox.cgRect
                let top = object.labels.first
                decoded.objects.append(DetectedObject(
                    label: top?.identifier ?? "object",
                    confidence: Double(top?.confidence ?? object.confidence),
                    boundsN: Rectangle(x: box.origin.x, y: box.origin.y,
                                       width: box.width, height: box.height)))
            case let pixels as PixelBufferObservation:
                decoded.observation = pixels
            case let feature as CoreMLFeatureValueObservation:
                if decoded.featureValue == nil, feature.featureValue.isShapedArray {
                    decoded.featureValue = feature.featureValue
                }
            default:
                continue
            }
        }
        decoded.labels.sort { $0.confidence > $1.confidence }
        decoded.objects.sort { $0.confidence > $1.confidence }
        return decoded
    }

    /// The class vocabulary a segmentation model declares about itself —
    /// Apple's gallery models (and anything exported with coremltools' image
    /// segmenter preview) carry it as JSON in the creator-defined metadata.
    /// Empty when the model declares none; index-based reads work regardless.
    static func declaredClassLabels(of model: MLModel) -> [String] {
        guard let creator = model.modelDescription
                .metadata[.creatorDefinedKey] as? [String: Any],
              let params = creator["com.apple.coreml.model.preview.params"] as? String,
              let data = params.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let labels = json["labels"] as? [String] else { return [] }
        return labels
    }

    /// The image-typed output as Ollin's own gray plane, extracted through the
    /// observation's stride-aware `cgImage` — never through `pixel(at:)`,
    /// which misindexes multi-channel buffers (see `MapBytes`).
    static func mapBytes(from cgImage: CGImage) -> MapBytes? {
        guard let bytes = SegmentationImages.grayBytes(from: cgImage,
                                                       width: cgImage.width,
                                                       height: cgImage.height) else { return nil }
        return MapBytes(bytes: bytes, width: cgImage.width, height: cgImage.height)
    }
}
