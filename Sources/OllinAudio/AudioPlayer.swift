import AVFoundation

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
@MainActor
public final class AudioPlayer: AudioSource {

    public nonisolated let analyzer: AudioAnalyzer

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer
    private let tapBufferSize: UInt32
    private var tapInstalled = false

    /// Whether playback should restart from the top when it reaches the end.
    /// Take effect on the next `play()`.
    public var loops = false

    /// Whether the file is currently playing.
    public var isPlaying: Bool { player.isPlaying }

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
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioError.couldNotDecode(url.lastPathComponent)
        }
        try file.read(into: buffer)
        self.buffer = buffer

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        self.analyzer = AudioAnalyzer(
            fftSize: fftSize,
            sampleRate: sampleRate > 0 ? sampleRate : format.sampleRate,
            smoothing: smoothing
        )
        self.tapBufferSize = UInt32(max(256, fftSize))

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Starts (or restarts) playback from the beginning, analyzing as it plays.
    public func play() {
        installTapIfNeeded()
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        player.stop()
        scheduleBuffer()
        player.play()
    }

    /// Pauses playback, keeping the position.
    public func pause() { player.pause() }

    /// Stops playback and tears down the tap.
    public func stop() {
        player.stop()
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
    }

    private func scheduleBuffer() {
        let options: AVAudioPlayerNodeBufferOptions = loops ? [.loops, .interrupts] : [.interrupts]
        player.scheduleBuffer(buffer, at: nil, options: options)
    }

    private func installTapIfNeeded() {
        guard !tapInstalled else { return }
        installAnalyzerTap(on: engine.mainMixerNode, bufferSize: tapBufferSize, analyzer: analyzer)
        tapInstalled = true
    }
}

/// Errors thrown while loading audio.
public enum AudioError: Error, CustomStringConvertible {
    case resourceNotFound(String)
    case couldNotDecode(String)

    public var description: String {
        switch self {
        case .resourceNotFound(let n): return "Audio resource not found: \(n)"
        case .couldNotDecode(let n): return "Could not decode audio: \(n)"
        }
    }
}
