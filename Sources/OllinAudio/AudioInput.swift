import AVFoundation

/// Live audio from the system's default input (the microphone), analyzed in real
/// time. Create it in `setup()`, `start()` it, then read `amplitude`, `spectrum`,
/// or a band (`bass`/`mid`/`treble`) in `draw()` to drive geometry.
///
/// ```swift
/// let mic = AudioInput()
/// override func setup() { try? mic.start() }
/// override func draw() {
///     let r = 100 + Double(mic.amplitude) * 800
///     drawCircle(width / 2, height / 2, r * scale)
/// }
/// ```
///
/// Capturing the microphone needs the user's permission; `start()` requests it
/// the first time. Until it's granted the level reads as silence.
@MainActor
public final class AudioInput: AudioSource {

    public nonisolated let analyzer: AudioAnalyzer

    private let engine = AVAudioEngine()
    private let tapBufferSize: UInt32

    /// Whether capture is currently running.
    public private(set) var isRunning = false

    /// Creates an input bound to the default capture device.
    ///
    /// - Parameters:
    ///   - fftSize: FFT window length (see `AudioAnalyzer`).
    ///   - smoothing: response damping, `0...1`.
    public init(fftSize: Int = 1024, smoothing: Float = 0.8) {
        let sampleRate = engine.inputNode.inputFormat(forBus: 0).sampleRate
        self.analyzer = AudioAnalyzer(
            fftSize: fftSize,
            sampleRate: sampleRate > 0 ? sampleRate : 44100,
            smoothing: smoothing
        )
        self.tapBufferSize = UInt32(max(256, fftSize))
    }

    /// Begins capturing and analyzing input. Requests microphone access on first
    /// use. Throws if the audio engine can't start.
    public func start() throws {
        guard !isRunning else { return }
        requestAccessIfNeeded()
        installAnalyzerTap(on: engine.inputNode, bufferSize: tapBufferSize, analyzer: analyzer)
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stops capturing. Safe to call when not running.
    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func requestAccessIfNeeded() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }
}
