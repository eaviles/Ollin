import AVFoundation
import Ollin

/// Plays an audio file and analyzes it as it sounds, so a sketch can react to
/// recorded music or field recordings the same way it reacts to the microphone.
///
/// ```swift
/// let song = try AudioPlayer(path: "/path/to/track.m4a")
/// override func setup() { song.loops = true; song.play() }
/// override func draw() {
///     for (i, m) in song.spectrum.prefix(64).enumerated() { … }
/// }
/// ```
///
/// Decodes the usual Apple-supported formats (`.m4a`/AAC, `.mp3`, `.wav`,
/// `.aiff`, `.caf`, …) through AVFoundation.
///
/// Under a headless export nothing audibly plays, so instead of the live
/// engine the player follows the export clock: each exported frame advances a
/// sample playhead through the decoded file and feeds that slice to the
/// analyzer, so frame `k` reads the analysis of the file at `k / fps` seconds
/// after `play()`, identically on every run. Create the player by the end of
/// `setup()` (stored on the sketch) or the per-frame advance never finds it.
@MainActor
public final class AudioPlayer: AudioSource {

    public nonisolated let analyzer: AudioAnalyzer

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer
    private let tapBufferSize: UInt32
    private var tapInstalled = false

    // The export-clock playhead (see the type note): positions in file samples,
    // fractional so any fps divides cleanly.
    private var headlessPlaying = false
    private var headlessArmed = false
    private(set) var headlessPosition = 0.0

    /// Whether playback should restart from the top when it reaches the end.
    /// Take effect on the next `play()`.
    public var loops = false

    /// Whether the file is currently playing.
    public var isPlaying: Bool { headlessPlaying || player.isPlaying }

    /// Loads a file from a filesystem path.
    public convenience init(path: String, fftSize: Int = 1024, smoothing: Float = 0.8) throws {
        try self.init(url: URL(fileURLWithPath: path), fftSize: fftSize, smoothing: smoothing)
    }

    /// Loads a file bundled as a resource. Pass the caller's bundle as `bundle`
    /// (a default would resolve to Ollin's own bundle, not yours).
    public convenience init(
        resource name: String, withExtension ext: String, in bundle: Bundle,
        fftSize: Int = 1024, smoothing: Float = 0.8
    ) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw AudioError.resourceNotFound("\(name).\(ext)")
        }
        try self.init(url: url, fftSize: fftSize, smoothing: smoothing)
    }

    /// Loads a file from a URL.
    public init(url: URL, fftSize: Int = 1024, smoothing: Float = 0.8) throws {
        guard let frames = try AudioFileFrames.read(url), let buffer = frames.buffer() else {
            throw AudioError.couldNotDecode(url.lastPathComponent)
        }
        let format = frames.format
        self.buffer = buffer

        // Live analysis taps the mixer, so the analyzer runs at the mixer's
        // rate; headless feeds the decoded file directly, so it runs at the
        // file's own rate (hardware-independent, which keeps exports
        // deterministic across machines).
        let mixerRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let analysisRate = OllinApp.isRenderingHeadless || mixerRate <= 0
            ? format.sampleRate : mixerRate
        self.analyzer = AudioAnalyzer(
            fftSize: fftSize,
            sampleRate: analysisRate,
            smoothing: smoothing
        )
        self.tapBufferSize = UInt32(max(256, fftSize))

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Where playback stands, which is what decides whether `play()` carries
    /// on or starts from the top.
    private enum Transport { case stopped, playing, paused }
    private var transport = Transport.stopped
    /// Whether the buffer the node holds was scheduled to loop.
    private var scheduledLooping = false

    /// Starts playback, analyzing as it plays. After a `pause()` it carries
    /// on from where the pause left it. Otherwise it starts from the top: on
    /// a file that is playing (so a sound can be struck again), after a
    /// `stop()`, and on a file that has played out.
    /// An engine that will not start leaves `isPlaying` false and says why in
    /// `unavailableReason`.
    public func play() {
        let resumes = transport == .paused && !hasPlayedOut
        if OllinApp.isRenderingHeadless {
            if !resumes { headlessPosition = 0 }
            headlessPlaying = true
            headlessArmed = true
            transport = .playing
            return
        }
        installTapIfNeeded()
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                unavailableReason = "the audio engine could not start: \(error.localizedDescription)"
                return
            }
        }
        unavailableReason = nil
        if !resumes {
            player.stop()
            scheduleBuffer()
        }
        player.play()
        transport = .playing
    }

    /// Why nothing plays, in a sentence worth drawing, or `nil` while the
    /// file plays or has not been asked to. A `play()` that fails writes it,
    /// and the next one that succeeds clears it.
    public private(set) var unavailableReason: String?

    /// Pauses playback, keeping the position: the next `play()` carries on
    /// from here.
    public func pause() {
        guard transport == .playing else { return }
        transport = .paused
        headlessPlaying = false
        pausedAt = livePosition         // the node cannot be asked once it is paused
        player.pause()
    }

    /// Stops playback and tears down the tap. The next `play()` starts from
    /// the top.
    public func stop() {
        transport = .stopped
        headlessPlaying = false
        headlessPosition = 0
        player.stop()
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
    }

    /// How far the live node had played when it was paused, in seconds.
    private(set) var pausedAt: Double?

    /// How far the live node has played into its buffer, in seconds, or nil
    /// while it is not playing. A looping buffer counts on past its length.
    var livePosition: Double? {
        guard let nodeTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: nodeTime), time.sampleRate > 0 else { return nil }
        return Double(time.sampleTime) / time.sampleRate
    }

    /// Whether the file has reached its end, so there is nothing after a
    /// pause to carry on with. A looping file never has.
    private var hasPlayedOut: Bool {
        let rate = buffer.format.sampleRate
        guard rate > 0 else { return true }
        let length = Double(buffer.frameLength) / rate
        if OllinApp.isRenderingHeadless {
            return !loops && headlessPosition / rate >= length
        }
        guard !scheduledLooping, let position = pausedAt else { return false }
        return position >= length
    }

    private func scheduleBuffer() {
        let options: AVAudioPlayerNodeBufferOptions = loops ? [.loops, .interrupts] : [.interrupts]
        scheduledLooping = loops
        player.scheduleBuffer(buffer, at: nil, options: options)
    }

    private func installTapIfNeeded() {
        guard !tapInstalled else { return }
        installAnalyzerTap(on: engine.mainMixerNode, bufferSize: tapBufferSize,
                           analyzer: analyzer, relay: relay, capture: captureRelay)
        tapInstalled = true
    }

    private let relay = AudioTapRelay()
    let captureRelay = CaptureTapRelay()
}

