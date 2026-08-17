import Ollin
import CoreML
import CoreGraphics
import CoreVideo
import Foundation
import os

/// Lifts **whatever you point at** out of a camera's frames (or a still image):
/// give it one point and it segments the thing under that point, any thing, as
/// a soft matte and the cutout it makes. Where `SubjectSegmenter` decides for
/// itself what stands out, this one takes direction: a click picks the mug,
/// not the person holding it.
///
/// ```swift
/// let camera = Camera()
/// lazy var picker = PointSegmenter(camera,
///     imageEncoderAt: encoderURL, promptEncoderAt: promptURL, maskDecoderAt: decoderURL)
/// override func mousePressed() {
///     guard let rect = camera.fittedRect(in: bounds) else { return }
///     picker.pick(at: Vector2(mouseX, mouseY), in: rect)
/// }
/// override func draw() {
///     if let cutout = picker.pick?.cutout { drawImage(cutout, in: rect) }
/// }
/// ```
///
/// Under it is a promptable-segmentation model in three parts, fetched by
/// `Scripts/fetch-models.sh` and never committed: an image encoder run once
/// over the picked frame (~0.2 s), a prompt encoder that turns the points into
/// the model's query, and a mask decoder that answers it (~10 ms). A pick
/// freezes the frame it was made on, so refining is cheap: `include(_:in:)`
/// adds a point the pick must cover, `exclude(_:in:)` a point it must not
/// (shift-click a stray region away), both re-answering against the frozen
/// frame's cached encoding. `pick(at:in:)` starts fresh on the current frame.
///
/// The model proposes three readings of every prompt (the part, the whole,
/// the group) and the one it scores highest wins; `Pick.score` is that
/// confidence. Results publish asynchronously: `pick` stays `nil` (or keeps
/// the previous pick) until the new answer lands, `isWorking` says one is on
/// the way.
public final class PointSegmenter: VisionTracking, @unchecked Sendable {

    /// Why a run couldn't happen.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// The models aren't usable here; the text is `unavailableReason`.
        case unavailable(String)

