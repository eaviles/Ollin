import Foundation

/// A string, described rather than drawn as a wave.
///
/// A plucked string is not a shape an oscillator traces. It is a length of
/// something under tension with a disturbance running up and down it, losing a
/// little at each end and losing the high part of itself faster than the low
/// part. Modelling that directly, rather than approximating the result, is what
/// makes it move the way a string does: the attack, the way the tone darkens as
/// it rings, and the difference between plucking near the bridge and over the
/// hole all come out of the model rather than being dialled in.
///
/// ```swift
/// let synth = Synth(.nylon)
/// synth.play("E3", for: 2)
/// ```
///
/// The four numbers are the ones a player has. Where the string is plucked, how
/// hard, how long it rings, and how quickly the bright part of it goes.
public struct PluckedString: Sendable, Hashable, Codable {

    /// Where along the string it is plucked, `0...1`, measured from one end.
    ///
    /// This is the one that sounds least like a synthesizer setting and most
    /// like a hand. Plucking at a point silences the harmonics that have a node
    /// there, so a pluck at 1/2 loses every even harmonic and comes out hollow,
    /// while one near the bridge keeps them all and comes out thin and nasal.
    /// A quarter of the way along is roughly where a guitar is played.
    public var pick: Double

    /// How hard the pluck is, `0...1`.
    ///
    /// A fingertip lets go of a string slowly and only sets the low part of it
    /// moving; a plectrum lets go at once and sets all of it moving. The note's
    /// velocity moves this as well, so playing harder is brighter without
    /// changing anything here.
    public var hardness: Double

    /// How long the note takes to fade away, in seconds.
    ///
    /// Measured at the pitch being played, and a real string holds a low note
    /// longer than a high one, so this is the time at the note rather than a
    /// fixed one for the instrument.
    public var decay: Double

    /// How much sooner the bright part of the note goes than the low part,
    /// `0...1`.
    ///
    /// At 0 every harmonic fades together, which sounds synthetic. At 1 the top
    /// goes almost at once and the note darkens as it rings, which is what a
    /// real string does and why a held note changes color without anything
    /// moving.
    public var damping: Double

    public init(
        pick: Double = 0.26,
        hardness: Double = 0.55,
        decay: Double = 2.4,
        damping: Double = 0.55
    ) {
        self.pick = min(max(0.01, pick), 0.99)
        self.hardness = min(max(0, hardness), 1)
        self.decay = max(0.02, decay)
        self.damping = min(max(0, damping), 1)
    }

    // MARK: Presets

    /// Soft and round, and it does not ring for long.
    public static let nylon = PluckedString(
        pick: 0.28, hardness: 0.35, decay: 1.8, damping: 0.7
    )

    /// Brighter and longer, with more of the pluck left in the front of it.
    public static let steel = PluckedString(
        pick: 0.16, hardness: 0.8, decay: 3.6, damping: 0.4
    )

    /// Plucked near the middle, so the even harmonics are missing and it comes
    /// out hollow and bell-like.
    public static let harp = PluckedString(
        pick: 0.45, hardness: 0.4, decay: 5.0, damping: 0.3
    )

    /// Almost no ring at all: the sound of a string stopped by the hand that
    /// plucked it.
    public static let muted = PluckedString(
        pick: 0.12, hardness: 0.9, decay: 0.24, damping: 0.85
    )
}

/// What a voice is built from.
///
/// A wave is drawn; the rest are modelled. They all end up as one stream of
/// samples the envelope and filter shape the same way, so everything else about
/// a `Voice` is unchanged whichever it is.
///
/// The models split into two kinds, and the difference is audible. A string and
/// a struck body are **set going once** and then left to fade, so the whole
/// note is decided at its start. A bow and a breath are **kept going**, so the
/// note lasts as long as the player keeps driving it and can change while it
/// sounds. `Synth.drive` is that driving.
public enum VoiceSource: Sendable, Hashable, Codable {
    /// An oscillator tracing a shape.
    case wave(Waveform)
    /// A plucked string, worked out rather than drawn.
    case string(PluckedString)
    /// A struck body, ringing at the frequencies its shape implies.
    case body(ModalBody)
    /// A bowed string, which sounds for as long as the bow moves.
    case bowed(BowedString)
    /// A blown tube, which sounds for as long as the breath lasts.
    case blown(BlownTube)
    /// Several oscillators and what they do to each other, built rather than
    /// picked. See ``Patch``.
    case patch(Patch)
    /// A recording, moved to whatever pitch is asked for. The recordings
    /// themselves live on the ``Synth``, since they are far too large to
    /// travel inside a note. See ``SampledInstrument``.
    case sampled(Sampled)

    /// Whether this source has to be driven to keep sounding.
    ///
    /// The two driven kinds read `Synth.drive`; the rest ignore it entirely.
    public var isDriven: Bool {
        switch self {
        case .bowed, .blown: return true
        case .wave, .string, .body, .patch, .sampled: return false
        }
    }
}
