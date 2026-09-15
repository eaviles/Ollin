import Foundation
import Synchronization

/// The part of a synthesizer that actually makes samples.
///
/// Deliberately knows nothing about the audio engine: it takes events in and
/// fills a buffer, so the same code that feeds the speakers can be run offline
/// at any rate, which is what makes the sound testable and what a deterministic
/// render later leans on. Given the same events at the same rate it produces the
/// same samples, so nothing here reads a clock or the sketch's randomness.
final class SynthRenderer: @unchecked Sendable {

    /// One voice's running state: everything a single note needs to sound.
    private struct RenderVoice {
        var oscillator: Oscillator
        var second: Oscillator
        var string: StringVoice
        var secondString: StringVoice
        var body = ModalVoice()
        var secondBody = ModalVoice()
        var bow: BowVoice
        var secondBow: BowVoice
        var tube: TubeVoice
        var secondTube: TubeVoice
        var patch: PatchVoice
        var secondPatch: PatchVoice
        var sampler = SamplerVoice()
        var table = WavetableVoice()
        var secondTable = WavetableVoice()
        var grain: GrainVoice
        var amplitude = EnvelopeRunner()
        var filterEnvelope = EnvelopeRunner()
        /// The envelope a wavetable scan moves its position by.
        var scanEnvelope = EnvelopeRunner()
        var filter = StateVariableFilter()
        /// The right channel's own filter, used only by a cloud that throws
        /// its grains to the sides: one filter cannot carry two channels, and
        /// every other voice is one stream.
        var rightFilter = StateVariableFilter()
        /// The right channel of the sample just produced, when this voice
        /// pans. Equal to the left one otherwise.
        var right = 0.0

        var spec = Voice()
        var pitch: Double = 60
        var velocity: Double = 0
        /// The number the sketch holds for this note, so a bend, a press, or
        /// a slide finds the voice that owns it.
        var noteID = 0
        /// The pitch sounding this block: `pitch` with the bends folded in.
        var sounding: Double = 60
        /// Where the note is bent to, in semitones: where the sketch put it,
        /// and where the glide has reached.
        var bendTarget = 0.0
        var bend = 0.0
        /// The offset the model was last cut to, so a retune happens on a
        /// move and not every block.
        var tunedTo = 0.0
        /// How hard the note is being pressed, `0...1`, and whether it has
        /// been pressed at all: until then a driven voice takes the
        /// instrument's own drive.
        var pressureTarget = 0.0
        var pressure = 0.0
        var hasOwnPressure = false
        /// Where the finger sits along the key, `0...1`, half way at rest.
        var slideTarget = 0.5
        var slide = 0.5
        /// Samples left before the note releases itself, or nil if it is held.
        var remaining: Int?
        /// Whether the note is still held, so a `noteOff` can find it.
        var isHeld = false
        /// When the note started, for deciding which voice to take.
        var startedAt: Int = 0

        var isSounding: Bool { !amplitude.isFinished }
    }

    private var voices: [RenderVoice]
    /// Events asked for with a wait on them, each holding the clock reading
    /// it is due at. Fixed memory, taken once, because the render thread may
    /// not allocate; past its size an event lands at once rather than late.
    private let pending: UnsafeMutablePointer<SynthEvent>
    private var pendingCount = 0
    private static let pendingCapacity = 256
    private let sampleRate: Double
    private let events: EventRing
    /// Every string voice's delay line, taken in one piece before the first
    /// note. Raw memory rather than arrays because the render thread writes it.
    private let stringMemory: UnsafeMutablePointer<Double>
    private let stringCapacity: Int
    /// Every driven voice's delay lines, taken in one piece for the same reason.
    private let drivenMemory: UnsafeMutablePointer<Double>
    /// Every grain cloud's sounding grains, taken in one piece for the same
    /// reason: the render thread starts and retires them.
    private let grainMemory: UnsafeMutablePointer<GrainSlot>
    /// Samples rendered so far, used only to order voices by age.
    private var clock = 0
    /// The recordings a sampled voice plays, if a sketch has set any.
    ///
    /// Held here rather than inside a `Voice` because it is a reference to
    /// something large, and a voice has to be copyable a word at a time to
    /// reach the audio thread. Set before the note that needs it and only read
    /// afterwards, so the render thread never sees it change under a note.
    var instrument: SampledInstrument?

