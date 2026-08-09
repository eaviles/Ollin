import AVFoundation
import Foundation
import Ollin
import Speech
import os

/// A stretch of speech the recognizer has committed to: it will not be revised
/// again.
public struct SpokenPhrase: Sendable, Equatable {
    /// The words, as the recognizer finally settled on them.
    public let text: String
    /// When the phrase started, in seconds of audio since listening began.
    public let start: Double
    /// How long it lasted, in seconds.
    public let duration: Double
}

/// Turns speech into words a sketch can draw and act on, live.
///
/// Bind it to anything that makes sound (the microphone, a playing video's
/// soundtrack) and read it in `draw()`:
///
/// ```swift
/// let mic = AudioInput()
/// let speech = SpeechListener(of: mic)
/// override func setup() { try? mic.start() }
/// override func draw() {
///     background(.black)
///     drawText(speech.caption, at: center)
/// }
/// ```
///
/// **A caption and a transcript are different things, and that is the whole
/// design.** Recognition works by guessing early and correcting itself: the
/// words on screen a moment ago may not be the words it settles on. So there
/// are two reads. `caption` is the running best guess, including the tail it
/// might still change, which is what you draw. `transcript` and `phrases()` are
/// what it committed to, which is what you act on. Triggering off `caption`
/// means acting on a word that can be taken back.
///
/// Recognition runs entirely on this Mac. There is no consent prompt for it and
/// nothing is sent anywhere; the microphone has its own permission, which
/// `AudioInput.start()` asks for. The first use of a language may install its
/// model, which takes a moment and needs the network: `unavailableReason` says
/// so while it happens, and the listener starts on its own when it lands.
///
/// Live only: under a headless export nothing is playing, so nothing is heard.
/// To put words into an export, transcribe ahead of time with
/// `transcribe(contentsOf:)` and draw them against the clock.
@MainActor
public final class SpeechListener {

    private let hub: AudioTapHub?
    private let engine: SpeechEngine

    /// Listen to `source` in `locale`, defaulting to the Mac's own language.
    ///
    /// A language the recognizer does not know leaves the listener
    /// unavailable, with `unavailableReason` naming it, rather than quietly
    /// hearing nothing.
    public init(of source: any AudioTapSource, locale: Locale = .current) {
        engine = SpeechEngine(locale: locale)
        if OllinApp.isRenderingHeadless {
            engine.status.markUnavailable(
                "speech recognition is live only; an export hears nothing. "
                + "Use SpeechListener.transcribe(contentsOf:) to get the words ahead of time.")
            hub = nil
        } else {
            let hub = SourceTapHubs.hub(for: source)
            hub.register(engine)
            self.hub = hub
            engine.start()
        }
    }

    /// The running best guess: everything heard so far, trimmed to its last
    /// `captionWords` words, with the tail still liable to change. What to draw.
    public var caption: String { engine.caption }

    /// Only what the recognizer has committed to, from the beginning. What to
    /// act on, and what to keep.
    public var transcript: String { engine.transcript }

    /// The phrases committed to since the last call, oldest first. Draining, so
    /// each phrase is handed out once: read it in one place per frame.
    ///
    /// This is the trigger surface. A word in `caption` can still be taken
    /// back; a word here cannot.
    public func phrases() -> [SpokenPhrase] { engine.drainPhrases() }

    /// The most recent committed phrase, or `nil` before the first one.
    public var latest: SpokenPhrase? { engine.latest }

    /// How many words `caption` keeps. Default 14, about a line.
    public var captionWords: Int {
        get { engine.captionWords }
        set { engine.captionWords = max(1, newValue) }
    }

    /// The language being recognized, resolved to one the recognizer knows.
    public var locale: Locale { engine.resolvedLocale }

    /// Whether recognition is running. `false` means `unavailableReason` says
    /// why, including while a language model installs.
    public var isAvailable: Bool { engine.status.isAvailable }

