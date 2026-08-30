import AVFoundation
import CoreML
import Foundation
import Ollin
import SoundAnalysis
import os

/// One thing the classifier thinks it is hearing, and how sure it is.
///
/// The label is one of *that classifier's* own names: the built-in vocabulary
/// spells them in lower case with underscores (`"dog_bark"`, `"finger_snapping"`,
/// `"electric_guitar"`), and a model you bring spells them however it was
/// trained.
public struct SoundClassification: Sendable, Equatable {
    /// What the classifier heard.
    public let label: String
    /// How sure it is, `0...1`.
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// A sound that just started: a label crossing the classifier's `threshold`
/// after being under it. The trigger half of the surface, where
/// `confidence(of:)` is the level half.
public struct SoundEvent: Sendable, Equatable {
    /// What was heard.
    public let label: String
    /// How sure the classifier was when it crossed.
    public let confidence: Double
    /// When it crossed, in seconds of audio since the classifier started. This
    /// is the sample clock, not the wall clock, so the same audio always
    /// produces the same times.
    public let time: Double
}

/// Names sounds as they happen, so a clap, a bark, a siren, or a guitar can
/// drive a sketch the way a face or a hand does on the seeing side.
///
/// Bind it to anything that makes sound (the microphone, a playing video's
/// soundtrack, an audio file) and read it in `draw()`:
///
/// ```swift
/// let mic = AudioInput()
/// let ears = SoundClassifier(of: mic)
/// override func setup() { try? mic.start() }
/// override func draw() {
///     for event in ears.events() where event.label == "clapping" { flash() }
///     let music = ears.confidence(of: "music")     // a level, not an event
/// }
/// ```
///
/// There are two ways to read it because there are two kinds of question. *Is
/// this music?* is a level that rises and falls: `confidence(of:)`, `top`, and
/// `classifications` answer it. *Did somebody just clap?* happens once:
/// `events()` drains what crossed `threshold` since the last call, and
/// `timeSinceHearing(_:)` says how long ago, for a mark that fades.
///
/// The built-in vocabulary holds 300-odd everyday sounds; `labels` lists them.
/// It is happy to guess, and `"music"` in particular turns up faintly under
/// almost anything, so read `top` and a `threshold` rather than believing every
/// small number.
///
/// A classifier hears a *window* of audio at a time (`windowDuration`), so a
/// short sound is named a fraction of a second after it happens. Shorter
/// windows react sooner and judge on less.
///
/// Live only: under a headless export nothing is playing, so nothing is heard.
/// To put sounds into an export, name them ahead of time with the one-shot
/// `classify(contentsOf:)` and draw against the clock.
@MainActor
public final class SoundClassifier {

    private let hub: AudioTapHub?
    private let engine: SoundClassifierEngine

    /// Listen to `source` with Apple's built-in classifier.
    ///
    /// - Parameters:
    ///   - source: anything that makes sound: an `AudioInput`, an
    ///     `AudioPlayer`, a `Tone`, a playing video.
    ///   - threshold: the confidence a label must reach to count as heard.
    ///   - windowDuration: how much audio each judgment is made from, in
    ///     seconds (clamped to what the classifier supports).
    public init(of source: any AudioTapSource, threshold: Double = 0.6,
                windowDuration: Double = 1.5) {
        engine = SoundClassifierEngine(request: .builtIn, threshold: threshold,
                                       windowDuration: windowDuration)
        hub = SoundClassifier.attach(engine, to: source)
    }

    /// Listen to `source` with a sound-classification model of your own: a
    /// Core ML model that takes audio and reports labeled probabilities (what
    /// Create ML's sound classifier trains).
    public init(of source: any AudioTapSource, model: MLModel, threshold: Double = 0.6,
                windowDuration: Double = 1.5) {
        engine = SoundClassifierEngine(request: .model(model), threshold: threshold,
                                       windowDuration: windowDuration)
        hub = SoundClassifier.attach(engine, to: source)
    }

    /// Listen to `source` with a compiled model on disk (an `.mlmodelc`).
    ///
    /// An `.mlmodel` has to be compiled first, and compiling to a *stable*
    /// path matters: a fresh temporary directory each launch makes Core ML
    /// re-specialize the model every time.
    public convenience init(of source: any AudioTapSource, modelAt url: URL,
                            threshold: Double = 0.6, windowDuration: Double = 1.5) throws {
        try self.init(of: source, model: MLModel(contentsOf: url),
                      threshold: threshold, windowDuration: windowDuration)
    }

