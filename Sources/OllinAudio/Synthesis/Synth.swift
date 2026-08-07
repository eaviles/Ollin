import AVFoundation

/// An instrument a sketch plays.
///
/// ```swift
/// let synth = Synth(.pluck)
///
/// override func mousePressed() {
///     synth.play("C4", for: 0.5)
/// }
/// ```
///
/// Notes are asked for from `draw()` and start on the next block of audio, a few
/// milliseconds later. A `Synth` is polyphonic: several notes sound at once, and
/// when they run out the quietest one already fading is taken first.
///
/// It is also an `AudioSource`, so everything a sketch can read from a
/// microphone it can read from its own playing: `synth.amplitude` to size a
/// shape, `synth.spectrum` to draw one.
///
/// ```swift
/// drawCircle(width / 2, height / 2, 100 + Double(synth.amplitude) * 600)
/// ```
@MainActor
public final class Synth: AudioSource {

    public nonisolated let analyzer: AudioAnalyzer

    private let engine = AVAudioEngine()
    private let events = EventRing()
    private let renderer: SynthRenderer
    private let sampleRate: Double
    private let tapBufferSize: UInt32
    private var sourceNode: AVAudioSourceNode!
    private let delayUnit = AVAudioUnitDelay()
    private let reverbUnit = AVAudioUnitReverb()
    private var tapInstalled = false

    /// Whether the engine is running.
    public private(set) var isRunning = false

    /// The recipe every new note is built from.
    ///
    /// Changing it does not disturb notes already sounding, so a sketch can move
    /// from one sound to another between notes without a click.
    public var voice: Voice {
        didSet {
            guard voice != oldValue else { return }
            events.push(SynthEvent(kind: .changeVoice, voice: voice))
        }
    }

    /// Overall level, `0...1`.
    public var gain: Double {
        get { renderer.gain }
        set { renderer.gain = newValue }
    }

    /// How many notes are sounding right now, tails included.
    public var activeVoiceCount: Int { renderer.activeVoiceCount }

    /// An echo on everything the synth plays, or nil for none.
    public var delay: Delay? {
        didSet { applyDelay() }
    }

    /// A room around everything the synth plays, or nil for none.
    public var reverb: Reverb? {
        didSet { applyReverb() }
    }

    /// Creates an instrument.
    ///
    /// - Parameters:
    ///   - voice: what a note is made of. The presets (`.pluck`, `.bass`,
    ///     `.pad`, `.bell`, `.stab`, `.breath`, `.sine`) are the quick way in.
    ///   - polyphony: how many notes may sound at once, tails included.
    ///   - fftSize: the window the analysis side reads over.
    public init(_ voice: Voice = .pluck, polyphony: Int = 16, fftSize: Int = 1024) {
        let output = engine.outputNode.outputFormat(forBus: 0)
        let rate = output.sampleRate
        self.sampleRate = rate > 0 ? rate : 44100
        self.tapBufferSize = UInt32(max(256, fftSize))
        self.voice = voice
        self.analyzer = AudioAnalyzer(fftSize: fftSize, sampleRate: self.sampleRate, smoothing: 0.5)
        self.renderer = SynthRenderer(
            voice: voice, polyphony: polyphony, sampleRate: self.sampleRate, events: events
        )

        // The chain runs in the output's own channel layout, not in mono. The
        // effect units refuse a format the hardware end of the graph does not
        // use, and the failure is a thrown exception rather than an error to
        // handle. One voice writes one stream of samples either way: the render
        // block copies it to whatever channels the format asks for.
        let channels = min(max(output.channelCount, 1), 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: self.sampleRate, channels: channels)!
        // Built in a free function so the closure is not main-actor isolated:
        // the engine calls it on the render thread, where that check would trap.
        self.sourceNode = makeSynthSourceNode(format: format, renderer: renderer)

        engine.attach(sourceNode)
        engine.attach(delayUnit)
        engine.attach(reverbUnit)
        // The effects are wired in once and left there, mixed all the way dry
        // until a sketch asks for them: rebuilding a running graph to add an
        // echo is how you get a gap in the sound.
        engine.connect(sourceNode, to: delayUnit, format: format)
        engine.connect(delayUnit, to: reverbUnit, format: format)
        engine.connect(reverbUnit, to: engine.mainMixerNode, format: format)
        applyDelay()
        applyReverb()
    }

    // MARK: Playing

    /// Plays a note.
    ///
    /// With a `duration` the note lets go by itself, which is what a sketch
    /// usually wants. Without one it sounds until `noteOff(_:)`, so a key can be
    /// held down.
    ///
    /// - Parameters:
    ///   - pitch: a MIDI number (`60`), a name (`"C4"`), or a `Pitch`.
    ///   - velocity: how hard the note is struck, `0...1`.
    ///   - duration: seconds to hold it, or nil to hold it until let go.
    public func play(_ pitch: Pitch, velocity: Double = 0.8, for duration: Double? = nil) {
        start()
        let samples = duration.map { Int(max(0.001, $0) * sampleRate) } ?? 0
        events.push(SynthEvent(
            kind: .noteOn, pitch: pitch.midi, velocity: velocity,
            durationSamples: max(1, samples)
        ))
    }