    /// Whether the recognizer has finished starting and is taking audio.
    ///
    /// Starting takes a moment (longer the first time a language is used), and
    /// `isAvailable` only reports that nothing is *wrong*. Audio that arrives
    /// before this goes true is held rather than dropped, so the first words
    /// into a microphone still land.
    public var isListening: Bool { engine.isListening }

    /// Why recognition is not running, or `nil` while it is.
    public var unavailableReason: String? { engine.status.reason }

    /// Forget everything heard so far: `caption`, `transcript`, and the
    /// undrained phrases. Recognition keeps running.
    public func reset() { engine.reset() }

    /// Stop listening. The source's tap is released once nothing else in this
    /// library is listening to it.
    public func detach() {
        hub?.unregister(engine)
        engine.stop()
    }

    /// The languages this Mac can recognize.
    nonisolated public static var supportedLocales: [Locale] {
        get async { await SpeechTranscriber.supportedLocales }
    }
}

// MARK: One-shot

extension SpeechListener {

    /// Transcribe a block of audio you already have, all at once, and hand back
    /// what was said.
    ///
    /// This is the deterministic path: the same audio always gives the same
    /// words, so it works in `setup()`, in a test, and in an export where
    /// nothing is playing. Call it from a synchronous place with `waitFor`:
    ///
    /// ```swift
    /// let said = try waitFor { try await SpeechListener.transcribe(samples, sampleRate: 44100) }
    /// ```
    ///
    /// - Parameters:
    ///   - samples: mono audio, `-1...1`.
    ///   - sampleRate: its rate in Hz.
    ///   - locale: the language to recognize, defaulting to the Mac's own.
    nonisolated public static func transcribe(_ samples: [Float], sampleRate: Double,
                                  locale: Locale = .current) async throws -> String {
        guard !samples.isEmpty, sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return "" }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        return try await transcribe(buffers: [buffer], locale: locale)
    }

    /// Transcribe an audio or video file, all at once. See
    /// `transcribe(_:sampleRate:)`.
    nonisolated public static func transcribe(contentsOf url: URL,
                                  locale: Locale = .current) async throws -> String {
        let (samples, rate) = try monoSamples(contentsOf: url)
        return try await transcribe(samples, sampleRate: rate, locale: locale)
    }

    /// Transcribe a bundled audio file. Pass the caller's bundle (a default
    /// would resolve to Ollin's own, not yours).
    nonisolated public static func transcribe(resource name: String, withExtension ext: String, in bundle: Bundle,
                                  locale: Locale = .current) async throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw AudioError.resourceNotFound("\(name).\(ext)")
        }
        return try await transcribe(contentsOf: url, locale: locale)
    }

    /// The shared one-shot engine: prepare a transcriber, push every buffer
    /// through it, and join the committed text.
    nonisolated static func transcribe(buffers: [AVAudioPCMBuffer], locale: Locale) async throws -> String {
        guard let prepared = try await SpeechEngine.prepareTranscriber(for: locale) else {
            return ""
        }
        let transcriber = prepared.transcriber
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: stream)

        let collector = Task { () -> String in
            var committed: [String] = []
            for try await result in transcriber.results where result.isFinal {
                committed.append(String(result.text.characters))
            }
            return committed.joined()
        }

        if let converter = SpeechConverter(to: prepared.format) {
            for buffer in buffers {
                if let converted = converter.convert(buffer) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = (try? await collector.value) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Runs a one-shot listening call and parks the caller until it is ready, so a
/// synchronous context can transcribe inline:
///
/// ```swift
/// let said = try waitFor { try await SpeechListener.transcribe(contentsOf: url) }
/// ```
///
/// Built for the places a sketch is synchronous by design: `setup()`, or a
/// deterministic export that must hold the words before its first frame
/// renders. It parks the calling thread, so never call it from an async context
/// (just `await` there), and do not touch the sketch from inside the closure:
/// a `Sketch` is main-actor isolated, so the read would wait on the thread that
/// is already waiting.
public func waitFor<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let box = WaitBox<T>()
    Task.detached(priority: .userInitiated) {
        do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
        box.done.signal()
    }
    box.done.wait()
    return try box.result!.get()
}

/// Carries a result back across the wait. Sound because the caller is parked
/// for the whole crossing, so nothing is touched from two threads at once and
/// the semaphore orders the trip back.
private final class WaitBox<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
    let done = DispatchSemaphore(value: 0)
}

