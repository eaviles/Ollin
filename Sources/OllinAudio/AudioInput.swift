import AVFoundation
import Ollin

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
        // Don't read the input node's format here — touching the capture device
        // before permission is granted can trip the system. Modern Macs run the
        // input at 48 kHz; the band-query Hz mapping uses this, while the tap
        // itself binds to the device's real format whatever it is.
        self.analyzer = AudioAnalyzer(fftSize: fftSize, sampleRate: 48000, smoothing: smoothing)
        self.tapBufferSize = UInt32(max(256, fftSize))
    }

    /// Begins capturing and analyzing input. Gates on microphone permission: if
    /// it's already granted, capture starts now; if it hasn't been asked yet, the
    /// system prompts and capture starts once the user allows it; if it's denied,
    /// nothing starts (the level stays silent). Touching the input device before
    /// permission is granted is what trips the system, so it's deferred to here.
    public func start() throws {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            try startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                Task { @MainActor in try? self.startEngine() }
            }
        default:
            break   // denied or restricted — stay silent
        }
    }

    /// Stops capturing. Safe to call when not running.
    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func startEngine() throws {
        installAnalyzerTap(on: engine.inputNode, bufferSize: tapBufferSize,
                           analyzer: analyzer, relay: relay)
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    private let relay = AudioTapRelay()
}

/// The microphone is a sound source anything can listen to, so a
/// `SpeechListener` or a `SoundClassifier` binds to it the way it binds to a
/// playing video. Samples flow once capture is running.
extension AudioInput: AudioTapSource {
    public var audioTap: AudioTap? {
        get { relay.tap }
        set { relay.tap = newValue }
    }
}
