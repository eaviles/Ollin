import Foundation

/// The shape of a note over time: how fast it arrives, how it settles while
/// held, and how long it takes to go.
///
/// The four numbers are the classic ones. `attack` is the time from silence to
/// full level, `decay` the time to fall from there to `sustain`, `sustain` the
/// level a held note rests at, and `release` the time to fall back to silence
/// once the note is let go.
///
/// ```swift
/// Envelope(attack: 0.001, decay: 0.4, sustain: 0, release: 0.1)   // a pluck
/// Envelope(attack: 0.8, decay: 1.0, sustain: 0.7, release: 1.5)   // a pad
/// ```
///
/// The times are seconds, and a falling segment is exponential, so `decay` and
/// `release` are the time to come within a thousandth of where they are headed:
/// what the ear reads as the note being over.
public struct Envelope: Sendable, Hashable, Codable {
    /// Seconds from silence to full level.
    public var attack: Double
    /// Seconds from full level down to `sustain`.
    public var decay: Double
    /// The level a held note rests at, `0...1`.
    public var sustain: Double
    /// Seconds from wherever the note was to silence, once it is let go.
    public var release: Double

    public init(attack: Double = 0.01, decay: Double = 0.1, sustain: Double = 0.7, release: Double = 0.3) {
        self.attack = max(0, attack)
        self.decay = max(0, decay)
        self.sustain = min(max(0, sustain), 1)
        self.release = max(0, release)
    }

    /// The level this envelope is at `time` seconds into a note held for
    /// `heldFor` seconds.
    ///
    /// The shape as a function rather than as something that happens, which is
    /// what lets a sketch draw the sound it designed, or size a shape by where
    /// a note has got to. It agrees with what is actually played.
    public func level(at time: Double, heldFor hold: Double) -> Double {
        guard time > 0 else { return 0 }
        if time <= hold { return levelWhileHeld(at: time) }
        guard release > 0 else { return 0 }
        // The release runs from wherever the note had reached, which is why a
        // note let go early falls a shorter distance rather than jumping.
        return levelWhileHeld(at: hold) * exp(-6.907755278982137 * (time - hold) / release)
    }

    private func levelWhileHeld(at time: Double) -> Double {
        if time < attack { return attack > 0 ? time / attack : 1 }
        guard decay > 0 else { return sustain }
        let since = time - attack
        return sustain + (1 - sustain) * exp(-6.907755278982137 * since / decay)
    }

    /// Struck and gone: no sustain at all, so the note tells its whole story on
    /// its own. Bells, plucks, and drums.
    public static let percussive = Envelope(attack: 0.001, decay: 0.35, sustain: 0, release: 0.15)
    /// A quick, blunt attack that holds while the note is held. Organs, stabs.
    public static let organ = Envelope(attack: 0.005, decay: 0.02, sustain: 0.9, release: 0.08)
    /// Slow in and slow out, so notes overlap into each other. Strings and pads.
    public static let swell = Envelope(attack: 0.7, decay: 0.9, sustain: 0.7, release: 1.6)
    /// The default: audible attack, gentle fall, moderate tail.
    public static let standard = Envelope()
    /// Out of the way: a string decides for itself how a note fades, so the
    /// envelope's only job is to open at once, hold, and let go without a
    /// click. Anything shorter would cut the string off mid-ring.
    public static let plucked = Envelope(attack: 0.0005, decay: 0.01, sustain: 1, release: 0.12)
    /// Out of the way in the other direction: a bow or a breath keeps the note
    /// going by itself, so the envelope only has to open without a click and
    /// close without cutting the tail off. The attack is long enough that the
    /// model has time to start speaking, which a real one also needs.
    public static let sustained = Envelope(attack: 0.03, decay: 0.02, sustain: 1, release: 0.18)
}

/// One envelope's running state, advanced a sample at a time by a voice.
struct EnvelopeRunner {
    enum Stage { case idle, attack, decay, sustain, release }

    private(set) var stage: Stage = .idle
    /// The current output, `0...1`.
    private(set) var level: Double = 0

    private var spec = Envelope()
    private var sampleRate: Double = 44100

    /// Per-sample step for the (linear) attack ramp.
    private var attackStep: Double = 1
    /// Per-sample multiplier on the distance still to travel, for the falls.
    private var decayCoefficient: Double = 0
    private var releaseCoefficient: Double = 0

    /// Whether the envelope has finished and its voice can be reused.
    var isFinished: Bool { stage == .idle }

    mutating func prepare(_ envelope: Envelope, sampleRate: Double) {
        self.spec = envelope
        self.sampleRate = sampleRate
        attackStep = envelope.attack > 0 ? 1 / (envelope.attack * sampleRate) : 1
        decayCoefficient = Self.coefficient(seconds: envelope.decay, sampleRate: sampleRate)
        releaseCoefficient = Self.coefficient(seconds: envelope.release, sampleRate: sampleRate)
    }

    /// A falling segment approaches its target rather than arriving, so the
    /// stated time is read as the time to come within a thousandth of it. A
    /// segment shorter than one sample simply lands.
    private static func coefficient(seconds: Double, sampleRate: Double) -> Double {
        let samples = seconds * sampleRate
        guard samples >= 1 else { return 0 }
        return exp(-6.907755278982137 / samples)   // ln(0.001)
    }

    /// Starts a note.
    ///
    /// The attack runs from wherever the envelope already is, not from silence,
    /// so retriggering a voice that is still sounding bends its level into the
    /// new note instead of cutting to zero and clicking.
    mutating func noteOn() {
        stage = .attack
    }

    /// Lets a note go. The release runs from the current level for the same
    /// reason: a note released early has less distance to fall, not a jump.
    mutating func noteOff() {
        guard stage != .idle else { return }
        stage = .release
    }

    /// Cuts the note short over a few milliseconds. Used when a voice is taken
    /// for a new note, where stopping outright would click.
    mutating func steal() {
        stage = .release
        releaseCoefficient = Self.coefficient(seconds: 0.005, sampleRate: sampleRate)
    }

    /// Advances one sample and returns the new level.
    mutating func next() -> Double {
        switch stage {
        case .idle:
            level = 0

        case .attack:
            level += attackStep
            if level >= 1 {
                level = 1
                stage = spec.decay > 0 || spec.sustain < 1 ? .decay : .sustain
            }

        case .decay:
            level = spec.sustain + (level - spec.sustain) * decayCoefficient
            if level - spec.sustain < 0.0001 {
                level = spec.sustain
                stage = .sustain
            }

        case .sustain:
            level = spec.sustain
            // A sustain of zero means the note has already told its story.
            if level <= 0 { stage = .idle }

        case .release:
            level *= releaseCoefficient
            if level < 0.0001 {
                level = 0
                stage = .idle
            }
        }
        return level
    }
}