    /// Bind the engine to a source, unless this is an export, where there is
    /// nothing to hear.
    private static func attach(_ engine: SoundClassifierEngine,
                               to source: any AudioTapSource) -> AudioTapHub? {
        guard !OllinApp.isRenderingHeadless else {
            engine.status.markUnavailable(
                "sound classification is live only; an export hears nothing. "
                + "Use SoundClassifier.classify(contentsOf:) to name sounds ahead of time.")
            return nil
        }
        let hub = SourceTapHubs.hub(for: source)
        hub.register(engine)
        return hub
    }

    /// Every label above `threshold` right now, most confident first. Empty
    /// when nothing has been recognized yet.
    public var classifications: [SoundClassification] { engine.classifications }

    /// The single most confident label right now, whatever the threshold, or
    /// `nil` before the first judgment.
    public var topClassification: SoundClassification? { engine.top }

    /// How sure the classifier is about one label right now, `0...1`, and `0`
    /// for a label it has not reported.
    public func confidence(of label: String) -> Double { engine.confidence(of: label) }

    /// The sounds that started since the last call, oldest first. Draining, so
    /// each event is handed out once: read it in one place per frame.
    public func events() -> [SoundEvent] { engine.drainEvents() }

    /// Seconds since `label` was last heard crossing the threshold, on the
    /// sample clock. Huge if it never has, so `timeSinceHearing("clapping") < 0.3`
    /// reads as a fading flash.
    public func timeSinceHearing(_ label: String) -> Double { engine.timeSinceHearing(label) }

    /// Every label this classifier can produce, in the order it reports them.
    /// The built-in one knows 300-odd everyday sounds.
    public var labels: [String] { engine.labels }

    /// The confidence a label must reach to count as heard, `0...1`. Settable
    /// live.
    public var threshold: Double {
        get { engine.threshold }
        set { engine.threshold = newValue }
    }

    /// Whether the classifier is running. `false` means `unavailableReason`
    /// says why.
    public var isAvailable: Bool { engine.status.isAvailable }

    /// Why the classifier is not running, or `nil` while it is.
    public var unavailableReason: String? { engine.status.reason }

    /// Stop listening. The source's tap is released once nothing else in this
    /// library is listening to it.
    public func detach() {
        hub?.unregister(engine)
    }
}

// MARK: One-shot

extension SoundClassifier {

    /// Name the sounds in a block of audio you already have, all at once.
    ///
    /// Each label comes back at the highest confidence it reached anywhere in
    /// the clip, strongest first, so a single clap in a long recording still
    /// registers. Runs inline (no waiting), which is what lets a figure, a
    /// test, or a `setup()` use it.
    ///
    /// - Parameters:
    ///   - samples: mono audio, `-1...1`.
    ///   - sampleRate: its rate in Hz.
    ///   - model: a classifier of your own, or `nil` for the built-in one.
    ///   - windowDuration: how much audio each judgment is made from.
    nonisolated public static func classify(_ samples: [Float], sampleRate: Double,
                                model: MLModel? = nil,
                                windowDuration: Double = 1.5) -> [SoundClassification] {
        let kind: ClassifierRequestKind = model.map { .model($0) } ?? .builtIn
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              !samples.isEmpty
        else { return [] }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        return classifyBuffer(buffer, kind: kind, windowDuration: windowDuration)
    }

    /// Name the sounds in an audio file, all at once. See `classify(_:sampleRate:)`.
    nonisolated public static func classify(contentsOf url: URL, model: MLModel? = nil,
                                windowDuration: Double = 1.5) throws -> [SoundClassification] {
        let (samples, rate) = try monoSamples(contentsOf: url)
        return classify(samples, sampleRate: rate, model: model, windowDuration: windowDuration)
    }

    /// Name the sounds in a bundled audio file. Pass the caller's bundle (a
    /// default would resolve to Ollin's own, not yours).
    nonisolated public static func classify(resource name: String, withExtension ext: String, in bundle: Bundle,
                                model: MLModel? = nil,
                                windowDuration: Double = 1.5) throws -> [SoundClassification] {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw AudioError.resourceNotFound("\(name).\(ext)")
        }
        return try classify(contentsOf: url, model: model, windowDuration: windowDuration)
    }