    /// The table of cycles a wavetable voice reads, if a sketch has set one.
    /// Held here for the same reason `instrument` is: it is a reference to
    /// something large, set before the note that needs it and only read after.
    var wavetable: Wavetable?

    /// The sound a grain cloud cuts its grains out of, if a sketch has set
    /// one. Held here for the same reason the two above are.
    var grainSource: GrainSource?

    /// The voice every new note is built from. Changed between notes.
    private var currentVoice: Voice

    /// A bend on every note at once, in semitones: the wheel on a keyboard,
    /// or the master channel of a polyphonic-expression surface. Arrives as
    /// an event rather than an atomic so an export replays it where it fell.
    private var bendAll = 0.0

    /// Master level, `0...1`.
    ///
    /// Set from the sketch and read on the render thread, so it travels as a
    /// single atomic word rather than a plain property: a torn read here would
    /// be an audible jump. The bit pattern is what makes a `Double` atomic.
    var gain: Double {
        get { Double(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(min(max(0, newValue), 1).bitPattern, ordering: .relaxed) }
    }
    private let gainBits = Atomic<UInt64>((0.7 as Double).bitPattern)

    /// How hard a driven voice is being bowed or blown, `0...1`.
    ///
    /// A bow and a breath keep happening, so this is read every sample rather
    /// than at the start of a note, which is what gives a driven note a middle
    /// that can change. It travels as one atomic word for the same reason
    /// `gain` does: a torn read on the render thread would be audible.
    /// Ignored entirely by the sources that are set going once.
    var pressure: Double {
        get { Double(bitPattern: pressureBits.load(ordering: .relaxed)) }
        set { pressureBits.store(min(max(0, newValue), 1).bitPattern, ordering: .relaxed) }
    }
    private let pressureBits = Atomic<UInt64>((1.0 as Double).bitPattern)

    /// How far a sounding grain cloud's reading is moved through its source,
    /// in source lengths.
    ///
    /// Read every sample for the reason `pressure` is: a cloud dragged by hand
    /// is a control that has to move while the note sounds, and a block is a
    /// few milliseconds. One atomic word, so a torn read cannot jump it.
    var grainScrub: Double {
        get { Double(bitPattern: scrubBits.load(ordering: .relaxed)) }
        set { scrubBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
    private let scrubBits = Atomic<UInt64>((0.0 as Double).bitPattern)

    /// How many voices are sounding, published for the sketch to read.
    ///
    /// Written once per block by the render thread rather than read off the
    /// voice array, which only that thread may touch.
    var activeVoiceCount: Int { activeCount.load(ordering: .relaxed) }
    private let activeCount = Atomic<Int>(0)

    /// How many grains are sounding across every voice, published the same way
    /// and for the same reason.
    var grainCount: Int { grains.load(ordering: .relaxed) }
    private let grains = Atomic<Int>(0)

    init(voice: Voice, polyphony: Int, sampleRate: Double, events: EventRing, seed: UInt64 = 0x5EED) {
        self.currentVoice = voice
        self.sampleRate = sampleRate
        self.events = events

        // A string is a delay line as long as one period, so the longest one is
        // set by the lowest note this can play. Every string's memory is taken
        // once, here, because the render thread may not allocate.
        let count = max(1, polyphony)
        let capacity = max(64, Int(sampleRate / SynthRenderer.lowestStringFrequency) + 2)
        let perString = StringVoice.memoryNeeded(capacity: capacity)
        self.stringCapacity = capacity
        self.stringMemory = .allocate(capacity: perString * count * 2)
        self.stringMemory.initialize(repeating: 0, count: perString * count * 2)

        // The driven models are delay lines too, and the render thread may not
        // allocate, so theirs is taken here as well. A voice is only ever one
        // kind at a time, but keeping the blocks apart means no two of them can
        // ever be looking at the same samples.
        let perBow = BowVoice.memoryNeeded(capacity: capacity)
        let perTube = TubeVoice.memoryNeeded(capacity: capacity)
        let perDriven = perBow + perTube
        self.drivenMemory = .allocate(capacity: perDriven * count * 2)
        self.drivenMemory.initialize(repeating: 0, count: perDriven * count * 2)

        // A cloud's sounding grains, one block per voice, for the same reason:
        // the render thread starts and retires them and may not allocate.
        let perCloud = GrainVoice.memoryNeeded()
        self.grainMemory = .allocate(capacity: perCloud * count)
        self.grainMemory.initialize(repeating: GrainSlot(), count: perCloud * count)
        // The grain envelopes are a table built on first use, so it is built
        // here rather than by whichever note reaches it first.
        GrainVoice.warm()

        self.pending = .allocate(capacity: SynthRenderer.pendingCapacity)
        self.pending.initialize(repeating: SynthEvent(), count: SynthRenderer.pendingCapacity)

        let memory = stringMemory
        let driven = drivenMemory
        let clouds = grainMemory
        // Each voice gets its own noise stream so a render replays exactly.
        // The closure says what it takes and returns, and the index appears once
        // as a number rather than ten times as a conversion, because working all
        // of that out from a single expression this size is more than an older
        // compiler will finish.
        self.voices = (0..<count).map { (index: Int) -> RenderVoice in
            let step = UInt64(index)
            let first = 2 * index
            let second = 2 * index + 1
            return RenderVoice(
                oscillator: Oscillator(seed: seed &+ step &* 0x9E37_79B9),
                second: Oscillator(seed: seed &+ step &* 0x85EB_CA6B &+ 1),
                string: StringVoice(
                    buffer: memory + perString * first, capacity: capacity,
                    seed: seed &+ step &* 0xC2B2_AE35
                ),
                secondString: StringVoice(
                    buffer: memory + perString * second, capacity: capacity,
                    seed: seed &+ step &* 0x27D4_EB2F &+ 1
                ),
                bow: BowVoice(buffer: driven + perDriven * first, capacity: capacity),
                secondBow: BowVoice(
                    buffer: driven + perDriven * second, capacity: capacity
                ),
                tube: TubeVoice(
                    buffer: driven + perDriven * first + perBow, capacity: capacity,
                    seed: seed &+ step &* 0x165667B1
                ),
                secondTube: TubeVoice(
                    buffer: driven + perDriven * second + perBow, capacity: capacity,
                    seed: seed &+ step &* 0xD3A2646C &+ 1
                ),
                patch: PatchVoice(seed: seed &+ step &* 0x2545F491),
                secondPatch: PatchVoice(seed: seed &+ step &* 0x94D049BB &+ 1),
                grain: GrainVoice(buffer: clouds + perCloud * index,
                                  seed: seed &+ step &* 0x6C8E_9CF5 &+ 1)
            )
        }
    }

    deinit {
        stringMemory.deallocate()
        drivenMemory.deallocate()
        grainMemory.deallocate()
        pending.deinitialize(count: SynthRenderer.pendingCapacity)
        pending.deallocate()
    }

    /// The lowest note a string voice can be tuned to, which is what sizes the
    /// delay lines. Below it the note is played sharp rather than the buffer
    /// being outrun.
    static let lowestStringFrequency = 16.0

    /// Fills `output` with the next `frameCount` samples, applying anything the
    /// sketch has asked for since the last block.
    func render(into output: UnsafeMutableBufferPointer<Float>, frameCount: Int) {
        renderFrames(left: output, right: nil, frameCount: frameCount)
    }

    /// The same, in two channels.
    ///
    /// Every voice here is one stream, so the two are the same samples unless
    /// a grain cloud is throwing its grains to the sides. A block with nothing
    /// panning takes the one-channel path and writes it to both, so the sound
    /// is what it always was to the bit.
    func render(into left: UnsafeMutableBufferPointer<Float>,
                right: UnsafeMutableBufferPointer<Float>, frameCount: Int) {
        renderFrames(left: left, right: right, frameCount: frameCount)
    }

    private func renderFrames(left: UnsafeMutableBufferPointer<Float>,
                              right: UnsafeMutableBufferPointer<Float>?,
                              frameCount: Int) {
        drainEvents()
        let level = gain
        // Read once for the block rather than once a sample: it is a control,
        // not a signal, and a block is a few milliseconds.
        let driving = pressure
        let scrub = grainScrub

        // A note's own expression glides toward where the sketch put it, one
        // step a block: a controller speaks every few milliseconds and a
        // jump between two of its values would be heard as a step.
        let step = 1 - exp(-Double(frameCount) / (0.008 * sampleRate))
        for index in voices.indices where voices[index].isSounding {
            settle(&voices[index], step: step)
        }

        // Whether anything in this block has a side to be on. Asked once a
        // block rather than once a sample, and false for every sketch that
        // never spreads a cloud, which is the path that must not change.
        var panning = right != nil
            && voices.contains { $0.isSounding && $0.grain.isPanning }

        for frame in 0..<frameCount {
            // An event with a wait on it starts on its own sample, in the
            // middle of the block if that is where it falls. One comparison a
            // sample while nothing is waiting, which is nearly always.
            if pendingCount > 0 {
                startDue()
                // A note that starts here may be the first thing in the block
                // with a side to be on, and it would play the left channel in
                // both until the next one otherwise. Asked only where a note
                // actually started, which is rare.
                if right != nil, !panning {
                    panning = voices.contains { $0.isSounding && $0.grain.isPanning }
                }
            }
            var mix = 0.0
            var mixRight = 0.0
            for index in voices.indices where voices[index].isSounding {
                mix += nextSample(&voices[index], pressure: driving, scrub: scrub)
                if panning { mixRight += voices[index].right }
            }
            let value = Float(softClip(mix * level))
            left[frame] = value
            if let right { right[frame] = panning ? Float(softClip(mixRight * level)) : value }
            clock += 1
        }

        activeCount.store(voices.count { $0.isSounding }, ordering: .relaxed)
        grains.store(voices.reduce(0) { $0 + $1.grain.soundingCount }, ordering: .relaxed)
    }

    /// One sample from one voice. The right channel of it, which differs only
    /// for a cloud that pans, is left on the voice rather than returned, so
    /// every other voice's path is what it was.
    private func nextSample(_ voice: inout RenderVoice, pressure: Double,
                            scrub: Double) -> Double {
        // A note given a length releases itself when it runs out.
        if let remaining = voice.remaining {
            if remaining <= 0 {
                voice.amplitude.noteOff()
                voice.filterEnvelope.noteOff()
                voice.scanEnvelope.noteOff()
                voice.isHeld = false
                voice.remaining = nil
            } else {
                voice.remaining = remaining - 1
            }
        }

        let amplitude = voice.amplitude.next()

        // A driven voice pressed on its own is driven by that; until a note
        // is pressed, the instrument's one bow and one breath drive it.
        let pressure = voice.hasOwnPressure ? voice.pressure : pressure

        var sample: Double
        switch voice.spec.source {
        case .wave(let waveform):
            let increment = frequency(of: voice.sounding) / sampleRate
            sample = voice.oscillator.next(waveform, increment: increment)
            if voice.spec.detune != 0 {
                let detuned = frequency(of: voice.sounding + voice.spec.detune) / sampleRate
                sample = 0.5 * (sample + voice.second.next(waveform, increment: detuned))
            }
        case .plucked:
            // The string was set going when the note started; here it only
            // carries on losing what it loses.
            sample = voice.string.next()
            if voice.spec.detune != 0 {
                sample = 0.5 * (sample + voice.secondString.next())
            }
        case .struck:
            sample = voice.body.next()
            if voice.spec.detune != 0 {
                sample = 0.5 * (sample + voice.secondBody.next())
            }
        case .bowed(let spec):
            // The bow is still moving, so the note is still being made. This is
            // the whole difference from the sources above, which were set going
            // once and are only fading now.
            // Bow speed against the speed the rosin lets go at is what decides
            // whether the string moves the way a bowed string moves. Below that
            // ratio the string is caught and released once a cycle and the tone
            // is the falling spectrum of a real bow; above it the string tears
            // loose twice a cycle and jumps to the octave, which is exactly what
            // over-bowing sounds like. Force widens the sticking band, so a
            // light bow can be over-driven and a heavy one stays solid, which is
            // the same bargain a player makes.
            let speed = pressure * (0.06 + 0.22 * min(max(0, spec.force), 1))
            sample = voice.bow.next(bowVelocity: speed)
            if voice.spec.detune != 0 {
                sample = 0.5 * (sample + voice.secondBow.next(bowVelocity: speed))
            }
        case .sampled:
            // The read head was placed when the note started; here it only
            // moves along the recording.
            sample = voice.sampler.next()
        case .patch:
            // The patch was set up when the note started; here it is only run
            // forward a sample, exactly as an oscillator is.
            sample = voice.patch.next()
            if voice.spec.detune != 0 {
                sample = 0.5 * (sample + voice.secondPatch.next())
            }
        case .blown(let spec):
            let breath = pressure * 1.1
            sample = voice.tube.next(breath: breath, breathiness: spec.breathiness)
            if voice.spec.detune != 0 {
                sample = 0.5 * (sample
                                + voice.secondTube.next(breath: breath,
                                                        breathiness: spec.breathiness))
            }
        case .wavetable:
            // The table was chosen when the note started; here the note only
            // moves through its cycle, and the scan's envelope moves where in
            // the table that cycle is read from.
            let travel = voice.scanEnvelope.next()
            sample = voice.table.next(travel: travel)
            if voice.spec.detune != 0 {
                sample = 0.5 * (sample + voice.secondTable.next(travel: travel))
            }
        case .granular:
            // The sound was chosen when the note started; here the cloud only
            // moves its position along and starts whatever grains are due.
            // The detune is inside it, as every other grain, so there is no
            // second copy of a cloud to run.
            sample = voice.grain.next(scrub: scrub)
        }

        if let spec = voice.spec.filter {
            let envelope = voice.filterEnvelope.next()
            // The envelope moves the cutoff in octaves, and key tracking moves
            // it with the note, so both are multiples of where it started.
            var cutoff = spec.cutoff
            if spec.envelopeAmount != 0 { cutoff *= pow(2, spec.envelopeAmount * envelope) }
            if spec.keyTracking != 0 { cutoff *= pow(2, spec.keyTracking * (voice.sounding - 60) / 12) }
            // A slide opens the filter above the middle of the key and closes
            // it below, by the octaves the voice allows.
            if spec.slideAmount != 0, voice.slide != 0.5 {
                cutoff *= pow(2, spec.slideAmount * (voice.slide - 0.5) * 2)
            }
            voice.filter.setCoefficients(cutoff: cutoff, resonance: spec.resonance, sampleRate: sampleRate)
            if voice.grain.isPanning {
                // Two channels need two filters: one filter carries one
                // stream's memory, and running the right channel through the
                // left's would smear them together.
                voice.rightFilter.setCoefficients(cutoff: cutoff, resonance: spec.resonance,
                                                  sampleRate: sampleRate)
                voice.right = voice.rightFilter.next(voice.grain.right, mode: spec.mode)
            }
            sample = voice.filter.next(sample, mode: spec.mode)
        } else if voice.grain.isPanning {
            voice.right = voice.grain.right
        }

        // A sampled voice has already taken the note's velocity into account,
        // because how much of it is heard is one of its own settings: an
        // instrument whose recordings are already its dynamics should not be
        // scaled by velocity a second time. Every other source is scaled here
        // as it always was, and a note pressed on its own rises from its
        // struck level toward full by the voice's pressure amount (a driven
        // voice takes pressure as its drive instead, above).
        var struck = voice.velocity
        if case .sampled = voice.spec.source {
            struck = 1
        } else if voice.hasOwnPressure, !voice.spec.source.isDriven, voice.spec.pressureAmount > 0 {
            struck += (1 - struck) * voice.spec.pressureAmount * voice.pressure
        }
        // Spelled out the same way on both channels rather than through a
        // shared factor: the two orders of multiplication do not give the same
        // bits, and every voice but a panned cloud must land on the left
        // channel exactly as a one-channel render leaves it.
        let out = sample * amplitude * struck * voice.spec.gain
        voice.right = voice.grain.isPanning
            ? voice.right * amplitude * struck * voice.spec.gain
            : out
        return out
    }

    // MARK: Expression

    /// Moves a voice's bend, pressure, and slide one step toward where the
    /// sketch put them, and cuts a model to the pitch it now sounds.
    private func settle(_ voice: inout RenderVoice, step: Double) {
        voice.bend = approach(voice.bend, voice.bendTarget, by: step)
        voice.pressure = approach(voice.pressure, voice.pressureTarget, by: step)
        voice.slide = approach(voice.slide, voice.slideTarget, by: step)
        let offset = voice.bend + bendAll
        voice.sounding = voice.pitch + offset
        guard abs(offset - voice.tunedTo) > 1e-5 else { return }
        voice.tunedTo = offset
        retune(&voice)
    }

    private func approach(_ value: Double, _ target: Double, by step: Double) -> Double {
        let next = value + (target - value) * step
        return abs(next - target) < 1e-6 ? target : next
    }

    /// Moves a model that was cut to length when the note started onto the
    /// pitch the voice sounds now. An oscillator reads `sounding` every sample
    /// and needs nothing here; a struck body's tones were decided by the
    /// strike and hold, the way a bell rung cannot be retuned.
    private func retune(_ voice: inout RenderVoice) {
        let played = voice.sounding
        let detune = voice.spec.detune
        let floor = SynthRenderer.lowestStringFrequency
        switch voice.spec.source {
        case .wave, .struck:
            break
        case .plucked:
            voice.string.retune(frequency: max(floor, frequency(of: played)), sampleRate: sampleRate)
            if detune != 0 {
                voice.secondString.retune(frequency: max(floor, frequency(of: played + detune)),
                                          sampleRate: sampleRate)
            }
        case .bowed:
            voice.bow.retune(frequency: max(floor, frequency(of: played)), sampleRate: sampleRate)
            if detune != 0 {
                voice.secondBow.retune(frequency: max(floor, frequency(of: played + detune)),
                                       sampleRate: sampleRate)
            }
        case .blown:
            voice.tube.retune(frequency: max(floor, frequency(of: played)), sampleRate: sampleRate)
            if detune != 0 {
                voice.secondTube.retune(frequency: max(floor, frequency(of: played + detune)),
                                        sampleRate: sampleRate)
            }
        case .sampled:
            voice.sampler.retune(semitones: voice.tunedTo)
        case .patch:
            voice.patch.retune(frequency: frequency(of: played), sampleRate: sampleRate)
            if detune != 0 {
                voice.secondPatch.retune(frequency: frequency(of: played + detune), sampleRate: sampleRate)
            }
        case .wavetable:
            voice.table.retune(frequency: frequency(of: played), sampleRate: sampleRate)
            if detune != 0 {
                voice.secondTable.retune(frequency: frequency(of: played + detune), sampleRate: sampleRate)
            }
        case .granular:
            // Grains started from here on are read at the new pitch. The ones
            // already sounding keep theirs, the way a note already sounding
            // keeps the recording it started on.
            voice.grain.retune(semitones: played - Double(grainSource?.rootKey ?? 60))
        }
    }

    /// Applies a bend, a press, or a slide to the voice that owns the note.
    ///
    /// A note that started in this same drain takes the value outright
    /// rather than gliding from nothing: a controller says where a finger is
    /// before it says the finger is down, and both arrive together.
    private func express(_ event: SynthEvent) {
        guard event.noteID != 0,
              let index = voices.firstIndex(where: { $0.noteID == event.noteID && $0.isSounding })
        else { return }
        let fresh = voices[index].startedAt == clock
        switch event.kind {
        case .bend:
            voices[index].bendTarget = event.amount
            if fresh { voices[index].bend = event.amount }
        case .press:
            let pressed = min(max(0, event.amount), 1)
            voices[index].pressureTarget = pressed
            voices[index].hasOwnPressure = true
            if fresh { voices[index].pressure = pressed }
        case .slide:
            let slid = min(max(0, event.amount), 1)
            voices[index].slideTarget = slid
            if fresh { voices[index].slide = slid }
        default:
            break
        }
    }

    private func frequency(of midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    // MARK: Events

    private func drainEvents() {
        while let event = events.pop() {
            if event.delaySamples > 0 { hold(event) } else { apply(event) }
        }
    }

    private func apply(_ event: SynthEvent) {
        switch event.kind {
        case .noteOn:      start(event)
        case .noteOff:
            if event.noteID != 0 { release(id: event.noteID) } else { release(pitch: event.pitch) }
        case .allNotesOff:
            for index in voices.indices { releaseVoice(&voices[index]) }
            // A note still waiting to start is more held than a tail is, so
            // letting everything go drops it too.
            pendingCount = 0
        case .changeVoice: currentVoice = event.voice
        case .bend, .press, .slide:
            // A bend with no note is the whole instrument's.
            if event.kind == .bend, event.noteID == 0 { bendAll = event.amount } else { express(event) }
        }
    }

    /// Puts an event aside until its sample comes round, the wait rewritten
    /// as the clock reading it is due at.
    private func hold(_ event: SynthEvent) {
        guard pendingCount < SynthRenderer.pendingCapacity else {
            apply(event)
            return
        }
        var due = event
        due.delaySamples = clock + event.delaySamples
        pending[pendingCount] = due
        pendingCount += 1
    }

    /// Applies every waiting event whose sample has arrived, keeping the rest
    /// in the order they came.
    private func startDue() {
        var kept = 0
        for index in 0..<pendingCount {
            let event = pending[index]
            if event.delaySamples <= clock {
                if event.kind == .noteOn {
                    // The block's settle has already run, so the voice that
                    // starts here folds the instrument's bend in itself.
                    let voice = start(event)
                    settle(&voices[voice], step: 1)
                } else {
                    apply(event)
                }
            } else {
                pending[kept] = event
                kept += 1
            }
        }
        pendingCount = kept
    }

    @discardableResult
    private func start(_ event: SynthEvent) -> Int {
        let index = claimVoice()
        var voice = voices[index]

        voice.spec = currentVoice
        voice.pitch = event.pitch
        voice.velocity = min(max(0, event.velocity), 1)
        voice.remaining = event.durationSamples > 0 ? event.durationSamples : nil
        voice.isHeld = event.durationSamples == 0
        voice.startedAt = clock
        voice.noteID = event.noteID
        // Cut to the plain pitch here; the settle before the first sample
        // folds the instrument's bend in and retunes if there is one.
        voice.sounding = event.pitch
        voice.bend = 0
        voice.bendTarget = 0
        voice.tunedTo = 0
        voice.pressure = 0
        voice.pressureTarget = 0
        voice.hasOwnPressure = false
        voice.slide = 0.5
        voice.slideTarget = 0.5

        voice.oscillator.reset()
        voice.second.reset()
        voice.body.reset()
        voice.secondBody.reset()
        if case .struck(let spec) = currentVoice.source {
            // A struck body carries its whole note in its tones, so the note is
            // made here, once, rather than a sample at a time.
            voice.body.strike(
                frequency: frequency(of: event.pitch), velocity: voice.velocity,
                body: spec, sampleRate: sampleRate
            )
            if currentVoice.detune != 0 {
                voice.secondBody.strike(
                    frequency: frequency(of: event.pitch + currentVoice.detune),
                    velocity: voice.velocity, body: spec, sampleRate: sampleRate
                )
            }
        }
        voice.sampler.reset()
        if case .sampled(let spec) = currentVoice.source {
            if let instrument, !instrument.isEmpty {
                voice.sampler.start(instrument: instrument, pitch: event.pitch,
                                    velocity: voice.velocity, spec: spec,
                                    sampleRate: sampleRate)
            }
        }
        voice.table.reset()
        voice.secondTable.reset()
        if case .wavetable(let scan) = currentVoice.source, let wavetable {
            let played = frequency(of: event.pitch)
            voice.table.start(table: wavetable, scan: scan, frequency: played,
                              sampleRate: sampleRate)
            if currentVoice.detune != 0 {
                voice.secondTable.start(
                    table: wavetable, scan: scan,
                    frequency: frequency(of: event.pitch + currentVoice.detune),
                    sampleRate: sampleRate
                )
            }
            voice.scanEnvelope.prepare(scan.envelope, sampleRate: sampleRate)
            voice.scanEnvelope.noteOn()
        }
        voice.grain.reset()
        if case .granular(let cloud) = currentVoice.source, let grainSource {
            voice.grain.start(source: grainSource, cloud: cloud, pitch: event.pitch,
                              detune: currentVoice.detune, sampleRate: sampleRate,
                              seed: UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9 &+ 0x6C8E_9CF5)
        }
        voice.patch.reset()
        voice.secondPatch.reset()
        if case .patch(let spec) = currentVoice.source {
            let played = frequency(of: event.pitch)
            voice.patch.start(patch: spec, frequency: played, sampleRate: sampleRate)
            if currentVoice.detune != 0 {
                voice.secondPatch.start(
                    patch: spec, frequency: frequency(of: event.pitch + currentVoice.detune),
                    sampleRate: sampleRate
                )
            }
        }
        voice.bow.reset()
        voice.secondBow.reset()
        voice.tube.reset()
        voice.secondTube.reset()
        if case .bowed(let spec) = currentVoice.source {
            // Tuned but not excited: a bow makes no sound until it moves.
            let played = max(SynthRenderer.lowestStringFrequency, frequency(of: event.pitch))
            voice.bow.start(frequency: played, spec: spec, sampleRate: sampleRate)
            if currentVoice.detune != 0 {
                voice.secondBow.start(
                    frequency: max(SynthRenderer.lowestStringFrequency,
                                   frequency(of: event.pitch + currentVoice.detune)),
                    spec: spec, sampleRate: sampleRate
                )
            }
        }
        if case .blown(let spec) = currentVoice.source {
            let played = max(SynthRenderer.lowestStringFrequency, frequency(of: event.pitch))
            voice.tube.start(frequency: played, spec: spec, sampleRate: sampleRate)
            if currentVoice.detune != 0 {
                voice.secondTube.start(
                    frequency: max(SynthRenderer.lowestStringFrequency,
                                   frequency(of: event.pitch + currentVoice.detune)),
                    spec: spec, sampleRate: sampleRate
                )
            }
        }
        if case .plucked(let spec) = currentVoice.source {
            // A string carries its whole note in the line, so the note is made
            // here, once, rather than a sample at a time.
            let played = max(SynthRenderer.lowestStringFrequency, frequency(of: event.pitch))
            voice.string.pluck(
                frequency: played, velocity: voice.velocity, spec: spec, sampleRate: sampleRate
            )
            if currentVoice.detune != 0 {
                let apart = max(
                    SynthRenderer.lowestStringFrequency,
                    frequency(of: event.pitch + currentVoice.detune)
                )
                voice.secondString.pluck(
                    frequency: apart, velocity: voice.velocity, spec: spec, sampleRate: sampleRate
                )
            }
        }
        voice.filter.reset()
        voice.rightFilter.reset()
        voice.right = 0
        voice.amplitude.prepare(currentVoice.envelope, sampleRate: sampleRate)
        voice.amplitude.noteOn()
        voice.filterEnvelope.prepare(currentVoice.filter?.envelope ?? currentVoice.envelope, sampleRate: sampleRate)
        voice.filterEnvelope.noteOn()

        voices[index] = voice
        return index
    }

    /// Picks the voice a new note should use.
    ///
    /// A silent one if there is one, then the note that has already been let go
    /// and is furthest through its tail, and only then the oldest note still
    /// held. Taking a held note last is what keeps a chord intact while a melody
    /// runs over it.
    private func claimVoice() -> Int {
        if let free = voices.firstIndex(where: { !$0.isSounding }) { return free }

        var bestReleasing: (index: Int, level: Double)?
        var oldestHeld: (index: Int, startedAt: Int)?
        for (index, voice) in voices.enumerated() {
            if !voice.isHeld {
                let level = voice.amplitude.level
                if bestReleasing == nil || level < bestReleasing!.level {
                    bestReleasing = (index, level)
                }
            } else if oldestHeld == nil || voice.startedAt < oldestHeld!.startedAt {
                oldestHeld = (index, voice.startedAt)
            }
        }

        let index = bestReleasing?.index ?? oldestHeld?.index ?? 0
        // Cutting a sounding voice dead would click, so it is given a few
        // milliseconds to get out of the way. The new note starts from wherever
        // the envelope had reached, which is the other half of the same trick.
        voices[index].amplitude.steal()
        return index
    }

    /// Lets the note the sketch holds a number for go.
    private func release(id: Int) {
        guard let index = voices.firstIndex(where: { $0.noteID == id && $0.isHeld && $0.isSounding })
        else { return }
        releaseVoice(&voices[index])
    }

    private func release(pitch: Double) {
        // The nearest held note wins, so releasing works with bends and glides.
        var best: (index: Int, distance: Double)?
        for (index, voice) in voices.enumerated() where voice.isHeld && voice.isSounding {
            let distance = abs(voice.pitch - pitch)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        guard let best, best.distance < 0.5 else { return }
        releaseVoice(&voices[best.index])
    }

    private func releaseVoice(_ voice: inout RenderVoice) {
        guard voice.isHeld else { return }
        voice.amplitude.noteOff()
        voice.filterEnvelope.noteOff()
        voice.scanEnvelope.noteOff()
        voice.isHeld = false
        voice.remaining = nil
    }
}

/// Keeps a dense chord inside the range the speakers can take.
///
/// Below the knee this is exactly the identity, so a single note is untouched
/// and only a stack of them is bent. The curve meets the straight part with the
/// same slope, so there is no corner to hear where it takes over.
@inline(__always)
func softClip(_ x: Double) -> Double {
    let knee = 0.8
    let magnitude = abs(x)
    guard magnitude > knee else { return x }
    let excess = (magnitude - knee) / (1 - knee)
    return (x < 0 ? -1 : 1) * (knee + (1 - knee) * tanh(excess))
}