/// The live recorder's lane onto a playing file.
extension AudioPlayer: CaptureAudioSource {
    package func beginAudioCapture(into sink: AudioCaptureSink) {
        captureRelay.set(sink)
        installTapIfNeeded()
    }

    package func endAudioCapture() {
        captureRelay.set(nil)
    }
}

/// A playing file is a sound source anything can listen to. Samples flow while
/// the engine plays, so the export clock's silent path carries none: a sketch
/// that wants words out of a file under an export transcribes it with
/// `SpeechListener.transcribe(contentsOf:)` instead.
extension AudioPlayer: AudioTapSource {
    public var audioTap: AudioTap? {
        get { relay.tap }
        set { relay.tap = newValue }
    }
}

// MARK: Export clock

/// The per-frame advance pass (the one that steps `@Eased` and `Timeline`)
/// also steps the sample playhead while a headless driver runs, feeding each
/// frame's slice of the decoded file to the analyzer, so an exported frame
/// always reads the analysis of the file at the sketch clock's position. The
/// conformance is main-actor isolated, matching the pass that calls it.
extension AudioPlayer: @MainActor FrameAdvancing {
    package func advance(by dt: Double) {
        guard OllinApp.isRenderingHeadless, headlessPlaying else { return }
        if headlessArmed {
            // The dt that elapsed before `play()` isn't playback time.
            headlessArmed = false
            return
        }
        let rate = buffer.format.sampleRate
        let total = Int(buffer.frameLength)
        guard rate > 0, total > 0 else { return }

        // Fractional positions, so a frame rate that doesn't divide the sample
        // rate never drifts; each frame feeds the integer samples it crossed.
        let nextPosition = headlessPosition + dt * rate
        var start = Int(headlessPosition)
        var remaining = Int(nextPosition) - start
        headlessPosition = nextPosition

        while remaining > 0 {
            let index = loops ? start % total : start
            if index >= total {
                headlessPlaying = false
                break
            }
            let count = min(remaining, total - index)
            feed(from: index, count: count)
            start += count
            remaining -= count
        }
        if !loops && Int(headlessPosition) >= total { headlessPlaying = false }
    }

    /// Down-mixes `count` file samples starting at `start` to mono and hands
    /// them to the analyzer, exactly what the live tap would have delivered.
    private func feed(from start: Int, count: Int) {
        guard let channels = buffer.floatChannelData, count > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)
        if channelCount == 1 {
            analyzer.analyze(samples: channels[0] + start, count: count)
            return
        }
        var mono = [Float](repeating: 0, count: count)
        let inv = Float(1) / Float(channelCount)
        for c in 0..<channelCount {
            let src = channels[c] + start
            for i in 0..<count { mono[i] += src[i] * inv }
        }
        mono.withUnsafeBufferPointer { analyzer.analyze(samples: $0.baseAddress!, count: count) }
    }
}

/// Errors thrown while loading audio: a player, a room, a grain source, or a
/// sampled instrument.
public enum AudioError: Error, CustomStringConvertible {
    /// No file of that name in the bundle handed over.
    case resourceNotFound(String)
    /// The file is there and is not something this reads.
    case couldNotDecode(String)
    /// The file read, and holds nothing to play: no samples, or an
    /// instrument whose every recording is missing.
    case empty(String)

    public var description: String {
        switch self {
        case .resourceNotFound(let n): return "Audio resource not found: \(n)"
        case .couldNotDecode(let n): return "Could not decode audio: \(n)"
        case .empty(let n): return "Nothing to play in: \(n)"
        }
    }
}