    /// Starts a note and holds it until `noteOff(_:)`.
    public func noteOn(_ pitch: Pitch, velocity: Double = 0.8) {
        start()
        events.push(SynthEvent(kind: .noteOn, pitch: pitch.midi, velocity: velocity))
    }

    /// Lets a held note go, so it moves into its release.
    public func noteOff(_ pitch: Pitch) {
        events.push(SynthEvent(kind: .noteOff, pitch: pitch.midi))
    }

    /// Lets every held note go. Their tails still sound.
    public func allNotesOff() {
        events.push(SynthEvent(kind: .allNotesOff))
    }

    /// Plays several notes at once.
    public func play(chord pitches: [Pitch], velocity: Double = 0.8, for duration: Double? = nil) {
        for pitch in pitches { play(pitch, velocity: velocity, for: duration) }
    }

    // MARK: Engine

    /// Starts the audio engine. Called for you by the first note.
    public func start() {
        guard !isRunning else { return }
        installTapIfNeeded()
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            audioNoteOnce("the audio engine could not start (\(error.localizedDescription)).")
        }
    }

    /// Stops the engine and everything sounding.
    public func stop() {
        guard isRunning else { return }
        allNotesOff()
        if tapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        isRunning = false
    }

    private func installTapIfNeeded() {
        guard !tapInstalled else { return }
        installAnalyzerTap(on: engine.mainMixerNode, bufferSize: tapBufferSize, analyzer: analyzer)
        tapInstalled = true
    }

    private func applyDelay() {
        guard let delay else {
            delayUnit.wetDryMix = 0
            return
        }
        delayUnit.delayTime = max(0, delay.time)
        delayUnit.feedback = Float(min(max(0, delay.feedback), 0.95) * 100)
        delayUnit.lowPassCutoff = Float(delay.damping)
        delayUnit.wetDryMix = Float(min(max(0, delay.mix), 1) * 100)
    }

    private func applyReverb() {
        guard let reverb else {
            reverbUnit.wetDryMix = 0
            return
        }
        reverbUnit.loadFactoryPreset(reverb.space.preset)
        reverbUnit.wetDryMix = Float(min(max(0, reverb.mix), 1) * 100)
    }
}

// MARK: - Effects

/// An echo: the sound again, later and quieter each time.
public struct Delay: Sendable, Hashable {
    /// Seconds before the first repeat.
    public var time: Double
    /// How much of each repeat feeds the next, `0...0.95`. Higher runs longer.
    public var feedback: Double
    /// How much of the result is the echo rather than the sound itself, `0...1`.
    public var mix: Double
    /// Where the repeats start losing their top end, in Hz. Lower makes each
    /// repeat duller than the last, the way a real one is.
    public var damping: Double

    public init(time: Double = 0.25, feedback: Double = 0.4, mix: Double = 0.3, damping: Double = 6000) {
        self.time = time
        self.feedback = feedback
        self.mix = mix
        self.damping = damping
    }
}

/// A room the sound is heard in.
public struct Reverb: Sendable, Hashable {
    /// How big the room is.
    public enum Space: String, Sendable, Hashable, CaseIterable, Codable {
        case room, hall, plate, cathedral

        var preset: AVAudioUnitReverbPreset {
            switch self {
            case .room:      return .mediumRoom
            case .hall:      return .largeHall
            case .plate:     return .plate
            case .cathedral: return .cathedral
            }
        }
    }

    public var space: Space
    /// How much of the result is the room rather than the sound itself, `0...1`.
    public var mix: Double

    public init(_ space: Space = .hall, mix: Double = 0.3) {
        self.space = space
        self.mix = mix
    }
}

/// Builds the render block outside any actor, so the audio thread can call it.
///
/// It captures the renderer and nothing else, and everything it touches there
/// was allocated before the first note.
private func makeSynthSourceNode(format: AVAudioFormat, renderer: SynthRenderer) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let frames = Int(frameCount)
        guard let first = buffers.first, let data = first.mData else { return noErr }

        let output = UnsafeMutableBufferPointer(
            start: data.assumingMemoryBound(to: Float.self), count: frames
        )
        renderer.render(into: output, frameCount: frames)

        // Any further channels get the same samples.
        for buffer in buffers.dropFirst() {
            guard let other = buffer.mData else { continue }
            other.assumingMemoryBound(to: Float.self).update(from: output.baseAddress!, count: frames)
        }
        return noErr
    }
}