    nonisolated private static func classifyBuffer(_ buffer: AVAudioPCMBuffer, kind: ClassifierRequestKind,
                                       windowDuration: Double) -> [SoundClassification] {
        guard buffer.format.sampleRate > 0, buffer.format.channelCount > 0,
              let request = kind.make(windowDuration: windowDuration)
        else { return [] }
        let analyzer = SNAudioStreamAnalyzer(format: buffer.format)
        let collector = ClassificationCollector()
        do { try analyzer.add(request, withObserver: collector) } catch { return [] }
        analyzer.analyze(buffer, atAudioFramePosition: 0)
        analyzer.completeAnalysis()
        return collector.peaks()
    }
}

/// Reads a whole audio file into mono samples.
func monoSamples(contentsOf url: URL) throws -> ([Float], Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frames = AVAudioFrameCount(file.length)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        return ([], format.sampleRate)
    }
    try file.read(into: buffer)
    let count = Int(buffer.frameLength)
    guard let channels = buffer.floatChannelData, count > 0 else { return ([], format.sampleRate) }
    let channelCount = Int(format.channelCount)
    var mono = [Float](repeating: 0, count: count)
    let inv = Float(1) / Float(channelCount)
    for c in 0..<channelCount {
        let src = channels[c]
        for i in 0..<count { mono[i] += src[i] * inv }
    }
    return (mono, format.sampleRate)
}

// MARK: The engine

/// Which classifier a request is built from.
enum ClassifierRequestKind: @unchecked Sendable {
    case builtIn
    case model(MLModel)

    /// A fresh request, or `nil` when the classifier will not load.
    func make(windowDuration: Double) -> SNClassifySoundRequest? {
        let request: SNClassifySoundRequest?
        switch self {
        case .builtIn: request = try? SNClassifySoundRequest(classifierIdentifier: .version1)
        case .model(let model): request = try? SNClassifySoundRequest(mlModel: model)
        }
        guard let request else { return nil }
        // Out-of-range durations are snapped by the framework, so this only has
        // to be sane, not exact.
        request.windowDuration = CMTime(seconds: max(0.1, windowDuration), preferredTimescale: 48000)
        return request
    }
}

/// Collects whatever the classifier reports, keeping each label's best moment.
/// Used by the one-shot path, where analysis is synchronous.
final class ClassificationCollector: NSObject, SNResultsObserving {
    private var best: [String: Double] = [:]

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        for classification in result.classifications {
            let confidence = classification.confidence
            if confidence > (best[classification.identifier] ?? 0) {
                best[classification.identifier] = confidence
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}

    func peaks() -> [SoundClassification] {
        best.map { SoundClassification(label: $0.key, confidence: $0.value) }
            .sorted { ($0.confidence, $1.label) > ($1.confidence, $0.label) }
    }
}

/// The live half: takes audio on the source's thread, runs the classifier off
/// it, and publishes what it heard.
///
/// `@unchecked Sendable`: every mutable value lives under `lock`, and the
/// SoundAnalysis objects are touched only from `queue`, which is serial.
final class SoundClassifierEngine: NSObject, AudioListening, SNResultsObserving, @unchecked Sendable {

    let status = ListeningStatus()

    private struct State {
        var classifications: [SoundClassification] = []
        var top: SoundClassification?
        var confidences: [String: Double] = [:]
        var lastHeard: [String: Double] = [:]
        var pending: [SoundEvent] = []
        var above: Set<String> = []
        var threshold: Double
        var elapsed: Double = 0        // seconds of audio delivered
        var queued = 0
    }
    private let lock: OSAllocatedUnfairLock<State>
    private let queue = DispatchQueue(label: "ollin.sound-classifier", qos: .userInitiated)
    private let kind: ClassifierRequestKind
    private let windowDuration: Double

    // Touched only on `queue`.
    private var analyzer: SNAudioStreamAnalyzer?
    private var analyzerRate: Double = 0
    private var framePosition: AVAudioFramePosition = 0
    private var knownLabels: [String] = []

