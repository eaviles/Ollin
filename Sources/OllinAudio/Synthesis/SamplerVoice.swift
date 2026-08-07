import Foundation

/// One sampled note's running state: a position in a recording, moving through
/// it at whatever rate the pitch asks for.
///
/// The whole model is a read head. A recording made at one note plays at
/// another by being read faster or slower, which moves its pitch and its length
/// together, exactly as a tape does. That is also the limitation: move a
/// recording far enough and the instrument audibly changes size, which is why a
/// library ships many recordings rather than one.
struct SamplerVoice {
    /// The recordings, held by the instrument rather than copied here. Set
    /// before the note starts and only read afterwards.
    private var instrument: SampledInstrument?
    private var zone = 0
    /// Where the read head is, in samples, as a fraction.
    private var position = 0.0
    /// How far it moves per output sample.
    private var step = 1.0
    private var gain = 1.0
    private var loop: (start: Int, end: Int)?
    private var finished = true

    mutating func reset() {
        instrument = nil
        position = 0
        finished = true
        loop = nil
    }

    /// Whether the recording has run out. A note whose recording has ended has
    /// nothing left to say, whatever its envelope thinks.
    var hasEnded: Bool { finished }

    /// Sets up a note.
    mutating func start(instrument: SampledInstrument, pitch: Double, velocity: Double,
                        spec: Sampled, sampleRate: Double) {
        reset()
        let played = pitch + spec.transpose
        let key = Int(played.rounded())
        guard let index = instrument.zone(for: key, velocity: velocity) else { return }

        let zone = instrument.zones[index]
        guard !zone.frames.isEmpty else { return }
        self.instrument = instrument
        self.zone = index

        // How far the note is from where the recording was made, plus whatever
        // the file says about its own tuning. Every semitone is a step of the
        // twelfth root of two, the same relation a pitch has to a frequency.
        let semitones = played - Double(zone.rootKey) + zone.tune / 100
        // The recording may not be at the rate this is playing at, and both
        // corrections are the same kind of thing, so they multiply.
        step = pow(2, semitones / 12) * (zone.sampleRate / max(1, sampleRate))

        // At zero sensitivity a note is as loud as it was recorded, which is
        // right for an instrument whose recordings are already its dynamics.
        let struck = min(max(0, velocity), 1)
        gain = zone.gain * (1 - spec.velocitySensitivity + spec.velocitySensitivity * struck)

        if spec.loops, let start = zone.loopStart, let end = zone.loopEnd,
           end > start, end < zone.frames.count {
            loop = (start, end)
        }
        position = 0
        finished = false
    }

    /// One sample.
    mutating func next() -> Double {
        guard !finished, let instrument else { return 0 }
        let frames = instrument.zones[zone].frames
        guard !frames.isEmpty else { finished = true; return 0 }

        // Between two samples, because the read head almost never lands on one.
        // Stepping to the nearest instead is audible as a grainy edge on every
        // note that is not at its recorded pitch, which is most of them.
        let whole = Int(position)
        guard whole >= 0, whole < frames.count else { finished = true; return 0 }
        let next = whole + 1 < frames.count ? whole + 1 : whole
        let fraction = position - Double(whole)
        let value = Double(frames[whole]) * (1 - fraction) + Double(frames[next]) * fraction

        position += step
        if let loop, position >= Double(loop.end) {
            // Back to the start of the loop, keeping whatever fraction it
            // overshot by, so looping cannot drift the pitch.
            position -= Double(loop.end - loop.start)
        } else if position >= Double(frames.count) {
            finished = true
        }
        return value * gain
    }
}
