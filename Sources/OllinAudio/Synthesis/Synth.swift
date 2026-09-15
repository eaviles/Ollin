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
    /// Where a grain cloud's reading was dragged to, whenever it moved. Empty
    /// unless the sketch scrubbed one, for the same reason the poses are.
    var recordedScrubs: [RecordedScrub] = []
    var exportClock: Double = 0
    /// The offline machine, once an export has asked for a soundtrack.
    var offline: OfflineRender?
    /// The last note number handed out; each note gets its own.
    private var noteCounter = 0
    /// What each playing note was last bent, pressed, and slid to, so a value
    /// repeated every frame is sent once.
    private var expressed: [Int: Expressed] = [:]
    private struct Expressed {
        var bend: Double?
        var pressure: Double?
        var slide: Double?
    }
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
            // A wavetable voice with no table to read plays the plain one, so
            // the first note is a sound rather than silence. The table is put
            // in place here, before the note that would read it.
            if voice.wavetable != nil, renderer.wavetable == nil {
                renderer.wavetable = .basic
            }
            // And a grain cloud with nothing to cut grains out of reads the
            // bundled sound, for the same reason: silence is not a first note.
            if voice.granular != nil, renderer.grainSource == nil {
                renderer.grainSource = GrainSource.builtIn
            }
            emit(SynthEvent(kind: .changeVoice, voice: voice))
        }
    }

    /// The table of cycles a wavetable voice reads.
    ///
    /// Set separately from ``voice`` for the same reason ``instrument`` is: a
    /// voice travels to the audio thread inside a note and has to be copyable
    /// a word at a time, where a table is hundreds of kilobytes. So the voice
    /// says where in the table to read and this says which table.
    ///
    /// ```swift
    /// synth.wavetable = .vowels
    /// synth.voice = Voice(wavetable: WavetableScan(position: 0.4))
    /// ```
    ///
    /// Set it before the notes that need it. Notes already sounding keep the
    /// table they started on. A wavetable voice played with none set reads
    /// `.basic`.
    public var wavetable: Wavetable? {
        get { renderer.wavetable }
        set { renderer.wavetable = newValue }
    }

    /// The sound a grain cloud cuts its grains out of.
    ///
    /// Set separately from ``voice`` for the same reason ``instrument`` is: a
    /// voice travels to the audio thread inside a note and has to be copyable
    /// a word at a time, where a few seconds of sound is hundreds of kilobytes.
    /// So the voice says how to cut it up and this says what.
    ///
    /// ```swift
    /// synth.grainSource = GrainSource(contentsOf: url)
    /// synth.voice = Voice(granular: GrainCloud(size: 0.08, speed: 0))
    /// ```
    ///
    /// Set it before the notes that need it. Notes already sounding keep the
    /// sound they started on. A grain cloud played with none set reads the
    /// bundled ``GrainSource/builtIn``.
    public var grainSource: GrainSource? {
        get { renderer.grainSource }
        set { renderer.grainSource = newValue }
    }

    /// How far a sounding grain cloud's reading is moved through its source,
    /// in source lengths.
    ///
    /// Where a note's own ``GrainCloud/position`` says where it starts and
    /// ``GrainCloud/speed`` says how fast it travels from there, this moves
    /// every sounding note away from wherever it has reached. With `speed` at
    /// 0, where a note stays put, that makes this simply where in the sound it
    /// is reading, so dragging it is dragging a playhead through a held note.
    ///
    /// ```swift
    /// synth.grainScrub = mouseX / width
    /// ```
    ///
    /// Read every sample rather than once a note, so it moves a note that is
    /// already sounding. Leaving it at 0 is what every note does by itself.
    public var grainScrub: Double {
        get { renderer.grainScrub }
        set {
            renderer.grainScrub = newValue
            // An export drives the sketch on a clock of its own with nothing
            // playing, so a drag made while the frames go by has to be written
            // down to be heard, exactly as a placing is.
            if OllinApp.isRenderingHeadless { recordScrub(newValue) }
        }
    }

    /// Writes down where the reading was dragged to, if it moved.
    private func recordScrub(_ value: Double) {
        if let last = recordedScrubs.last, last.value == value { return }
        // A sketch dragging every frame for an hour should not grow without
        // bound; past this it is a stuck loop rather than a drag.
        guard recordedScrubs.count < 200_000 else { return }
        let scrub = RecordedScrub(at: exportClock, value: value)
        recordedScrubs.append(scrub)
        offline?.pendingScrubs.append(scrub)
    }

    /// Overall level, `0...1`.
    public var gain: Double {
        get { renderer.gain }
        set { renderer.gain = newValue }
    }

    /// How many notes are sounding right now, tails included.
    public var activeVoiceCount: Int { renderer.activeVoiceCount }

    /// How many grains are sounding right now, across every note.
    ///
    /// What a sketch draws to show a cloud working: it rises with
    /// ``GrainCloud/density`` and with ``GrainCloud/size``, since a grain is
    /// counted for as long as it lasts, and it stops rising where a note runs
    /// out of room and starts dropping grains.
    public var grainCount: Int { renderer.grainCount }

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
    /// synth.pressure = 0.3 + 0.5 * abs(sin(time * 2))
    /// ```
    ///
    /// Every voice shares it, which is right: one bow and one breath. The
    /// sources that are set going once and then fade (a wave, a plucked string,
    /// a struck body) ignore it entirely. A note pressed on its own
    /// (``press(_:_:)``) is driven by that instead, from then on.
    public var pressure: Double {
        get { renderer.pressure }
        set { renderer.pressure = newValue }
    }

    /// A bend on every note at once, in semitones: the wheel on a keyboard,
    /// or the master channel of a polyphonic-expression surface.
    ///
    /// ```swift
    /// synth.pitchBend = 2 * wheel          // a wheel at -1...1, two semitones each way
    /// ```
    ///
    /// Adds to whatever each note is bent by on its own (``bend(_:semitones:)``).
    /// A struck body holds its pitch: its tones were decided by the strike.
    public var pitchBend: Double = 0 {
        didSet {
            guard pitchBend != oldValue else { return }
            emit(SynthEvent(kind: .bend, amount: pitchBend))
        }
    }

    /// The recordings a sampled voice plays.
    ///
    /// Set separately from ``voice`` rather than being part of it, because a
    /// voice travels to the audio thread inside a note and has to be copyable
    /// a word at a time, where recordings are megabytes on the heap. So the
    /// voice says how to play them and this says which.
    ///
    /// ```swift
    /// synth.instrument = SampledInstrument.builtIn
    /// synth.voice = Voice(sampled: Sampler())
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
        set {
            replaceFirst(where: { if case .delay = $0 { return true } else { return false } },
                         with: newValue.map { Effect.delay($0) })
        }
    }

    /// A room around everything the synth plays, or nil for none.
    ///
    /// A view over ``effects``, the same way ``delay`` is. The first room in
    /// the chain, whether one of the built-in ones or a room of your own.
    public var reverb: Reverb? {
        get {
            for case .reverb(let reverb) in effects { return reverb }
            return nil
        }
        set {
            replaceFirst(where: { if case .reverb = $0 { return true } else { return false } },
                         with: newValue.map { Effect.reverb($0) })
        }
    }

    /// Puts an effect where the first one like it is, or on the end, or
    /// takes it out. Keeping the position is what stops setting `reverb` twice
    /// from moving it down the chain. Matched by the case rather than the
    /// kind, because a reverb with a room of its own is a kind of its own for
    /// the wiring and still the reverb to a sketch.
    private func replaceFirst(where matches: (Effect) -> Bool, with effect: Effect?) {
        var chain = effects
        if let position = chain.firstIndex(where: matches) {
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
        // A synth made with a wavetable voice reads the plain table until a
        // sketch sets another, the same rule the `voice` setter keeps.
        if voice.wavetable != nil { renderer.wavetable = .basic }
        if voice.granular != nil { renderer.grainSource = GrainSource.builtIn }

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
    ///   - delay: seconds to wait before it starts. Zero starts it on the
    ///     next block of audio, with the frame that asked. A wait lands the
    ///     note on its own sample instead, so notes asked for together can
    ///     be closer than a frame apart: a sequencer's swing and its
    ///     ratchets, a strum.
    /// - Returns: the note, for bending, pressing, or sliding it while it
    ///   sounds. Ignore it to play the note and forget it.
    @discardableResult
    public func play(
        _ pitch: Pitch, velocity: Double = 0.8, for duration: Double? = nil, after delay: Double = 0
    ) -> PlayingNote {
        // A duration is kept in seconds for an export, which may render at a
        // different rate from the one the hardware happens to be running at.
        let seconds = duration.map { max(0.001, $0) } ?? 0
        let wait = max(0, delay)
        let note = nextNote(pitch)
        emit(SynthEvent(
            kind: .noteOn, pitch: pitch.midi, velocity: velocity, noteID: note.id,
            durationSamples: seconds > 0 ? max(1, Int(seconds * sampleRate)) : 0,
            delaySamples: Int((wait * sampleRate).rounded()), delaySeconds: wait
        ), seconds: seconds)
        return note
    }

    /// Starts a note and holds it until `noteOff(_:)`.
    ///
    /// - Returns: the note, for letting it go by that value (`noteOff(_:)`
    ///   takes it as well as a pitch), and for bending, pressing, or sliding
    ///   it while it sounds. Ignore it to let the note go by its pitch.
    @discardableResult
    public func noteOn(_ pitch: Pitch, velocity: Double = 0.8) -> PlayingNote {
        let note = nextNote(pitch)
        emit(SynthEvent(kind: .noteOn, pitch: pitch.midi, velocity: velocity, noteID: note.id))
        return note
    }

    /// Lets a held note go, so it moves into its release.
    ///
    /// The nearest held note to `pitch` is the one let go, within half a
    /// semitone, so a note bent further than that is let go by the value
    /// ``noteOn(_:velocity:)`` handed back instead.
    public func noteOff(_ pitch: Pitch) {
        emit(SynthEvent(kind: .noteOff, pitch: pitch.midi))
    }

    /// Lets one note go, whatever it has been bent to.
    public func noteOff(_ note: PlayingNote) {
        expressed[note.id] = nil
        emit(SynthEvent(kind: .noteOff, pitch: note.pitch.midi, noteID: note.id))
    }

    // MARK: Expression

    /// Bends one note by `semitones`, on top of the instrument's ``pitchBend``.
    ///
    /// ```swift
    /// let note = synth.noteOn("C4")
    /// // in draw(), while it is held:
    /// synth.bend(note, semitones: 2 * sin(time * 3))
    /// ```
    ///
    /// The bend glides over a few milliseconds, so calling this every frame
    /// with a moving value moves the note smoothly. Every source follows but
    /// the struck body, whose tones were decided by the strike.
    public func bend(_ note: PlayingNote, semitones: Double) {
        express(note, kind: .bend, amount: semitones)
    }

    /// Presses one note, `0...1`.
    ///
    /// On the bowed string and the blown tube this is the note's own drive,
    /// replacing the instrument's ``pressure`` for that note from the first
    /// press on. On every other voice it raises the note's level above the
    /// one it was struck at, by the voice's `pressureAmount`.
    public func press(_ note: PlayingNote, _ pressure: Double) {
        express(note, kind: .press, amount: min(max(0, pressure), 1))
    }

    /// Slides one note, `0...1`, half way at rest: where a finger sits along
    /// the key on a polyphonic-expression surface. A voice with a filter opens
    /// it above the middle and closes it below, by the filter's `slideAmount`.
    public func slide(_ note: PlayingNote, _ position: Double) {
        express(note, kind: .slide, amount: min(max(0, position), 1))
    }

    /// Hands out the next note number, which is what ties a bend to a voice.
    private func nextNote(_ pitch: Pitch) -> PlayingNote {
        noteCounter += 1
        return PlayingNote(pitch: pitch, id: noteCounter)
    }

    /// Sends an expression only when it moved, so a sketch that repeats the
    /// same value every frame costs the render thread nothing.
    private func express(_ note: PlayingNote, kind: SynthEvent.Kind, amount: Double) {
        if expressed.count > 1024 { expressed.removeAll(keepingCapacity: true) }
        var sent = expressed[note.id] ?? Expressed()
        switch kind {
        case .bend:
            guard sent.bend != amount else { return }
            sent.bend = amount
        case .press:
            guard sent.pressure != amount else { return }
            sent.pressure = amount
        case .slide:
            guard sent.slide != amount else { return }
            sent.slide = amount
        default:
            return
        }
        expressed[note.id] = sent
        emit(SynthEvent(kind: kind, pitch: note.pitch.midi, noteID: note.id, amount: amount))
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

    /// Plays several notes at once, or after a wait, the way one note is.
    public func play(
        chord pitches: [Pitch], velocity: Double = 0.8, for duration: Double? = nil, after delay: Double = 0
    ) {
        for pitch in pitches { play(pitch, velocity: velocity, for: duration, after: delay) }
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

    /// The rate the chain was last wired at, which a room is prepared for.
    /// Zero until the first rebuild, when the instrument's own rate stands in.
    private var chainSampleRate: Double = 0

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
            let rate = chainSampleRate > 0 ? chainSampleRate : sampleRate
            for (unit, effect) in zip(effectUnits, effects) { effect.apply(to: unit, sampleRate: rate) }
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
        // A connection touching a custom unit names the chain's format
        // outright: left to work the format out, the engine keeps such a
        // unit's declared format and quietly resamples around it instead,
        // which is a converter in the middle of the sound. Connections between
        // built-in kinds stay worked out by the engine.
        let chainFormat = chainHead.outputFormat(forBus: 0)
        chainSampleRate = chainFormat.sampleRate > 0 ? chainFormat.sampleRate : sampleRate
        effectUnits = effects.map { effect in
            let unit = Effect.makeUnit(for: effect.kind)
            engine.attach(unit)
            effect.apply(to: unit, sampleRate: chainSampleRate)
            return unit
        }
        wiredKinds = effects.map(\.kind)

        engine.disconnectNodeOutput(chainHead)
        func isCustom(_ node: AVAudioNode) -> Bool {
            (node as? AVAudioUnit)?.auAudioUnit is ClosureAudioUnit
        }
        var previous: AVAudioNode = chainHead
        for unit in effectUnits {
            let named = (isCustom(unit) || isCustom(previous)) && chainFormat.sampleRate > 0
            engine.connect(previous, to: unit, format: named ? chainFormat : nil)
            previous = unit
        }
        engine.connect(previous, to: engine.mainMixerNode,
                       format: isCustom(previous) && chainFormat.sampleRate > 0 ? chainFormat : nil)
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
///
/// Four rooms are built in, and any room at all can be brought: a recording
/// of one, or one drawn from a rule, as an ``ImpulseResponse``.
///
/// ```swift
/// synth.reverb = Reverb(.hall, mix: 0.3)
/// synth.reverb = Reverb(.decay(seconds: 4, damping: 0.7), mix: 0.4)
/// synth.reverb = Reverb(ImpulseResponse.load("stairwell.wav")!, mix: 0.5, preDelay: 0.02)
/// ```
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

    /// Which of the built-in rooms. Not read while ``impulse`` is set.
    public var space: Space
    /// How much of the result is the room rather than the sound itself, `0...1`.
    public var mix: Double
    /// A room of your own, recorded or drawn. While one is set, the reverb
    /// is that room and ``space`` is not read.
    public var impulse: ImpulseResponse?
    /// Seconds before a room of your own answers, `0...1`. A little of it
    /// keeps the sound itself clear of the room; the built-in rooms carry
    /// their own and ignore this.
    public var preDelay: Double

    public init(_ space: Space = .hall, mix: Double = 0.3) {
        self.space = space
        self.mix = mix
        self.impulse = nil
        self.preDelay = 0
    }

    /// A room of your own: the sound convolved with `impulse`.
    ///
    /// The room is brought to unit energy on the way in, so `mix` means the
    /// same for a quiet recording and a loud one. Changing `mix` on a
    /// sounding room leaves its tail alone; changing the room or the
    /// pre-delay starts a fresh one.
    public init(_ impulse: ImpulseResponse, mix: Double = 0.3, preDelay: Double = 0) {
        self.space = .hall
        self.mix = mix
        self.impulse = impulse
        self.preDelay = min(max(0, preDelay), 1)
    }

    private enum CodingKeys: String, CodingKey {
        case space, mix, impulse, preDelay
    }

    /// Read back with the two fields a room of your own adds allowed to be
    /// missing, so a reverb written down before they existed still reads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        space = try container.decode(Space.self, forKey: .space)
        mix = try container.decode(Double.self, forKey: .mix)
        impulse = try container.decodeIfPresent(ImpulseResponse.self, forKey: .impulse)
        preDelay = try container.decodeIfPresent(Double.self, forKey: .preDelay) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(space, forKey: .space)
        try container.encode(mix, forKey: .mix)
        try container.encodeIfPresent(impulse, forKey: .impulse)
        if preDelay != 0 { try container.encode(preDelay, forKey: .preDelay) }
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

        // Two channels are rendered as two, because a grain cloud can throw
        // its grains to the sides and that is the only thing here that has a
        // side to be on. Everything else is one stream, which the renderer
        // writes to both.
        if buffers.count > 1, let second = buffers[1].mData {
            let right = UnsafeMutableBufferPointer(
                start: second.assumingMemoryBound(to: Float.self), count: frames
            )
            renderer.render(into: output, right: right, frameCount: frames)
            // Any further channels get the left one, as they always did.
            for buffer in buffers.dropFirst(2) {
                guard let other = buffer.mData else { continue }
                other.assumingMemoryBound(to: Float.self)
                    .update(from: output.baseAddress!, count: frames)
            }
        } else {
            renderer.render(into: output, frameCount: frames)
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

/// A note a `Synth` is playing, handed back when it starts.
///
/// Holding it is what lets a sketch bend, press, slide, and let go of one
/// note among several, whatever pitch the note has been bent to since.
///
/// ```swift
/// let note = synth.noteOn("C4")
/// synth.bend(note, semitones: 1.5)
/// synth.noteOff(note)
/// ```
public struct PlayingNote: Sendable, Hashable {
    /// The pitch the note started on.
    public let pitch: Pitch
    /// Which note this is, among every note the instrument has played.
    let id: Int
}