    init(request kind: ClassifierRequestKind, threshold: Double, windowDuration: Double) {
        self.kind = kind
        self.windowDuration = windowDuration
        self.lock = OSAllocatedUnfairLock(initialState: State(threshold: threshold))
        super.init()
        // Ask once, up front, so a model that will not load says so before any
        // audio arrives rather than staying silently empty.
        queue.async { [weak self] in
            guard let self else { return }
            guard let request = kind.make(windowDuration: windowDuration) else {
                status.markUnavailable(
                    "the sound classifier could not be loaded on this Mac.")
                return
            }
            knownLabels = request.knownClassifications
        }
    }

    var classifications: [SoundClassification] { lock.withLock { $0.classifications } }
    var top: SoundClassification? { lock.withLock { $0.top } }
    var labels: [String] { queue.sync { knownLabels } }

    var threshold: Double {
        get { lock.withLock { $0.threshold } }
        set { lock.withLock { $0.threshold = min(max(newValue, 0), 1) } }
    }

    func confidence(of label: String) -> Double {
        lock.withLock { $0.confidences[label] ?? 0 }
    }

    func drainEvents() -> [SoundEvent] {
        lock.withLock { state in
            let events = state.pending
            state.pending.removeAll(keepingCapacity: true)
            return events
        }
    }

    func timeSinceHearing(_ label: String) -> Double {
        lock.withLock { state in
            guard let heard = state.lastHeard[label] else { return .greatestFiniteMagnitude }
            return max(0, state.elapsed - heard)
        }
    }

    // MARK: Audio in

    /// Called on the source's audio thread. Copies the block and hands it to
    /// the analysis queue, dropping if that queue has fallen behind (a
    /// classifier is far slower than the audio it judges).
    func hear(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        let count = samples.count
        guard let base = samples.baseAddress, count > 0, sampleRate > 0 else { return }
        let advance = Double(count) / sampleRate
        let accepted = lock.withLock { state -> Bool in
            state.elapsed += advance
            guard state.queued < 4 else { return false }
            state.queued += 1
            return true
        }
        guard accepted else { return }

        guard let box = PCMBox(mono: base, count: count, sampleRate: sampleRate) else {
            lock.withLock { $0.queued -= 1 }
            return
        }
        queue.async { [weak self] in
            self?.analyze(box.buffer)
            self?.lock.withLock { $0.queued -= 1 }
        }
    }

    /// On `queue`. Builds the stream analyzer the first time (the source's rate
    /// is not knowable earlier) and rebuilds it if the rate ever changes.
    private func analyze(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        if analyzer == nil || abs(analyzerRate - rate) > 1 {
            guard let request = kind.make(windowDuration: windowDuration) else { return }
            let fresh = SNAudioStreamAnalyzer(format: buffer.format)
            do { try fresh.add(request, withObserver: self) } catch {
                status.markUnavailable("the sound classifier rejected this audio: \(error.localizedDescription)")
                return
            }
            knownLabels = request.knownClassifications
            analyzer = fresh
            analyzerRate = rate
            framePosition = 0
            status.recordSuccess()
        }
        analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
    }

    // MARK: Results

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let ranked = result.classifications.map {
            SoundClassification(label: $0.identifier, confidence: $0.confidence)
        }
        lock.withLock { state in
            state.top = ranked.first
            state.confidences = Dictionary(ranked.map { ($0.label, $0.confidence) },
                                           uniquingKeysWith: { a, _ in a })
            state.classifications = ranked.filter { $0.confidence >= state.threshold }

            // A label crossing the threshold from below is a sound starting.
            // Holding the set of what is currently above it is what keeps a
            // long note from firing once per window.
            var above: Set<String> = []
            for entry in ranked where entry.confidence >= state.threshold {
                above.insert(entry.label)
                if !state.above.contains(entry.label) {
                    state.pending.append(SoundEvent(label: entry.label,
                                                    confidence: entry.confidence,
                                                    time: state.elapsed))
                }
                state.lastHeard[entry.label] = state.elapsed
            }
            state.above = above
            if state.pending.count > 256 { state.pending.removeFirst(state.pending.count - 256) }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        status.markUnavailable("sound classification stopped: \(error.localizedDescription)")
    }

    func requestDidComplete(_ request: SNRequest) {}
}
