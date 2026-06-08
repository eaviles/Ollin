import AVFoundation
import os

/// The generation side: a single oscillator that synthesizes a tone you can hear
/// and analyze. The modest counterpart to the analysis sources — enough for
/// audible feedback, blips, and self-contained audio-reactive demos, short of a
/// full synthesizer.
///
/// ```swift
/// let tone = Tone(frequency: 220, waveform: .sine)
/// override func setup() { tone.play() }
/// override func draw() {
///     tone.frequency = 110 + 440 * (mouseX / width)   // pitch follows the cursor
/// }
/// ```
///
/// `frequency`, `amplitude`, and `waveform` are settable live from `draw()`. The
/// generated signal feeds the same `AudioAnalyzer` as the input sources, so a
/// `Tone` is also readable (`tone.spectrum`, `tone.amplitude`).
@MainActor
public final class Tone: AudioSource {

    /// Oscillator shapes, brightest last.
    public enum Waveform: Sendable {
        case sine, triangle, sawtooth, square
    }

    public nonisolated let analyzer: AudioAnalyzer

    private let engine = AVAudioEngine()
    private let state: ToneState
    private let sampleRate: Double
    private let tapBufferSize: UInt32
    private var sourceNode: AVAudioSourceNode!
    private var tapInstalled = false

    /// Whether the tone is currently sounding.
    public private(set) var isPlaying = false

    /// Pitch in Hz.
    public var frequency: Double {
        get { state.params.withLock { $0.frequency } }
        set { state.params.withLock { $0.frequency = max(0, newValue) } }
    }

    /// Output level, `0...1`.
    public var amplitude: Double {
        get { state.params.withLock { $0.amplitude } }
        set { state.params.withLock { $0.amplitude = max(0, min(1, newValue)) } }
    }

    /// Oscillator shape.
    public var waveform: Waveform {
        get { state.params.withLock { $0.waveform } }
        set { state.params.withLock { $0.waveform = newValue } }
    }

    /// Creates an oscillator. Call `play()` to start it.
    public init(
        frequency: Double = 440, amplitude: Double = 0.3, waveform: Waveform = .sine,
        fftSize: Int = 1024, smoothing: Float = 0.5
    ) {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        self.sampleRate = sr > 0 ? sr : 44100
        self.tapBufferSize = UInt32(max(256, fftSize))
        self.state = ToneState(
            params: Params(
                frequency: max(0, frequency),
                amplitude: max(0, min(1, amplitude)),
                waveform: waveform
            )
        )
        self.analyzer = AudioAnalyzer(fftSize: fftSize, sampleRate: self.sampleRate, smoothing: smoothing)

        let format = AVAudioFormat(standardFormatWithSampleRate: self.sampleRate, channels: 1)!
        // Build the render block in a non-isolated context (see the note on
        // `makeOscillatorNode`): formed inside this `@MainActor` init it would
        // trap when the audio thread calls it.
        self.sourceNode = makeOscillatorNode(format: format, state: state, sampleRate: sampleRate)
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    /// Starts the oscillator.
    public func play() {
        guard !isPlaying else { return }
        installTapIfNeeded()
        engine.prepare()
        try? engine.start()
        isPlaying = true
    }

    /// Stops the oscillator.
    public func stop() {
        guard isPlaying else { return }
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        isPlaying = false
    }

    private func installTapIfNeeded() {
        guard !tapInstalled else { return }
        installAnalyzerTap(on: engine.mainMixerNode, bufferSize: tapBufferSize, analyzer: analyzer)
        tapInstalled = true
    }
}

/// Builds the oscillator's render block as a free (non-isolated) function so the
/// closure isn't main-actor-isolated: the audio engine calls it on the render
/// thread, where a main-actor executor check would trap (SIGILL). It captures
/// only `Sendable` state.
private func makeOscillatorNode(
    format: AVAudioFormat, state st: ToneState, sampleRate sr2: Double
) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let p = st.params.withLock { $0 }
        let inc = 2.0 * Double.pi * p.frequency / sr2
        var phase = st.phase
        for frame in 0..<Int(frameCount) {
            let s = Float(oscillatorSample(phase: phase, waveform: p.waveform) * p.amplitude)
            for buffer in abl {
                let out = buffer.mData!.assumingMemoryBound(to: Float.self)
                out[frame] = s
            }
            phase += inc
            if phase >= 2.0 * Double.pi { phase -= 2.0 * Double.pi }
        }
        st.phase = phase
        return noErr
    }
}

/// One oscillator sample for a phase in `0..<2π`.
private func oscillatorSample(phase: Double, waveform: Tone.Waveform) -> Double {
    let t = phase / (2.0 * Double.pi)   // 0...1 through the cycle
    switch waveform {
    case .sine:
        return sin(phase)
    case .triangle:
        return 4.0 * abs(t - 0.5) - 1.0
    case .sawtooth:
        return 2.0 * t - 1.0
    case .square:
        return t < 0.5 ? 1.0 : -1.0
    }
}

/// The oscillator parameters shared with the render thread.
private struct Params: Sendable {
    var frequency: Double
    var amplitude: Double
    var waveform: Tone.Waveform
}

/// Holds the oscillator's live parameters (behind a lock) and its running phase
/// (touched only by the render block, which the engine calls serially).
private final class ToneState: @unchecked Sendable {
    let params: OSAllocatedUnfairLock<Params>
    var phase: Double = 0
    init(params: Params) { self.params = OSAllocatedUnfairLock(initialState: params) }
}
