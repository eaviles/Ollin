import AVFoundation

/// Installs a tap that feeds `analyzer` from a node's output, and passes the
/// same audio on to `relay` when the source is also being listened to.
///
/// This is a free (non-isolated) function on purpose: the tap closure runs on
/// the audio render thread. If it were formed inside a `@MainActor` method,
/// Swift would give it main-actor isolation and inject an executor assertion
/// that traps the moment the audio thread invokes it. Forming it here keeps it
/// non-isolated, and it only captures `Sendable` values.
func installAnalyzerTap(
    on node: AVAudioNode, bufferSize: UInt32, analyzer: AudioAnalyzer,
    relay: AudioTapRelay? = nil
) {
    node.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
        analyzer.process(buffer)
        relay?.deliver(buffer)
    }
}

/// The common read surface shared by every audio source. A source owns an
/// `AudioAnalyzer` and forwards the values a sketch reads in `draw()` to it, so
/// `mic.amplitude`, `player.spectrum`, and `tone.bass` all mean the same thing.
///
/// The analyzer is `Sendable` and internally locked, so these reads are safe
/// from any context even though the samples are produced on the audio thread.
public protocol AudioSource: AnyObject {
    /// The DSP the source feeds. Exposed so a sketch can reach the full surface
    /// (`magnitude(in:)`, band helpers) and tune `smoothing`.
    var analyzer: AudioAnalyzer { get }
}

extension AudioSource {
    /// Overall loudness this instant (smoothed RMS), roughly `0...1`.
    public var amplitude: Float { analyzer.amplitude }
    /// Per-bin frequency magnitudes, low frequency first.
    public var spectrum: [Float] { analyzer.spectrum }
    /// The most recent window of raw samples (`-1...1`), for an oscilloscope trace.
    public var waveform: [Float] { analyzer.waveform }
    /// Energy in the low band (20–250 Hz).
    public var bass: Float { analyzer.bass }
    /// Energy in the mid band (250–2000 Hz).
    public var mid: Float { analyzer.mid }
    /// Energy in the high band (2000–8000 Hz).
    public var treble: Float { analyzer.treble }

    /// Damping applied to `amplitude` and `spectrum`, `0...1`. Settable live.
    public var smoothing: Float {
        get { analyzer.smoothing }
        set { analyzer.smoothing = newValue }
    }

    /// Average magnitude across the bins overlapping a frequency range, in Hz.
    public func magnitude(in range: ClosedRange<Double>) -> Float {
        analyzer.magnitude(in: range)
    }

    /// `count` normalized, log-spaced frequency bands ready to draw — see
    /// `AudioAnalyzer.bands(_:)`. Call once per frame with a fixed `count`.
    public func bands(_ count: Int) -> [Float] { analyzer.bands(count) }

    /// Beats detected so far (compare to a stored value to fire once per beat).
    public var beatCount: Int { analyzer.beatCount }
    /// Seconds since the last beat (huge if none yet).
    public var timeSinceBeat: Double { analyzer.timeSinceBeat }
    /// A 0…1 pulse that hits 1 on each beat and decays over ~0.25 s.
    public var beat: Float { analyzer.beat }
    /// Onset threshold (higher = fewer, stronger beats). Default 1.5.
    public var beatSensitivity: Float {
        get { analyzer.beatSensitivity }
        set { analyzer.beatSensitivity = newValue }
    }
}
