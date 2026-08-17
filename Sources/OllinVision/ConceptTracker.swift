import Ollin
import CoreML
import Vision
import CoreGraphics
import Foundation
import os

/// Scores **any phrases you type** against what a camera's frames (or a still
/// image) show. Like `ImageClassifier`, but the vocabulary is yours: give it
/// concepts as plain language ("a spooky scene", "a person waving", "a sunny
/// day") and read how strongly each applies, `0…1`, every frame.
///
/// ```swift
/// let camera = Camera()
/// lazy var ideas = ConceptTracker(camera,
///     imageModelAt: imageURL, textModelAt: textURL, vocabAt: vocabURL,
///     concepts: ["a spooky scene", "a cheerful scene"])
/// override func draw() {
///     let spooky = ideas.confidence(of: "a spooky scene")   // 0…1
/// }
/// ```
///
/// Under it is a contrastive image-text model in two halves, fetched by
/// `Scripts/fetch-models.sh` and never committed: an image encoder Vision runs
/// over the frames, and a text encoder each phrase goes through **once** (its
/// embedding is cached, so a fixed concept set costs one text run per phrase,
/// ever). Both sides land in one shared space; a score is how close the
/// picture's embedding sits to the phrase's.
///
/// The scores are **relative to the concept set**: they are shared out among
/// the phrases (softmax over the cosine similarities, at the model's published
/// temperature) and sum to 1. One phrase alone therefore always reads 1. Give
/// the tracker contrasts. "How spooky does the room look" is the spooky
/// phrase's share against a cheerful one. `similarity(of:)` is the raw cosine
/// for when you want to map the space yourself, and `imageEmbedding` /
/// `embedding(of:)` expose the vectors both scores are computed from.
///
/// Phrases can change while the sketch runs: set `concepts`, or query
/// `confidence(of:)` for a new phrase. A phrase reads 0 until its
/// one-time text encoding lands (a background run, typically well under a
/// frame after the models load).
public final class ConceptTracker: VisionTracking, @unchecked Sendable {

    /// Why a run couldn't happen.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// The model isn't usable here; the text is `unavailableReason`.
        case unavailable(String)