// MARK: The engine

/// Converts whatever a source produces into the one format the recognizer
/// takes (16 kHz mono, as it happens). Not `Sendable`: it is used from one
/// place at a time, on the queue that owns it.
final class SpeechConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init?(to target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return nil }
        return out
    }
}

/// The live half: takes audio on the source's thread, feeds the recognizer off
/// it, and publishes what came back.
///
/// `@unchecked Sendable`: every published value lives under `lock`, the
/// converter is touched only from `queue` (serial), and the analyzer is an
/// actor of its own.
final class SpeechEngine: AudioListening, @unchecked Sendable {

    let status = ListeningStatus()

    private struct State {
        var committed: [String] = []
        var volatileTail = ""
        var pending: [SpokenPhrase] = []
        var latest: SpokenPhrase?
        var captionWords = 14
        var elapsed = 0.0
        var running = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "ollin.speech-listener", qos: .userInitiated)
    private let requestedLocale: Locale
    private let resolved = OSAllocatedUnfairLock<Locale?>(initialState: nil)

    // Touched only on `queue`.
    private var converter: SpeechConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var preroll: [PCMBox] = []
    private let prerollLimit = 5.0

    private var tasks: [Task<Void, Never>] = []

    init(locale: Locale) {
        self.requestedLocale = locale
    }

    var resolvedLocale: Locale { resolved.withLock { $0 } ?? requestedLocale }

