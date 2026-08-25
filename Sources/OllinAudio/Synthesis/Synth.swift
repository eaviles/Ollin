import AVFoundation
import Ollin

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
    /// The units the chain is currently wired as, one per effect, in order.
    private var effectUnits: [AVAudioUnit] = []
    /// The kinds those units are, which is what a rebuild is decided against.
    private var wiredKinds: [Effect.Kind] = []
    private var tapInstalled = false
    /// What a sketch asked for while it was being exported, and the clock those
    /// requests are measured against. All three are untouched on the live path.
    var recorded: [RecordedNote] = []
    /// Where the instrument was and where it was heard from, whenever either
    /// changed. Empty unless the sketch placed it, which is what keeps an
    /// export of an unplaced instrument exactly what it was before.
    var recordedPoses: [RecordedPose] = []
    var exportClock: Double = 0
    /// The offline machine, once an export has asked for a soundtrack.
    var offline: OfflineRender?
    /// The voice and polyphony an offline render has to be built with.
    let startingVoice: Voice
    let polyphony: Int

    /// Whether the engine is running.
    public private(set) var isRunning = false

    /// While `true`, requests to start a new note are dropped: the take
    /// transport holds the instrument quiet while it re-simulates frames that
    /// should pass unheard. Releases and notes already sounding still apply.
    package var transportMuted = false

    /// Where this instrument is in the scene, if a sketch has placed it.
    /// See ``place(at:heardFrom:)``.
    lazy var spatial = SpatialPlacement(owner: self)

    /// How far a sound carries. Held here rather than on the placement so that
    /// an export can read it without a live environment node existing.
    var placementRange: ClosedRange<Double> = 1...50

    /// The listener, once a sketch has placed this instrument. The effects hang
    /// off it from then on.
    private var listener: AVAudioEnvironmentNode?

    /// The node that carries a placed instrument's position. The source node is
    /// the one the engine will spatialize, because it is the one feeding the
    /// listener.
    var spatialMixing: AVAudioMixing? { sourceNode }

    /// The recipe every new note is built from.
    ///
    /// Changing it does not disturb notes already sounding, so a sketch can move
    /// from one sound to another between notes without a click.
    public var voice: Voice {
        didSet {
            guard voice != oldValue else { return }
            emit(SynthEvent(kind: .changeVoice, voice: voice))
        }
    }

    /// Overall level, `0...1`.
    public var gain: Double {
        get { renderer.gain }
        set { renderer.gain = newValue }
    }

    /// How many notes are sounding right now, tails included.
    public var activeVoiceCount: Int { renderer.activeVoiceCount }

    /// How hard a driven voice is being bowed or blown, `0...1`.
    ///
    /// The bowed string and the blown tube keep sounding only while something
    /// keeps driving them, so this is the expressive control for those voices:
    /// move it while a note is held and the note changes under your hand, which
    /// is what a player does and what an envelope cannot do.
    ///
    /// ```swift
    /// synth.noteOn("G3")
    /// // in draw(), for as long as the note is held:
    /// synth.drive = 0.3 + 0.5 * abs(sin(time * 2))
    /// ```
    ///
    /// Every voice shares it, which is right: one bow and one breath. The
    /// sources that are set going once and then fade (a wave, a plucked string,
    /// a struck body) ignore it entirely.
    public var drive: Double {
        get { renderer.drive }
        set { renderer.drive = newValue }
    }

    /// The recordings a sampled voice plays.
    ///
    /// Set separately from ``voice`` rather than being part of it, because a
    /// voice travels to the audio thread inside a note and has to be copyable
    /// a word at a time, where recordings are megabytes on the heap. So the
    /// voice says how to play them and this says which.
    ///
    /// ```swift
    /// synth.instrument = SampledInstrument.builtin
    /// synth.voice = Voice(sampled: Sampled())
    /// ```
    ///
    /// Set it before the notes that need it. Notes already sounding keep the
    /// recordings they started on.
    public var instrument: SampledInstrument? {
        get { renderer.instrument }
        set { renderer.instrument = newValue }
    }

    /// Everything done to the sound after it is made, in order.
    ///
    /// ```swift
    /// synth.effects = [
    ///     .distortion(Distortion(.softClip, mix: 0.3)),
    ///     .delay(Delay(time: 0.28)),
    ///     .reverb(Reverb(.hall, mix: 0.4)),
    /// ]
    /// ```
    ///
    /// Order is the point: a distorted echo and an echo of a distorted sound
    /// are different things. Changing a setting costs nothing, and changing
    /// which effects are in the chain rewires it, which the engine does without
    /// interrupting what is playing.
    public var effects: [Effect] = [] {
        didSet { applyEffects() }
    }

    /// An echo on everything the synth plays, or nil for none.
    ///
    /// A view over ``effects``: the first echo in the chain, or where one goes
    /// if there is not one yet. Here because it was here before the chain was,
    /// and because one echo is what most sketches want.
    public var delay: Delay? {
        get {
            for case .delay(let delay) in effects { return delay }
            return nil
        }
        set { replaceFirst(.delay, with: newValue.map { Effect.delay($0) }) }
    }

    /// A room around everything the synth plays, or nil for none.
    ///
    /// A view over ``effects``, the same way ``delay`` is.
    public var reverb: Reverb? {
        get {
            for case .reverb(let reverb) in effects { return reverb }
            return nil
        }
        set { replaceFirst(.reverb, with: newValue.map { Effect.reverb($0) }) }
    }

    /// Puts an effect where the first one of its kind is, or on the end, or
    /// takes it out. Keeping the position is what stops setting `reverb` twice
    /// from moving it down the chain.
    private func replaceFirst(_ kind: Effect.Kind, with effect: Effect?) {
        var chain = effects
        if let position = chain.firstIndex(where: { $0.kind == kind }) {
            if let effect { chain[position] = effect } else { chain.remove(at: position) }
        } else if let effect {
            chain.append(effect)
        }
        effects = chain
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
        self.startingVoice = voice
        self.polyphony = max(1, polyphony)
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
        // Straight to the output until a sketch asks for an effect. The chain
        // is built from `effects` and rebuilt when its shape changes, which the
        // engine takes without interrupting what is playing.
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
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
        // A duration is kept in seconds for an export, which may render at a
        // different rate from the one the hardware happens to be running at.
        let seconds = duration.map { max(0.001, $0) } ?? 0
        emit(SynthEvent(
            kind: .noteOn, pitch: pitch.midi, velocity: velocity,
            durationSamples: seconds > 0 ? max(1, Int(seconds * sampleRate)) : 0
        ), seconds: seconds)
    }

    /// Starts a note and holds it until `noteOff(_:)`.
    public func noteOn(_ pitch: Pitch, velocity: Double = 0.8) {
        emit(SynthEvent(kind: .noteOn, pitch: pitch.midi, velocity: velocity))
    }

    /// Lets a held note go, so it moves into its release.
    public func noteOff(_ pitch: Pitch) {
        emit(SynthEvent(kind: .noteOff, pitch: pitch.midi))
    }

    /// Lets every held note go. Their tails still sound.
    public func allNotesOff() {
        emit(SynthEvent(kind: .allNotesOff))
    }

    /// Sends an event to the speakers, or writes it down when a sketch is being
    /// exported and there are no speakers to send it to.
    ///
    /// `seconds` is the note's length where it has one, because an export may
    /// render at a different sample rate from the hardware.
    private func emit(_ event: SynthEvent, seconds: Double = 0) {
        guard !isRecordingForExport else {
            var recordedEvent = event
            recordedEvent.durationSeconds = seconds
            record(recordedEvent)
            return
        }
        // Held quiet by the take transport: a new note is dropped before it
        // can start the engine, while every other event still lands.
        if transportMuted, event.kind == .noteOn { return }
        start()
        events.push(event)
    }

    /// Plays several notes at once.
    public func play(chord pitches: [Pitch], velocity: Double = 0.8, for duration: Double? = nil) {
        for pitch in pitches { play(pitch, velocity: velocity, for: duration) }
    }

    // MARK: Engine

    /// Starts the audio engine. Called for you by the first note.
    ///
    /// Does nothing while a sketch is being exported: there is no hardware to
    /// start, and the notes are written down for the soundtrack instead.
    public func start() {
        guard !isRunning, !isRecordingForExport else { return }
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
        installAnalyzerTap(on: engine.mainMixerNode, bufferSize: tapBufferSize, analyzer: analyzer,
                           capture: captureRelay)
        tapInstalled = true
    }

    let captureRelay = CaptureTapRelay()

    /// Rebuilds the chain so the instrument can be placed in the scene.
    ///
    /// Placing a sound is a different shape of graph rather than a setting on
    /// it: one stream has to arrive at something that knows where the ears are
    /// and leave it as two. A source node's channel count is fixed when it is
    /// made, so the old one is replaced rather than reconnected, and the
    /// listener sits ahead of the effects so the room is applied to the sound
    /// after it has been placed in the room.
    func rewireForPlacement(_ environment: AVAudioEnvironmentNode) {
        let wasRunning = isRunning
        if wasRunning {
            engine.stop()
            isRunning = false
        }

        engine.disconnectNodeOutput(sourceNode)
        engine.detach(sourceNode)

        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let placed = makeSynthSourceNode(format: mono, renderer: renderer)
        // `.auto` is what picks the way a head hears on headphones and a plain
        // left and right on speakers.
        placed.renderingAlgorithm = .auto
        sourceNode = placed

        engine.attach(placed)
        engine.attach(environment)
        engine.connect(placed, to: environment, format: mono)
        listener = environment
        // From here on the engine works the formats out: the listener hands
        // back two channels whatever went in, and the effects follow that
        // rather than the format the chain started in.
        rebuildEffectChain()

        if wasRunning { start() }
    }

    /// Where the effects hang from: the listener once there is one, since the
    /// room has to be applied to the sound after it has been placed in the room,
    /// and the source itself otherwise.
    private var chainHead: AVAudioNode { listener ?? sourceNode }

    /// Brings the wiring into line with `effects`.
    ///
    /// A chain of the same kinds in the same order is the same wiring, so only
    /// the settings are applied and nothing is touched. Anything else is a
    /// rebuild.
    private func applyEffects() {
        let kinds = effects.map(\.kind)
        if kinds != wiredKinds {
            rebuildEffectChain()
        } else {
            for (unit, effect) in zip(effectUnits, effects) { effect.apply(to: unit) }
        }
    }

    /// Wires the chain from scratch.
    ///
    /// Done on the running engine rather than around a stop. Measured on this
    /// wiring, reconnecting while it runs costs nothing audible, and stopping
    /// costs the same, so there is no reason to take the sound away first.
    private func rebuildEffectChain() {
        for unit in effectUnits {
            engine.disconnectNodeOutput(unit)
            engine.detach(unit)
        }
        effectUnits = effects.map { effect in
            let unit = Effect.makeUnit(for: effect.kind)
            engine.attach(unit)
            effect.apply(to: unit)
            return unit
        }
        wiredKinds = effects.map(\.kind)

        engine.disconnectNodeOutput(chainHead)
        var previous: AVAudioNode = chainHead
        for unit in effectUnits {
            engine.connect(previous, to: unit, format: nil)
            previous = unit
        }
        engine.connect(previous, to: engine.mainMixerNode, format: nil)
    }

    /// Settings applied in one place, because an export builds its own units
    /// and they have to come out sounding the same as the ones on the output.
    nonisolated static func configure(_ unit: AVAudioUnitDelay, with delay: Delay?) {
        guard let delay else {
            unit.wetDryMix = 0
            return
        }
        unit.delayTime = max(0, delay.time)
        unit.feedback = Float(min(max(0, delay.feedback), 0.95) * 100)
        unit.lowPassCutoff = Float(delay.damping)
        unit.wetDryMix = Float(min(max(0, delay.mix), 1) * 100)
    }

    nonisolated static func configure(_ unit: AVAudioUnitReverb, with reverb: Reverb?) {
        guard let reverb else {
            unit.wetDryMix = 0
            return
        }
        unit.loadFactoryPreset(reverb.space.preset)
        unit.wetDryMix = Float(min(max(0, reverb.mix), 1) * 100)
    }
}

// MARK: - Effects

/// An echo: the sound again, later and quieter each time.
public struct Delay: Sendable, Hashable, Codable {
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
public struct Reverb: Sendable, Hashable, Codable {
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
func makeSynthSourceNode(format: AVAudioFormat, renderer: SynthRenderer) -> AVAudioSourceNode {
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

/// The live recorder's lane onto an instrument: what the synth sends to the
/// speakers is what lands in the file, effects and placement included, because
/// the tap sits on the far end of the graph.
extension Synth: CaptureAudioSource {
    package func beginAudioCapture(into sink: AudioCaptureSink) {
        captureRelay.set(sink)
        // The tap normally arrives with the first note; a recording that
        // starts earlier wants it in place already.
        installTapIfNeeded()
    }

    package func endAudioCapture() {
        captureRelay.set(nil)
    }
}
