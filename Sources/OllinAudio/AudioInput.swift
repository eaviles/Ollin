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
    public var isRunning: Bool { phase == .running }

    /// Where a start stands. `asking` is a start waiting on the system's
    /// prompt: the answer belongs to it, and only while it still stands.
    private enum Phase { case stopped, asking, running }
    private var phase = Phase.stopped

    /// Creates an input bound to the default capture device.
    ///
    /// - Parameters:
    ///   - fftSize: FFT window length (see `AudioAnalyzer`).
    ///   - smoothing: response damping, `0...1`.
    public init(fftSize: Int = 1024, smoothing: Float = 0.8) {
        // Don't read the input node's format here: touching the capture device
        // before permission is granted can trip the system. Modern Macs run the
        // input at 48 kHz; the band-query Hz mapping uses this, while the tap
        // itself binds to the device's real format whatever it is.
        let analyzer = AudioAnalyzer(fftSize: fftSize, sampleRate: 48000, smoothing: smoothing)
        let bufferSize = UInt32(max(256, fftSize))
        self.analyzer = analyzer
        self.tapBufferSize = bufferSize
        let engine = self.engine, relay = self.relay
        self.device = Device(
            installTap: {
                installAnalyzerTap(on: engine.inputNode, bufferSize: bufferSize,
                                   analyzer: analyzer, relay: relay)
            },
            removeTap: { engine.inputNode.removeTap(onBus: 0) },
            start: {
                engine.prepare()
                try engine.start()
            },
            stop: { engine.stop() })
    }

    /// The capture engine's four calls, behind closures the tests replace: a
    /// test must not open the microphone, and the order these are called in
    /// is what the lifecycle around them has to get right.
    struct Device {
        var installTap: () -> Void
        var removeTap: () -> Void
        var start: () throws -> Void
        var stop: () -> Void
    }
    var device: Device

    /// Where the permission stands, and the call that puts the system's prompt
    /// up. The tests replace both: a test must never put a real prompt on
    /// somebody's screen, or wait on the answer to one.
    package static var authorizationStatus: () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }
    package static var requestAccess: (@escaping @Sendable (Bool) -> Void) -> Void = { answer in
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: answer)
    }

    /// Begins capturing and analyzing input. Gates on microphone permission: if
    /// it's already granted, capture starts now; if it hasn't been asked yet, the
    /// system prompts and capture starts once the user allows it; if it's denied,
    /// nothing starts (the level stays silent) and `unavailableReason` says so.
    /// It throws for what it can see for itself, an engine that will not start
    /// on the granted path; anything that goes wrong after the prompt has
    /// returned lands in `unavailableReason` instead, since by then there is
    /// no caller left to throw to. Touching the input device before permission
    /// is granted is what trips the system, so it's deferred to here.
    public func start() throws {
        // A start that is already waiting on the prompt is the start: asking
        // again would bring a second answer, and a second tap with it.
        guard phase == .stopped else { return }
        unavailableReason = nil
        switch AudioInput.authorizationStatus() {
        case .authorized:
            try startEngine()
        case .notDetermined:
            phase = .asking
            AudioInput.requestAccess { granted in
                Task { @MainActor in
                    // The answer belongs to the start that is waiting on it.
                    // A `stop()` since then called that start off, and a
                    // second answer to one prompt finds the capture running.
                    guard self.phase == .asking else { return }
                    self.phase = .stopped
                    guard granted else {
                        self.unavailableReason = "microphone access was refused"
                        return
                    }
                    do { try self.startEngine() }
                    catch { self.unavailableReason = "the audio engine could not start: \(error.localizedDescription)" }
                }
            }
        default:
            unavailableReason = "microphone access is denied or restricted for this app"
        }
    }

    /// Why nothing is being captured, in a sentence worth drawing, or `nil`
    /// while nothing has gone wrong. `start()` throws for what it can see
    /// itself; this carries a refused, denied or restricted microphone, and
    /// what went wrong once the permission prompt has returned and there is
    /// no caller left to throw to.
    public private(set) var unavailableReason: String?

    /// Stops capturing. Safe to call when not running. Called while the
    /// system's prompt is still up, it calls the start off: the answer, when
    /// it comes, opens nothing.
    public func stop() {
        switch phase {
        case .stopped:
            return
        case .asking:
            phase = .stopped
        case .running:
            device.removeTap()
            device.stop()
            phase = .stopped
        }
    }

    private func startEngine() throws {
        device.installTap()
        do {
            try device.start()
        } catch {
            // The tap is the only one the node allows. Left in place, the
            // next start would install a second, which the engine answers
            // with an exception.
            device.removeTap()
            throw error
        }
        phase = .running
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