    var transcript: String {
        lock.withLock { $0.committed.joined() }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var caption: String {
        let (all, words) = lock.withLock { ($0.committed.joined() + $0.volatileTail, $0.captionWords) }
        return SpeechEngine.tail(of: all, words: words)
    }

    var latest: SpokenPhrase? { lock.withLock { $0.latest } }

    var isListening: Bool { lock.withLock { $0.running } }

    var captionWords: Int {
        get { lock.withLock { $0.captionWords } }
        set { lock.withLock { $0.captionWords = newValue } }
    }

    func drainPhrases() -> [SpokenPhrase] {
        lock.withLock { state in
            let phrases = state.pending
            state.pending.removeAll(keepingCapacity: true)
            return phrases
        }
    }

    func reset() {
        lock.withLock { state in
            state.committed.removeAll()
            state.volatileTail = ""
            state.pending.removeAll()
            state.latest = nil
        }
    }

    /// The last `words` words of `text`, which is what keeps a caption from
    /// growing off the side of the canvas.
    static func tail(of text: String, words: Int) -> String {
        let pieces = text.split(whereSeparator: \.isWhitespace)
        return pieces.suffix(words).joined(separator: " ")
    }

    // MARK: Lifecycle

    /// Prepares a transcriber for `locale`, installing its model if this Mac
    /// does not have it yet. `nil` when the language is not one the recognizer
    /// knows.
    static func prepareTranscriber(
        for locale: Locale
    ) async throws -> (transcriber: SpeechTranscriber, format: AVAudioFormat)? {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        else { return nil }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        _ = try? await AssetInventory.reserve(locale: supported)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { return nil }
        return (transcriber, format)
    }

    func start() {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let prepared = try await SpeechEngine.prepareTranscriber(for: requestedLocale)
                else {
                    status.markUnavailable(
                        "speech recognition has no model for "
                        + (requestedLocale.identifier) + " on this Mac.")
                    return
                }
                resolved.withLock { $0 = prepared.transcriber.selectedLocales.first }
                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                let analyzer = SpeechAnalyzer(modules: [prepared.transcriber])
                try await analyzer.start(inputSequence: stream)
                queue.async { [weak self] in
                    guard let self else { return }
                    converter = SpeechConverter(to: prepared.format)
                    self.continuation = continuation
                    // Whatever arrived while the recognizer was getting ready
                    // goes in now, oldest first: the first thing said into a
                    // microphone is usually the thing worth hearing.
                    for held in preroll { push(held) }
                    preroll.removeAll()
                }
                lock.withLock { $0.running = true }
                status.recordSuccess()
                await collect(from: prepared.transcriber)
            } catch {
                status.markUnavailable(
                    "speech recognition could not start: \(error.localizedDescription)")
            }
        }
        tasks.append(task)
        // Say what is happening while a language model installs, rather than
        // reading as broken for the minute it takes.
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !(lock.withLock { $0.running }), status.isAvailable else { return }
            status.markUnavailable(
                "installing the speech model for \(requestedLocale.identifier); "
                + "listening starts when it lands.")
        }
    }

    private func collect(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                receive(String(result.text.characters), isFinal: result.isFinal,
                        start: result.range.start.seconds, duration: result.range.duration.seconds)
            }
        } catch {
            status.markUnavailable("speech recognition stopped: \(error.localizedDescription)")
        }
    }

    /// One result from the recognizer, committed or not. This is the whole
    /// caption-versus-transcript rule in one place: a committed result is
    /// appended and handed out as a phrase, an uncommitted one *replaces* the
    /// tail, because that is exactly what the recognizer is doing to it.
    func receive(_ text: String, isFinal: Bool, start: Double, duration: Double) {
        lock.withLock { state in
            guard isFinal else {
                state.volatileTail = text
                return
            }
            state.committed.append(text)
            state.volatileTail = ""
            let phrase = SpokenPhrase(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start.isFinite ? start : state.elapsed,
                duration: duration.isFinite ? duration : 0)
            guard !phrase.text.isEmpty else { return }
            state.pending.append(phrase)
            state.latest = phrase
            if state.pending.count > 256 {
                state.pending.removeFirst(state.pending.count - 256)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.continuation?.finish()
            self?.continuation = nil
        }
        for task in tasks { task.cancel() }
        tasks.removeAll()
        lock.withLock { $0.running = false }
    }

    // MARK: Audio in

    /// Called on the source's audio thread. Copies the block and hands it to
    /// the conversion queue: resampling is not work for the audio thread, and
    /// nothing is dropped, because a dropped block is a missing word.
    func hear(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        let count = samples.count
        guard let base = samples.baseAddress, count > 0, sampleRate > 0 else { return }
        lock.withLock { $0.elapsed += Double(count) / sampleRate }
        guard let box = PCMBox(mono: base, count: count, sampleRate: sampleRate) else { return }

        queue.async { [weak self] in
            guard let self else { return }
            guard continuation != nil else { return hold(box) }
            push(box)
        }
    }

    /// On `queue`. Converts and hands one block to the recognizer.
    private func push(_ box: PCMBox) {
        guard let converter, let continuation,
              let converted = converter.convert(box.buffer)
        else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// On `queue`. Keeps a block until the recognizer is ready, discarding the
    /// oldest once there is more than `prerollLimit` seconds of it: a listener
    /// that has not started in that long is not about to.
    private func hold(_ box: PCMBox) {
        preroll.append(box)
        var seconds = preroll.reduce(0.0) { $0 + Double($1.buffer.frameLength) / $1.buffer.format.sampleRate }
        while seconds > prerollLimit, let oldest = preroll.first {
            seconds -= Double(oldest.buffer.frameLength) / oldest.buffer.format.sampleRate
            preroll.removeFirst()
        }
    }
}
