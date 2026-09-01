import Foundation

/// The recipe for one note: what it is made of, how it is shaped, and what is
/// filtered out of it.
///
/// A `Voice` is a value, so it can be built once and held, copied and adjusted,
/// or changed on a running `Synth` between notes. It says nothing about pitch or
/// loudness: those arrive with the note.
///
/// ```swift
/// let synth = Synth(.pluck)                        // one of the presets
///
/// var glass = Voice.bell                           // or start from one
/// glass.envelope.release = 3
/// glass.filter?.cutoff = 4000
/// ```
public struct Voice: Sendable, Hashable, Codable {
    /// What the note is built from: a wave an oscillator traces, or a string
    /// the note is worked out on.
    public var source: VoiceSource
    /// The wave the note is built from.
    ///
    /// The same thing as ``source`` for a voice built on an oscillator, which
    /// is most of them. Reading it on a string voice gives `.sine`; setting it
    /// makes the voice an oscillator again.
    public var waveform: Waveform {
        get {
            if case .wave(let waveform) = source { return waveform }
            return .sine
        }
        set { source = .wave(newValue) }
    }
    /// The struck body this voice rings as, or nil if it is not one.
    public var struck: ModalBody? {
        get {
            if case .struck(let body) = source { return body }
            return nil
        }
        set { if let newValue { source = .struck(newValue) } }
    }
    /// The string this voice is worked out on, or nil if it is a wave.
    public var plucked: PluckedString? {
        get {
            if case .plucked(let string) = source { return string }
            return nil
        }
        set { if let newValue { source = .plucked(newValue) } }
    }
    /// The patch this voice is built from, or nil if it is not one.
    public var patch: Patch? {
        get {
            if case .patch(let patch) = source { return patch }
            return nil
        }
        set { if let newValue { source = .patch(newValue) } }
    }
    /// How the note's loudness moves over time.
    public var envelope: Envelope
    /// What is filtered out of it, and how that moves. Nil leaves the wave alone.
    public var filter: Filter?
    /// A second oscillator this far from the first, in semitones.
    ///
    /// Small values (a few hundredths) are the point: two oscillators slightly
    /// apart drift in and out of phase with each other, which is what makes a
    /// held note shimmer instead of sitting still. Zero runs a single oscillator.
    public var detune: Double
    /// The voice's own level, `0...1`, before the note's velocity.
    public var gain: Double

