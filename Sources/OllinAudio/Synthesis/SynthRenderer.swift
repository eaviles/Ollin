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
        var amplitude = EnvelopeRunner()
        var filterEnvelope = EnvelopeRunner()
        /// The envelope a wavetable scan moves its position by.
        var scanEnvelope = EnvelopeRunner()
        var filter = StateVariableFilter()

        var spec = Voice()
        var pitch: Double = 60
        var velocity: Double = 0
        /// Samples left before the note releases itself, or nil if it is held.
        var remaining: Int?
        /// Whether the note is still held, so a `noteOff` can find it.
        var isHeld = false
        /// When the note started, for deciding which voice to take.
        var startedAt: Int = 0

        var isSounding: Bool { !amplitude.isFinished }
    }

    private var voices: [RenderVoice]
    private let sampleRate: Double
    private let events: EventRing
    /// Every string voice's delay line, taken in one piece before the first
    /// note. Raw memory rather than arrays because the render thread writes it.
    private let stringMemory: UnsafeMutablePointer<Double>
    private let stringCapacity: Int
    /// Every driven voice's delay lines, taken in one piece for the same reason.
    private let drivenMemory: UnsafeMutablePointer<Double>
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

    /// The voice every new note is built from. Changed between notes.
    private var currentVoice: Voice

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

    /// How many voices are sounding, published for the sketch to read.
    ///
    /// Written once per block by the render thread rather than read off the
    /// voice array, which only that thread may touch.
    var activeVoiceCount: Int { activeCount.load(ordering: .relaxed) }
    private let activeCount = Atomic<Int>(0)

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

        let memory = stringMemory
        let driven = drivenMemory
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
                secondPatch: PatchVoice(seed: seed &+ step &* 0x94D049BB &+ 1)
            )
        }
    }

    deinit {
        stringMemory.deallocate()
        drivenMemory.deallocate()
    }

    /// The lowest note a string voice can be tuned to, which is what sizes the
    /// delay lines. Below it the note is played sharp rather than the buffer
    /// being outrun.
    static let lowestStringFrequency = 16.0

    /// Fills `output` with the next `frameCount` samples, applying anything the
    /// sketch has asked for since the last block.
    func render(into output: UnsafeMutableBufferPointer<Float>, frameCount: Int) {
        drainEvents()
        let level = gain
        // Read once for the block rather than once a sample: it is a control,
        // not a signal, and a block is a few milliseconds.
        let driving = pressure

        for frame in 0..<frameCount {
            var mix = 0.0
            for index in voices.indices where voices[index].isSounding {
                mix += nextSample(&voices[index], pressure: driving)
            }
            output[frame] = Float(softClip(mix * level))
            clock += 1
        }

        activeCount.store(voices.count { $0.isSounding }, ordering: .relaxed)
    }

    /// One sample from one voice.
    private func nextSample(_ voice: inout RenderVoice, pressure: Double) -> Double {
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

        var sample: Double
        switch voice.spec.source {
        case .wave(let waveform):
            let increment = frequency(of: voice.pitch) / sampleRate
            sample = voice.oscillator.next(waveform, increment: increment)
            if voice.spec.detune != 0 {
                let detuned = frequency(of: voice.pitch + voice.spec.detune) / sampleRate
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
        }

        if let spec = voice.spec.filter {
            let envelope = voice.filterEnvelope.next()
            // The envelope moves the cutoff in octaves, and key tracking moves
            // it with the note, so both are multiples of where it started.
            var cutoff = spec.cutoff
            if spec.envelopeAmount != 0 { cutoff *= pow(2, spec.envelopeAmount * envelope) }
            if spec.keyTracking != 0 { cutoff *= pow(2, spec.keyTracking * (voice.pitch - 60) / 12) }
            voice.filter.setCoefficients(cutoff: cutoff, resonance: spec.resonance, sampleRate: sampleRate)
            sample = voice.filter.next(sample, mode: spec.mode)
        }

        // A sampled voice has already taken the note's velocity into account,
        // because how much of it is heard is one of its own settings: an
        // instrument whose recordings are already its dynamics should not be
        // scaled by velocity a second time. Every other source is scaled here
        // as it always was.
        var struck = voice.velocity
        if case .sampled = voice.spec.source { struck = 1 }
        return sample * amplitude * struck * voice.spec.gain
    }

    private func frequency(of midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    // MARK: Events

    private func drainEvents() {
        while let event = events.pop() {
            switch event.kind {
            case .noteOn:      start(event)
            case .noteOff:     release(pitch: event.pitch)
            case .allNotesOff: for index in voices.indices { releaseVoice(&voices[index]) }
            case .changeVoice: currentVoice = event.voice
            }
        }
    }

    private func start(_ event: SynthEvent) {
        let index = claimVoice()
        var voice = voices[index]

        voice.spec = currentVoice
        voice.pitch = event.pitch
        voice.velocity = min(max(0, event.velocity), 1)
        voice.remaining = event.durationSamples > 0 ? event.durationSamples : nil
        voice.isHeld = event.durationSamples == 0
        voice.startedAt = clock

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
        voice.amplitude.prepare(currentVoice.envelope, sampleRate: sampleRate)
        voice.amplitude.noteOn()
        voice.filterEnvelope.prepare(currentVoice.filter?.envelope ?? currentVoice.envelope, sampleRate: sampleRate)
        voice.filterEnvelope.noteOn()

        voices[index] = voice
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