        public var description: String {
            switch self {
            case .unavailable(let reason): return reason
            }
        }
    }

    private struct State {
        /// The image-encoder request, built once the models load.
        var request: CoreMLRequest?
        /// The text encoder, run once per phrase.
        var textModel: MLModel?
        var textInputName = ""
        var textOutputName = ""
        var tokenizer: PhraseTokenizer?
        /// The one background load, started on the first frame (or query).
        var loadTask: Task<Void, Never>?
        /// The concept set, in the order given.
        var concepts: [String] = []
        /// Normalized text embeddings by phrase (lowercased key).
        var textEmbeddings: [String: [Float]] = [:]
        /// Phrases waiting for their one-time text encoding.
        var pendingPhrases: [String] = []
        var encoding = false
        /// The latest frame's normalized image embedding.
        var imageEmbedding: [Float]?
        /// The concept scores over the latest analyzed frame, strongest first.
        var labels: [Classification] = []
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("concept scoring")
    private let imageModelURL: URL
    private let textModelURL: URL
    private let vocabURL: URL

    /// Softmax temperature: the scale contrastive image-text models apply to
    /// cosine similarities before the shares are taken (the published value
    /// the model family trains to).
    private static let logitScale: Float = 100

    // MARK: Reading

    /// The phrases being scored, in the order given. Setting it starts the
    /// one-time text encoding of any phrase not seen before; a new phrase
    /// reads 0 until that lands.
    public var concepts: [String] {
        get { lock.withLockUnchecked { $0.concepts } }
        set {
            lock.withLockUnchecked { $0.concepts = newValue }
            requestEncodings(of: newValue)
        }
    }

    /// Every concept scored over the most recent analyzed frame, strongest
    /// first. Scores are the concepts' shares and sum to 1; a phrase whose
    /// text encoding hasn't landed yet isn't listed.
    public var labels: [Classification] { lock.withLockUnchecked { $0.labels } }

    /// The single strongest concept, or `nil` while there is none.
    public var top: Classification? { labels.first }

    /// One concept's share of the most recent analyzed frame, `0…1`, matched
    /// case-insensitively. A phrase not in `concepts` joins the set (so the
    /// first query registers it); it reads 0 until its encoding lands.
    public func confidence(of phrase: String) -> Double {
        let wanted = phrase.lowercased()
        let (score, known) = lock.withLockUnchecked { state in
            (state.labels.first { $0.label.lowercased() == wanted }?.confidence,
             state.concepts.contains { $0.lowercased() == wanted })
        }
        if !known {
            lock.withLockUnchecked { $0.concepts.append(phrase) }
            requestEncodings(of: [phrase])
        }
        return score ?? 0
    }

    /// The raw cosine similarity between the most recent analyzed frame and
    /// `phrase`, unshared: typically a small positive number (matching pairs
    /// run roughly 0.2…0.4 in this model family), for mapping the space
    /// yourself. 0 until the frame and the phrase's encoding both exist.
    public func similarity(of phrase: String) -> Double {
        let wanted = phrase.lowercased()
        let (image, text) = lock.withLockUnchecked { state in
            (state.imageEmbedding, state.textEmbeddings[wanted])
        }
        guard let image, let text else {
            _ = confidence(of: phrase)   // registers the phrase if new
            return 0
        }
        return Double(Self.dot(image, text))
    }

    /// The most recent analyzed frame's embedding: a unit vector in the
    /// model's shared image-text space, or `nil` before the first frame.
    /// Compare two of them (or one against `embedding(of:)`) with a dot
    /// product.
    public var imageEmbedding: [Double]? {
        lock.withLockUnchecked { $0.imageEmbedding?.map(Double.init) }
    }

    /// A phrase's embedding: the unit vector its score is computed from.
    /// Waits for the models to load; throws when they can't.
    public func embedding(of phrase: String) async throws -> [Double] {
        await ensureLoading().value
        return try encodePhrase(phrase).map(Double.init)
    }

    /// Whether the models have finished loading. `false` covers both "still
    /// loading" (the first-ever load specializes them for this Mac, which can
    /// take several seconds) and "failed"; `unavailableReason` tells the two
    /// apart.
    public var isLoaded: Bool { lock.withLockUnchecked { $0.request != nil } }

    /// Whether the models can run here: the files exist, loaded, and the
    /// compute device can execute them. When `false`, `unavailableReason`
    /// says why.
    public var isAvailable: Bool { status.isAvailable }
    /// Why the models can't run here, or `nil` when they can.
    public var unavailableReason: String? { status.reason }

    // MARK: Creating

    /// Score `source`'s frames (the live camera, or a playing video) against
    /// `concepts`. The three files are the fetched pair of encoders and the
    /// tokenizer vocabulary they were trained with.
    @MainActor
    public init(_ source: any FrameSource,
                imageModelAt imageModel: URL, textModelAt textModel: URL,
                vocabAt vocab: URL, concepts: [String] = []) {
        self.imageModelURL = imageModel
        self.textModelURL = textModel
        self.vocabURL = vocab
        lock.withLockUnchecked { state in
            state.concepts = concepts
            state.pendingPhrases = concepts
        }
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// A tracker bound to no frame source, for still images only; call
    /// `detect(in:)`.
    public init(imageModelAt imageModel: URL, textModelAt textModel: URL,
                vocabAt vocab: URL, concepts: [String] = []) {
        self.imageModelURL = imageModel
        self.textModelURL = textModel
        self.vocabURL = vocab
        lock.withLockUnchecked { state in
            state.concepts = concepts
            state.pendingPhrases = concepts
        }
    }

    /// Score a still image, once, against the tracker's `concepts`. Waits
    /// for the models to load on the first call. Throws `Error.unavailable`
    /// when they can't load (a file is missing) or can't run here.
    public func detect(in image: Image) async throws -> [Classification] {
        await ensureLoading().value
        guard let request = lock.withLockUnchecked({ $0.request }) else {
            throw Error.unavailable(status.reason ?? "The models aren't available.")
        }
        let concepts = lock.withLockUnchecked { $0.concepts }
        var texts: [(String, [Float])] = []
        for phrase in concepts {
            texts.append((phrase, try encodePhrase(phrase)))
        }
        let observations = try await request.perform(on: image.currentCGImage())
        guard let embedding = Self.embedding(in: observations) else {
            throw Error.unavailable("The image encoder produced no embedding.")
        }
        return Self.scores(image: embedding, texts: texts)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        guard let request = lock.withLockUnchecked({ $0.request }) else {
            _ = ensureLoading()
            return
        }
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            guard let embedding = Self.embedding(in: observations) else { return }
            lock.withLockUnchecked { state in
                state.imageEmbedding = embedding
                state.labels = Self.scores(
                    image: embedding,
                    texts: state.concepts.compactMap { phrase in
                        state.textEmbeddings[phrase.lowercased()].map { (phrase, $0) }
                    })
            }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Scoring

    /// The image embedding an image-encoder run produced, normalized.
    private static func embedding(in observations: [any VisionObservation]) -> [Float]? {
        for observation in observations {
            guard let feature = observation as? CoreMLFeatureValueObservation,
                  let array = feature.featureValue.shapedArrayValue(of: Float.self)
            else { continue }
            return normalized(array.scalars)
        }
        return nil
    }

    /// Each concept's share of the picture: cosine similarities scaled by the
    /// model's temperature, shared out (softmax), strongest first.
    private static func scores(image: [Float],
                               texts: [(String, [Float])]) -> [Classification] {
        guard !texts.isEmpty else { return [] }
        let logits = texts.map { dot(image, $0.1) * logitScale }
        let peak = logits.max() ?? 0
        let exponentials = logits.map { expf($0 - peak) }
        let total = exponentials.reduce(0, +)
        return zip(texts, exponentials)
            .map { Classification(label: $0.0, confidence: Double($1 / total)) }
            .sorted { $0.confidence > $1.confidence }
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var sum: Float = 0
        for index in a.indices { sum += a[index] * b[index] }
        return sum
    }

    private static func normalized(_ vector: [Float]) -> [Float] {
        let length = dot(vector, vector).squareRoot()
        guard length > 0 else { return vector }
        return vector.map { $0 / length }
    }

    // MARK: Text encoding

    /// Queue the phrases that haven't been encoded yet and make sure one
    /// background drain is running (after the models load).
    private func requestEncodings(of phrases: [String]) {
        let fresh = lock.withLockUnchecked { state -> [String] in
            let missing = phrases.filter {
                state.textEmbeddings[$0.lowercased()] == nil
                    && !state.pendingPhrases.contains($0)
            }
            state.pendingPhrases.append(contentsOf: missing)
            return missing
        }
        guard !fresh.isEmpty else { return }
        drainEncodings()
    }

    private func drainEncodings() {
        let shouldStart = lock.withLockUnchecked { state -> Bool in
            guard !state.encoding, !state.pendingPhrases.isEmpty else { return false }
            state.encoding = true
            return true
        }
        guard shouldStart else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            await self.ensureLoading().value
            while let phrase = self.lock.withLockUnchecked({ state -> String? in
                state.pendingPhrases.isEmpty ? nil : state.pendingPhrases.removeFirst()
            }) {
                _ = try? self.encodePhrase(phrase)
            }
            self.lock.withLockUnchecked { $0.encoding = false }
            self.rescoreFromCache()
        }
    }

    /// A frame may not arrive for a while (or ever, on the still path); when
    /// text encodings land, re-share the latest frame's scores right away.
    private func rescoreFromCache() {
        lock.withLockUnchecked { state in
            guard let image = state.imageEmbedding else { return }
            state.labels = Self.scores(
                image: image,
                texts: state.concepts.compactMap { phrase in
                    state.textEmbeddings[phrase.lowercased()].map { (phrase, $0) }
                })
        }
    }

    /// One phrase through the text encoder, cached by its lowercased text.
    /// The models must be loaded; throws when they aren't available.
    private func encodePhrase(_ phrase: String) throws -> [Float] {
        let key = phrase.lowercased()
        if let cached = lock.withLockUnchecked({ $0.textEmbeddings[key] }) {
            return cached
        }
        let (model, tokenizer, inputName, outputName) = lock.withLockUnchecked {
            ($0.textModel, $0.tokenizer, $0.textInputName, $0.textOutputName)
        }
        guard let model, let tokenizer else {
            throw Error.unavailable(status.reason ?? "The models aren't available.")
        }
        let tokens = tokenizer.encode(phrase)
        let shaped = MLShapedArray<Int32>(scalars: tokens, shape: [1, tokens.count])
        let input = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLMultiArray(shaped)])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
            throw Error.unavailable("The text encoder produced no embedding.")
        }
        let embedding = Self.normalized(MLShapedArray<Float>(array).scalars)
        lock.withLockUnchecked { $0.textEmbeddings[key] = embedding }
        return embedding
    }

    // MARK: Loading

    /// The one background load, started by the first frame (or query), shared
    /// by everything that waits on it.
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
        let missing = [imageModelURL, textModelURL, vocabURL].filter {
            !FileManager.default.fileExists(atPath: $0.path)
        }
        guard missing.isEmpty else {
            status.markUnavailable("Model file not found: "
                + missing.map(\.path).joined(separator: ", ")
                + ". Download the models and relaunch.")
            return
        }
        do {
            let tokenizer = try PhraseTokenizer(vocabAt: vocabURL)

            // Off the GPU path on purpose: the GPU graph compiler crashes
            // specializing this model family's attention blocks (a fold-into-
            // attention pass dereferences null mid-compile), and the Neural
            // Engine + CPU pair runs both encoders correctly and fast.
            let compiledText = try await ModelTracker.compiledModelURL(for: textModelURL)
            let textModel = try await ModelLoader.shared.load(contentsOf: compiledText,
                                                              computeUnits: .cpuAndNeuralEngine)
            let description = textModel.modelDescription
            guard let inputName = description.inputDescriptionsByName.keys.first,
                  let outputName = description.outputDescriptionsByName.keys.first,
                  description.inputDescriptionsByName.count == 1
            else {
                status.markUnavailable("The text encoder at \(textModelURL.path) "
                    + "doesn't have the one-input, one-output shape.")
                return
            }

            let compiledImage = try await ModelTracker.compiledModelURL(for: imageModelURL)
            let imageModel = try await ModelLoader.shared.load(contentsOf: compiledImage,
                                                               computeUnits: .cpuAndNeuralEngine)
            var request = CoreMLRequest(model: try CoreMLModelContainer(model: imageModel))
            // The model family's published preprocessing: the short side
            // scaled to the input size, the long side cropped around the
            // center.
            request.cropAndScaleAction = .centerCrop

            lock.withLockUnchecked { state in
                state.tokenizer = tokenizer
                state.textModel = textModel
                state.textInputName = inputName
                state.textOutputName = outputName
                state.request = request
            }
            drainEncodings()
        } catch {
            status.markUnavailable("The models at \(imageModelURL.path) and "
                + "\(textModelURL.path) couldn't load: \(error.localizedDescription)")
        }
    }
}