        public var description: String {
            switch self {
            case .unavailable(let reason): return reason
            }
        }
    }

    /// One answered pick: the thing under the point(s), lifted. Handed over
    /// whole, its images built fresh per answer and never mutated after,
    /// which is the `@unchecked Sendable` promise (the same one
    /// `Segmentation` makes).
    public struct Pick: @unchecked Sendable {
        /// The white-alpha silhouette of the picked thing, frame-aligned:
        /// draw it into the same rectangle as the frame and it lines up.
        public let matte: Image
        /// The frame's own pixels where the picked thing is, transparent
        /// elsewhere, frame-aligned like `matte`.
        public let cutout: Image
        /// The model's own confidence in this mask, `0…1`.
        public let score: Double
        /// The mask's bounding box in frame fractions (`0…1` on both axes).
        let region: Rectangle

        /// The picked thing's bounding box, mapped into the rectangle the
        /// frame is drawn in, for framing, stamping, or outlining it.
        public func bounds(in rect: Rectangle) -> Rectangle {
            Rectangle(x: rect.x + region.x * rect.width,
                      y: rect.y + region.y * rect.height,
                      width: region.width * rect.width,
                      height: region.height * rect.height)
        }
    }

    /// One prompt point in the model's square input space, with its label
    /// (1 = the pick must cover this, 0 = it must not).
    private struct Prompt {
        var x: Float
        var y: Float
        var label: Float
    }

    /// The three loaded model parts.
    private struct Models {
        var imageEncoder: MLModel
        var promptEncoder: MLModel
        var maskDecoder: MLModel
    }

    /// A frozen frame's encoding, reused by every refine on that frame.
    private struct Embeddings {
        var image: MLMultiArray
        var coarse: MLMultiArray
        var fine: MLMultiArray
    }

    private struct State {
        var models: Models?
        var loadTask: Task<Void, Never>?
        /// The newest frame the source produced (stored, never encoded).
        var latest: FrameBox?
        /// The frame the current selection lives on, frozen at pick time.
        var frozen: FrameBox?
        /// `frozen`'s encoding, filled by the first run and kept while the
        /// frame stays the same.
        var embeddings: Embeddings?
        /// The current prompt set, in the order given.
        var prompts: [Prompt] = []
        /// Bumped by every pick/refine/clear; stale work checks it before
        /// publishing.
        var generation = 0
        var working = false
        var pick: Pick?
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("point segmentation")
    private let imageEncoderURL: URL
    private let promptEncoderURL: URL
    private let maskDecoderURL: URL

    /// The square edge the model reads frames and points in.
    private static let inputEdge = 1024.0
    /// The decoder's mask resolution per side.
    private static let maskEdge = 256

    // MARK: Reading

    /// The most recent answered pick, or `nil` while there is none (nothing
    /// picked yet, the pick was cleared, or the prompt matched nothing).
    /// A new pick replaces it only when its answer lands.
    public var pick: Pick? { lock.withLockUnchecked { $0.pick } }

    /// Whether an answer is on the way; the encode after a fresh pick takes
    /// a beat, refines land in milliseconds.
    public var isWorking: Bool { lock.withLockUnchecked { $0.working } }

    /// Whether the models can run here: the files exist, loaded, and the
    /// compute device can execute them. When `false`, `unavailableReason`
    /// says why.
    public var isAvailable: Bool { status.isAvailable }
    /// Why the models can't run here, or `nil` when they can.
    public var unavailableReason: String? { status.reason }

    // MARK: Creating

    /// Pick from `source`'s frames (the live camera, or a playing video).
    /// The three files are the fetched model parts.
    @MainActor
    public init(_ source: any FrameSource,
                imageEncoderAt imageEncoder: URL, promptEncoderAt promptEncoder: URL,
                maskDecoderAt maskDecoder: URL) {
        self.imageEncoderURL = imageEncoder
        self.promptEncoderURL = promptEncoder
        self.maskDecoderURL = maskDecoder
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// A segmenter bound to no frame source, for still images only; call
    /// `detect(in:at:avoiding:)`.
    public init(imageEncoderAt imageEncoder: URL, promptEncoderAt promptEncoder: URL,
                maskDecoderAt maskDecoder: URL) {
        self.imageEncoderURL = imageEncoder
        self.promptEncoderURL = promptEncoder
        self.maskDecoderURL = maskDecoder
    }

    // MARK: Picking

    /// Start a fresh pick: segment the thing under `point` on the current
    /// frame. `point` is in canvas coordinates, `rect` the rectangle the
    /// frame is drawn in (a click outside it is ignored). The answer lands
    /// asynchronously in `pick`.
    public func pick(at point: Vector2, in rect: Rectangle) {
        guard let prompt = Self.prompt(for: point, in: rect, label: 1) else { return }
        lock.withLockUnchecked { state in
            state.frozen = state.latest
            state.embeddings = nil
            state.prompts = [prompt]
            state.generation += 1
        }
        kick()
    }

    /// Refine the current pick with a point it must also cover, for the
    /// other half of a thing the mask only partly caught. With no pick
    /// active this starts one, like `pick(at:in:)`.
    public func include(_ point: Vector2, in rect: Rectangle) {
        add(point, in: rect, label: 1)
    }

    /// Refine the current pick with a point it must not cover: shift-click
    /// a stray region and the mask retreats from it. With no pick active
    /// this does nothing.
    public func exclude(_ point: Vector2, in rect: Rectangle) {
        add(point, in: rect, label: 0)
    }

    /// Drop the current pick and its frozen frame.
    public func clear() {
        lock.withLockUnchecked { state in
            state.frozen = nil
            state.embeddings = nil
            state.prompts = []
            state.pick = nil
            state.generation += 1
        }
    }

    private func add(_ point: Vector2, in rect: Rectangle, label: Float) {
        guard let prompt = Self.prompt(for: point, in: rect, label: label) else { return }
        let startsFresh = lock.withLockUnchecked { state -> Bool in
            guard state.frozen != nil else { return true }
            state.prompts.append(prompt)
            state.generation += 1
            return false
        }
        if startsFresh {
            guard label == 1 else { return }
            pick(at: point, in: rect)
            return
        }
        kick()
    }

    /// `point` mapped from the drawn rectangle into the model's square input
    /// space, or `nil` when it falls outside the rectangle.
    private static func prompt(for point: Vector2, in rect: Rectangle,
                               label: Float) -> Prompt? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let u = (point.x - rect.x) / rect.width
        let v = (point.y - rect.y) / rect.height
        guard (0...1).contains(u), (0...1).contains(v) else { return nil }
        return Prompt(x: Float(u * inputEdge), y: Float(v * inputEdge), label: label)
    }

    // MARK: Still images

    /// Pick from a still image, once: segment the thing under `points`
    /// (image pixel coordinates), steered away from any `avoiding` points.
    /// Waits for the models to load on the first call; throws
    /// `Error.unavailable` when they can't load or can't run here. `nil`
    /// when the prompt matched nothing.
    public func detect(in image: Image, at points: [Vector2],
                       avoiding: [Vector2] = []) async throws -> Pick? {
        await ensureLoading().value
        guard let models = lock.withLockUnchecked({ $0.models }) else {
            throw Error.unavailable(status.reason ?? "The models aren't available.")
        }
        let frame = FrameBox(image.currentCGImage())
        let pixels = Rectangle(x: 0, y: 0,
                               width: Double(frame.width), height: Double(frame.height))
        let prompts = points.compactMap { Self.prompt(for: $0, in: pixels, label: 1) }
            + avoiding.compactMap { Self.prompt(for: $0, in: pixels, label: 0) }
        guard !prompts.isEmpty else { return nil }
        let embeddings = try Self.encode(frame, with: models.imageEncoder)
        return try Self.decode(prompts, embeddings: embeddings,
                               frame: frame, models: models)
    }

    // MARK: VisionTracking

    /// The live path only remembers the newest frame: the model runs on
    /// picks, never per frame, so sharing an analyzer with other trackers
    /// costs them nothing.
    func analyze(_ cgImage: CGImage, size: CGSize) async {
        lock.withLockUnchecked { $0.latest = FrameBox(cgImage) }
    }

    // MARK: The worker

    /// Make sure one background worker is draining the pending prompt.
    private func kick() {
        let shouldStart = lock.withLockUnchecked { state -> Bool in
            guard !state.working else { return false }
            state.working = true
            return true
        }
        guard shouldStart else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            await self.ensureLoading().value
            self.drain()
        }
    }

    private struct Job {
        var generation: Int
        var frame: FrameBox
        var prompts: [Prompt]
        var embeddings: Embeddings?
        var models: Models
    }

    /// Answer the newest prompt set; loop while picks or refines land
    /// mid-run. An encode is stored against its frame, so a refine that
    /// arrives during one still reuses it.
    private func drain() {
        while true {
            guard let job = lock.withLockUnchecked({ state -> Job? in
                guard let models = state.models, let frozen = state.frozen,
                      !state.prompts.isEmpty else {
                    state.working = false
                    return nil
                }
                return Job(generation: state.generation, frame: frozen,
                           prompts: state.prompts, embeddings: state.embeddings,
                           models: models)
            }) else { return }

            do {
                let embeddings: Embeddings
                if let cached = job.embeddings {
                    embeddings = cached
                } else {
                    embeddings = try Self.encode(job.frame, with: job.models.imageEncoder)
                    lock.withLockUnchecked { state in
                        // Keyed to the frame, not the generation: a refine
                        // bumps the generation but keeps the frame, and this
                        // encoding is what makes it land in milliseconds.
                        if state.frozen?.cgImage === job.frame.cgImage {
                            state.embeddings = embeddings
                        }
                    }
                }
                let answer = try Self.decode(job.prompts, embeddings: embeddings,
                                             frame: job.frame, models: job.models)
                status.recordSuccess()
                lock.withLockUnchecked { state in
                    if state.generation == job.generation { state.pick = answer }
                }
            } catch {
                status.recordFailure(error)
            }

            let moreArrived = lock.withLockUnchecked { state -> Bool in
                if state.generation != job.generation, status.isAvailable { return true }
                state.working = false
                return false
            }
            if !moreArrived { return }
        }
    }

    // MARK: Running the models

    /// The frame scaled onto the model's square input and encoded: the
    /// expensive step, ~0.2 s, run once per picked frame.
    private static func encode(_ frame: FrameBox, with encoder: MLModel) throws -> Embeddings {
        let edge = Int(inputEdge)
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, edge, edge, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
                            &pixelBuffer)
        guard let buffer = pixelBuffer else {
            throw Error.unavailable("Couldn't allocate the model's input buffer.")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: edge, height: edge, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw Error.unavailable("Couldn't draw into the model's input buffer.")
        }
        context.interpolationQuality = .high
        context.draw(frame.cgImage, in: CGRect(x: 0, y: 0, width: edge, height: edge))

        let output = try encoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["image": buffer]))
        guard let image = output.featureValue(for: "image_embedding")?.multiArrayValue,
              let coarse = output.featureValue(for: "feats_s0")?.multiArrayValue,
              let fine = output.featureValue(for: "feats_s1")?.multiArrayValue else {
            throw Error.unavailable("The image encoder produced no embedding.")
        }
        return Embeddings(image: image, coarse: coarse, fine: fine)
    }

    /// The points through the prompt encoder and mask decoder: the cheap
    /// step, ~10 ms against a cached encoding.
    private static func decode(_ prompts: [Prompt], embeddings: Embeddings,
                               frame: FrameBox, models: Models) throws -> Pick? {
        let points = try MLMultiArray(shape: [1, NSNumber(value: prompts.count), 2],
                                      dataType: .float32)
        let labels = try MLMultiArray(shape: [1, NSNumber(value: prompts.count)],
                                      dataType: .float32)
        for (index, prompt) in prompts.enumerated() {
            points[[0, index, 0] as [NSNumber]] = NSNumber(value: prompt.x)
            points[[0, index, 1] as [NSNumber]] = NSNumber(value: prompt.y)
            labels[[0, index] as [NSNumber]] = NSNumber(value: prompt.label)
        }
        let prompt = try models.promptEncoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["points": points,
                                                           "labels": labels]))
        guard let sparse = prompt.featureValue(for: "sparse_embeddings")?.multiArrayValue,
              let dense = prompt.featureValue(for: "dense_embeddings")?.multiArrayValue else {
            throw Error.unavailable("The prompt encoder produced no embedding.")
        }
        let output = try models.maskDecoder.prediction(
            from: MLDictionaryFeatureProvider(dictionary: [
                "image_embedding": embeddings.image,
                "feats_s0": embeddings.coarse,
                "feats_s1": embeddings.fine,
                "sparse_embedding": sparse,
                "dense_embedding": dense]))
        guard let scores = output.featureValue(for: "scores")?.multiArrayValue,
              let masks = output.featureValue(for: "low_res_masks")?.multiArrayValue else {
            throw Error.unavailable("The mask decoder produced no mask.")
        }

        // Three candidate readings; the best-scored one wins.
        let count = scores.count
        let scoreValues = (0..<count).map { scores[$0].floatValue }
        guard let top = scoreValues.max(),
              let best = scoreValues.firstIndex(of: top) else { return nil }
        return pick(fromMask: masks, candidate: best,
                    score: Double(min(max(top, 0), 1)), frame: frame)
    }

    /// One candidate's mask plane turned into the published `Pick`. The mask
    /// arrives as logits (positive = picked); the gray plane maps a narrow
    /// band around zero to a soft rim, so the upsampled edge lands
    /// anti-aliased instead of stair-stepped, with alpha 50% still sitting
    /// exactly on the model's own boundary.
    private static func pick(fromMask masks: MLMultiArray, candidate: Int,
                             score: Double, frame: FrameBox) -> Pick? {
        let edge = maskEdge
        let plane = edge * edge
        guard masks.count >= (candidate + 1) * plane else { return nil }
        var gray = [UInt8](repeating: 0, count: plane)
        var minX = edge, minY = edge, maxX = -1, maxY = -1
        masks.withUnsafeBufferPointer(ofType: Float16.self) { logits in
            let base = candidate * plane
            for index in 0..<plane {
                let logit = Float(logits[base + index])
                gray[index] = UInt8(min(max(128 + logit * 64, 0), 255))
                if logit > 0 {
                    let x = index % edge, y = index / edge
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        guard let grayImage = SegmentationImages.grayCGImage(fromPlane: gray,
                                                             width: edge, height: edge),
              let matte = SegmentationImages.matteImage(from: grayImage),
              let cutout = SegmentationImages.cutoutImage(frame: frame.cgImage,
                                                          matte: grayImage) else {
            return nil
        }
        let scale = 1.0 / Double(edge)
        let region = Rectangle(x: Double(minX) * scale, y: Double(minY) * scale,
                               width: Double(maxX - minX + 1) * scale,
                               height: Double(maxY - minY + 1) * scale)
        return Pick(matte: matte, cutout: cutout, score: score, region: region)
    }

    // MARK: Loading

    /// The one background load, started by the first pick (or still call),
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
        let missing = [imageEncoderURL, promptEncoderURL, maskDecoderURL].filter {
            !FileManager.default.fileExists(atPath: $0.path)
        }
        guard missing.isEmpty else {
            status.markUnavailable("Model file not found: "
                + missing.map(\.path).joined(separator: ", ")
                + ". Download the models and relaunch.")
            return
        }
        do {
            // CPU + GPU by measurement: the warm encode is the same on every
            // compute-unit setting here (~0.2 s), but letting the Neural
            // Engine specialize these graphs costs ~9 s at load against
            // under a second on the GPU pair.
            var loaded: [MLModel] = []
            for url in [imageEncoderURL, promptEncoderURL, maskDecoderURL] {
                let compiled = try await ModelTracker.compiledModelURL(for: url)
                loaded.append(try await ModelLoader.shared.load(contentsOf: compiled,
                                                                computeUnits: .cpuAndGPU))
            }
            lock.withLockUnchecked { state in
                state.models = Models(imageEncoder: loaded[0],
                                      promptEncoder: loaded[1],
                                      maskDecoder: loaded[2])
            }
        } catch {
            status.markUnavailable("The models at \(imageEncoderURL.deletingLastPathComponent().path) "
                + "couldn't load: \(error.localizedDescription)")
        }
    }
}