    public init(
        waveform: Waveform = .sawtooth,
        envelope: Envelope = .standard,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .wave(waveform), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// A voice built on a plucked string rather than an oscillator.
    ///
    /// The string decides how the note fades, so the envelope's job here is to
    /// let it ring rather than to shape it. `.plucked` is that envelope, and
    /// the presets use it.
    public init(
        plucked: PluckedString,
        envelope: Envelope = .plucked,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .plucked(plucked), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// A voice built on a struck body rather than an oscillator.
    ///
    /// The body decides how the note fades, so the envelope's job here is to
    /// let it ring rather than to shape it.
    public init(
        struck: ModalBody,
        envelope: Envelope = .plucked,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .struck(struck), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// A voice built on a bowed string.
    ///
    /// The bow decides how the note goes, so the envelope's job is to open and
    /// close around it rather than to shape it. `.sustained` is that envelope,
    /// and the presets use it.
    public init(
        bowed: BowedString,
        envelope: Envelope = .sustained,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .bowed(bowed), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// A voice built on a blown tube.
    ///
    /// The breath decides how the note goes, so the envelope only opens and
    /// closes around it.
    public init(
        blown: BlownTube,
        envelope: Envelope = .sustained,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .blown(blown), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// A voice built on a patch: several oscillators and what they do to each
    /// other, rather than one shape an envelope and a filter work on.
    ///
    /// Everything else about a `Voice` still applies. The patch decides what
    /// the note is made of; the envelope and the filter shape it as they shape
    /// anything else.
    public init(
        patch: Patch,
        envelope: Envelope = .standard,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .patch(patch), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// A voice built on recordings rather than on something worked out.
    ///
    /// Which recordings is ``Synth/instrument``, set separately, because they
    /// are far too large to travel inside a note. This says only how they are
    /// played.
    public init(
        sampled: Sampler,
        envelope: Envelope = .plucked,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .sampled(sampled), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    public init(
        source: VoiceSource,
        envelope: Envelope = .standard,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.source = source
        self.envelope = envelope
        self.filter = filter
        self.detune = detune
        self.gain = min(max(0, gain), 1)
    }

    /// What is taken out of the wave, and how that moves while the note sounds.
    public struct Filter: Sendable, Hashable, Codable {
        /// Which side of the cutoff is kept.
        public enum Mode: String, Sendable, Hashable, Codable, CaseIterable {
            /// Keeps what is below the cutoff: the usual one, and what makes a
            /// bright wave sound dark.
            case lowpass
            /// Keeps what is above it: thins a sound out.
            case highpass
            /// Keeps a band around it: hollow and vocal.
            case bandpass
            /// Takes out a band around it, leaving the rest.
            case notch
        }

        public var mode: Mode
        /// Where the filter sits when the note starts, in Hz.
        public var cutoff: Double
        /// How much the filter emphasizes its own cutoff, `0...1`. Past about
        /// 0.7 the cutoff starts to whistle, which is usually the point.
        public var resonance: Double
        /// How far `envelope` moves the cutoff, in octaves. Negative closes the
        /// filter as the note goes on, which is what a plucked string does.
        public var envelopeAmount: Double
        /// The shape of that movement. Ignored when `envelopeAmount` is zero.
        public var envelope: Envelope
        /// How far the cutoff follows the note being played, `0...1`.
        ///
        /// At 0 the filter sits at `cutoff` whatever is played, so high notes
        /// come out duller than low ones (which is what real instruments do, and
        /// why it is the default). At 1 it moves with the note step for step, so
        /// every note is filtered the same distance above its own pitch. That is
        /// what makes an unpitched wave playable: a noise voice has no pitch of
        /// its own, so the filter is the only thing a note can move.
        public var keyTracking: Double

        public init(
            mode: Mode = .lowpass,
            cutoff: Double = 2000,
            resonance: Double = 0.2,
            envelopeAmount: Double = 0,
            envelope: Envelope = .percussive,
            keyTracking: Double = 0
        ) {
            self.mode = mode
            self.cutoff = max(10, cutoff)
            self.resonance = min(max(0, resonance), 1)
            self.envelopeAmount = envelopeAmount
            self.envelope = envelope
            self.keyTracking = min(max(0, keyTracking), 1)
        }

        /// A plain lowpass that does not move.
        public static func lowpass(cutoff: Double, resonance: Double = 0.2) -> Filter {
            Filter(mode: .lowpass, cutoff: cutoff, resonance: resonance)
        }

        /// A lowpass that opens as the note is struck and closes as it decays,
        /// which is most of what a synthesizer sounds like.
        public static func sweep(
            from cutoff: Double, by octaves: Double = 3,
            resonance: Double = 0.3, envelope: Envelope = .percussive
        ) -> Filter {
            Filter(mode: .lowpass, cutoff: cutoff, resonance: resonance,
                   envelopeAmount: octaves, envelope: envelope)
        }
    }
}

// MARK: - Presets

extension Voice {
    /// One partial and nothing else: a test tone, and the quietest thing here.
    public static let sine = Voice(
        waveform: .sine,
        envelope: Envelope(attack: 0.01, decay: 0.1, sustain: 0.8, release: 0.2),
        gain: 0.7
    )

    /// Struck and gone, bright at the front and dark by the end: the sound a
    /// string makes when it is let go rather than bowed.
    public static let pluck = Voice(
        waveform: .sawtooth,
        envelope: Envelope(attack: 0.002, decay: 0.5, sustain: 0, release: 0.2),
        filter: Filter(mode: .lowpass, cutoff: 400, resonance: 0.35,
                       envelopeAmount: 3.5,
                       envelope: Envelope(attack: 0.001, decay: 0.25, sustain: 0, release: 0.15)),
        gain: 0.8
    )

    /// Low, round, and quick: sits under everything else without competing.
    public static let bass = Voice(
        waveform: .square,
        envelope: Envelope(attack: 0.005, decay: 0.15, sustain: 0.6, release: 0.12),
        filter: Filter(mode: .lowpass, cutoff: 180, resonance: 0.25,
                       envelopeAmount: 2.5,
                       envelope: Envelope(attack: 0.002, decay: 0.12, sustain: 0.2, release: 0.1)),
        gain: 0.9
    )

    /// Slow in, slow out, and never quite still, so held notes wash together.
    public static let pad = Voice(
        waveform: .sawtooth,
        envelope: .swell,
        filter: Filter(mode: .lowpass, cutoff: 1200, resonance: 0.15,
                       envelopeAmount: 1.5, envelope: .swell),
        detune: 0.08,
        gain: 0.5
    )

    /// A struck bell: nothing at the front, a long ring, and two tones just far
    /// enough apart to beat against each other.
    public static let bell = Voice(
        waveform: .sine,
        envelope: Envelope(attack: 0.001, decay: 2.5, sustain: 0, release: 1.2),
        detune: 0.35,
        gain: 0.6
    )

    /// Blunt and immediate, and it stops when you do.
    public static let stab = Voice(
        waveform: .sawtooth,
        envelope: .organ,
        filter: Filter(mode: .lowpass, cutoff: 2400, resonance: 0.5),
        detune: 0.05,
        gain: 0.6
    )

    /// A nylon string: soft, round, and gone fairly soon.
    public static let nylon = Voice(plucked: .nylon, gain: 0.85)

    /// A steel string: brighter at the front and longer behind it.
    public static let steel = Voice(plucked: .steel, gain: 0.8)

    /// Plucked near the middle, so the even harmonics are missing and what is
    /// left rings hollow for a long time.
    public static let harp = Voice(plucked: .harp, gain: 0.75)

    /// A string stopped by the hand that plucked it.
    public static let muted = Voice(plucked: .muted, gain: 0.9)

    /// A bowed string close to the bridge: bright, and it keeps going.
    public static let violin = Voice(bowed: .violin, gain: 0.7)

    /// Broader and darker, bowed further along.
    public static let cello = Voice(bowed: .cello, gain: 0.75)

    /// A light bow a long way up the string, almost breathy.
    public static let bowed = Voice(bowed: .sustained, gain: 0.7)

    /// Hollow and woody: a stopped tube, so only the odd harmonics are there.
    public static let clarinet = Voice(blown: .clarinet, gain: 0.62)

    /// Bitten tight: thin and pure, with almost nothing above the third.
    public static let reed = Voice(blown: .reedy, gain: 0.58)

    /// A loose reed on a long tube, dark and full of air.
    public static let hollow = Voice(blown: .hollow, gain: 0.66)

    /// A sine pushed by one at three and a half times its frequency, which is
    /// not a harmonic, so it rings like struck metal rather than like a note.
    public static let fmBell = Voice(patch: .bell, envelope: .percussive, gain: 0.6)

    /// Pushed hard by one an octave up, which fills in the harmonics a filter
    /// would otherwise have had to take away from something brighter.
    public static let fmBrass = Voice(patch: .brass, gain: 0.55)

    /// One operator pushing itself into a buzz.
    public static let fmBuzz = Voice(patch: .buzz, gain: 0.5)

    /// A round drumhead, struck off center.
    public static let drum = Voice(struck: .drum, gain: 0.9)

    /// A bar free at both ends, which is what a xylophone key is.
    public static let bar = Voice(struck: .bar, gain: 0.85)

    /// A bell, with the minor third that makes one sound like a bell.
    public static let chime = Voice(struck: .bell, gain: 0.7)

    /// A glass rung rather than struck: almost nothing at the front and a long
    /// pure tone behind it.
    public static let glass = Voice(struck: .glass, gain: 0.7)

    /// Air rather than pitch: noise through a band the note moves.
    public static let breath = Voice(
        waveform: .noise,
        envelope: Envelope(attack: 0.15, decay: 0.4, sustain: 0.5, release: 0.6),
        filter: Filter(mode: .bandpass, cutoff: 900, resonance: 0.75, keyTracking: 1),
        gain: 0.7
    )
}
