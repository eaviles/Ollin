import AVFoundation
import Foundation
import Ollin

/// The sound a grain cloud cuts its grains out of.
///
/// One stretch of audio and the note it plays untransposed at. Where a
/// ``SampledInstrument`` holds many recordings and picks the one nearest the
/// note, a cloud reads one and is read by position rather than from the start,
/// so the same second of sound can be held still, crawled through, or scattered
/// over.
///
/// ```swift
/// synth.grainSource = GrainSource(recording: SampledInstrument.builtIn!.recording(at: 2, over: 0...127))
/// synth.voice = Voice(granular: GrainCloud(size: 0.08, density: 40, speed: 0))
/// synth.play("C4", for: 4)                   // a held moment of that bar
/// ```
///
/// ### Why this is a reference rather than a value
///
/// The same reason ``SampledInstrument`` is. A `Voice` travels to the audio
/// thread inside a note and has to be copyable a word at a time; a few seconds
/// of sound is hundreds of kilobytes on the heap. So the source is held by the
/// ``Synth`` and the note carries only ``GrainCloud``, which is numbers.
public final class GrainSource: @unchecked Sendable {

    /// The samples, one channel.
    public let frames: [Float]

    /// The rate they were recorded at.
    public let sampleRate: Double

    /// The note the source reads at its own speed. A note this far above it
    /// reads each grain that much faster, exactly as a tape does, which moves
    /// its pitch without moving how fast the cloud travels through the sound.
    public let rootKey: Int

    /// What it is called, for a sketch that wants to say.
    public let name: String

    /// How long it is, in seconds.
    public var duration: Double {
        sampleRate > 0 ? Double(frames.count) / sampleRate : 0
    }

    /// Whether there is anything to cut grains from.
    public var isEmpty: Bool { frames.count < 2 }

    /// A source from samples already in hand.
    public init(name: String = "source", frames: [Float], sampleRate: Double,
                rootKey: Int = 60) {
        self.name = name
        self.frames = frames
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        self.rootKey = rootKey
    }

    /// A source from one of a sampled instrument's recordings, which is also
    /// what a stretched recording comes back as.
    public convenience init(name: String = "source", recording: SampledInstrument.Recording) {
        self.init(name: name, frames: recording.frames,
                  sampleRate: recording.sampleRate, rootKey: recording.rootKey)
    }

    /// A source read from an audio file. Folded to one channel, like every
    /// other recording here.
    public convenience init?(contentsOf url: URL, rootKey: Int = 60) {
        guard let (frames, rate) = SampledInstrument.read(url) else {
            audioNoteOnce("could not read the sound at \(url.lastPathComponent).")
            return nil
        }
        self.init(name: url.deletingPathExtension().lastPathComponent,
                  frames: frames, sampleRate: rate, rootKey: rootKey)
    }

    /// A source read from an audio file bundled with a sketch.
    ///
    /// The bundle is explicit because a default would resolve to Ollin's own
    /// rather than the caller's, which is the rule every loader here follows.
    public convenience init?(named name: String, withExtension ext: String = "wav",
                             in bundle: Bundle, rootKey: Int = 60) {
        let base = (name as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext) else {
            audioNoteOnce("no sound named \(name) in that bundle.")
            return nil
        }
        self.init(contentsOf: url, rootKey: rootKey)
    }

    /// A source drawn rather than recorded: `seconds` of a wave at `frequency`,
    /// through the same anti-aliased oscillator a voice reads.
    ///
    /// Granulating a plain wave is the way to hear a cloud with nothing loaded,
    /// and holding the position still over a wave is how a grain rate becomes
    /// a tone of its own.
    public convenience init(waveform: Waveform, frequency: Double = 220,
                            seconds: Double = 1, sampleRate: Double = 44100,
                            seed: Int = 0x5EED) {
        let rate = sampleRate > 0 ? sampleRate : 44100
        let count = max(2, Int(max(0.01, seconds) * rate))
        var oscillator = Oscillator(seed: UInt64(bitPattern: Int64(seed)))
        let increment = max(1e-9, frequency) / rate
        var frames = [Float](repeating: 0, count: count)
        for index in 0..<count {
            frames[index] = Float(oscillator.next(waveform, increment: increment))
        }
        let root = 69 + 12 * log2(max(1e-9, frequency) / 440)
        self.init(name: waveform.rawValue, frames: frames, sampleRate: rate,
                  rootKey: Int(root.rounded()))
    }

    /// A short sound Ollin carries, so a cloud can be heard working without
    /// loading anything: the middle recording of the bundled struck bar.
    ///
    /// Generated rather than sourced, like the instrument it comes from, so it
    /// is Ollin's own and carries no license of anyone else's.
    public static let builtIn: GrainSource? = {
        guard let instrument = SampledInstrument.builtIn, !instrument.isEmpty else { return nil }
        let middle = instrument.recordingCount / 2
        return GrainSource(name: "struck bar",
                           recording: instrument.recording(at: middle, over: 0...127))
    }()
}

// MARK: - The envelope one grain wears

/// The shape a single grain fades in and out with.
///
/// A grain is a few thousandths of a second of sound, and cutting one out with
/// a straight edge is a click at each end. The shape is what the cut is made
/// with, and at these lengths it is most of the character: the same sound
/// through a soft bell and through a sharp tick is two instruments.
public enum GrainShape: String, Sendable, Hashable, Codable, CaseIterable {
    /// A raised cosine: no corner anywhere, and nothing added to the sound.
    /// The one to reach for, and the default.
    case bell
    /// A narrower bell that never quite reaches the ends, so a grain is
    /// softer still and overlaps further into its neighbors.
    case gaussian
    /// Straight up and straight down, which is a corner at the peak: a little
    /// brighter than the bell, and cheaper to think about.
    case triangle
    /// Flat in the middle with a short fade at each end, so the middle of the
    /// grain is the sound exactly as it was recorded. What to use when the
    /// cloud is meant to sound like the source and not like grains.
    case plateau
    /// Sharp at the front and falling away: every grain is a tick, and a cloud
    /// of them is a rattle or a rain.
    case tick
    /// The same shape backward, a swell into a sudden stop, which is the sound
    /// of a tape played in reverse without reversing anything.
    case swell
}

extension GrainShape {
    /// The shape's level at `t`, `0` the start of a grain to `1` the end.
    ///
    /// The shape as a function rather than as something that happens, which is
    /// what lets a sketch draw the cut it chose, the way
    /// ``Envelope/level(at:heldFor:)`` draws the note. It is the same table the
    /// grains themselves are read through, so the picture cannot disagree with
    /// the sound.
    public func level(at t: Double) -> Double {
        GrainVoice.window(self, at: t)
    }
}

// MARK: - The cloud itself

/// How a note cuts grains out of the ``Synth/grainSource``: how big they are,
/// how many, where from, and how far each one strays.
///
/// The idea underneath is that any sound at all can be built from short bursts,
/// each too brief to have a pitch of its own, and that what you hear is the
/// statistics of the pile rather than any one of them. So there are two clocks
/// here that are normally one. The **grains** are read at whatever speed the
/// note's pitch asks for; the **position** they are cut from travels at
/// ``speed``, which is a separate number. Set `speed` to 0 and the position
/// stops while the note keeps sounding, which is the one thing nothing else in
/// this tier does: a moment of a recording, held.
///
/// ```swift
/// GrainCloud()                                      // a cloud over the source, moving with it
/// GrainCloud(size: 0.05, density: 60, speed: 0)     // that moment, held
/// GrainCloud(density: 8, positionJitter: 0.3, pitchSpread: 7)   // scattered and sparse
/// ```
///
/// Small and made only of numbers, because this is the part that travels to
/// the audio thread inside a note. The sound itself stays on the ``Synth``.
public struct GrainCloud: Sendable, Hashable, Codable {

    /// How long one grain lasts, in seconds, `0.001...1`.
    ///
    /// The number that decides what a cloud is. Under about 0.01 a grain is
    /// too short to carry a pitch and the cloud turns into texture; over about
    /// 0.1 each grain is long enough to be heard as a fragment of the source.
    public var size: Double

    /// How many grains start each second, `0.1...1000`.
    ///
    /// Below about 10 you hear them one at a time. Past about 1 / ``size``
    /// they overlap and the cloud becomes continuous. Loudness rises with the
    /// square root of this, because grains land on each other at random and
    /// power adds where amplitude would not.
    public var density: Double

    /// Where in the source the note starts cutting, `0` the beginning to `1`
    /// the end.
    public var position: Double

    /// How far each grain strays from that, as a fraction of the whole source,
    /// `0...1`.
    ///
    /// A little is what keeps a dense cloud from sounding like one sound played
    /// many times: grains that come from different places do not line up, so
    /// they pile into texture rather than into a louder copy.
    public var positionJitter: Double

    /// How fast the position travels through the source, as a multiple of the
    /// source's own speed, `-4...4`.
    ///
    /// At 1 the cloud crawls along the sound at the speed it was recorded, so
    /// it is the source with grain over it. At 0 the position stops and the
    /// note holds that moment for as long as it sounds. Negative runs backward.
    /// The note's pitch is not involved either way, which is the whole point:
    /// time and pitch are two knobs here rather than one.
    public var speed: Double

    /// How far each grain's pitch strays from the note, in semitones either
    /// way, `0...24`.
    ///
    /// Small values thicken; a fifth or an octave turns the cloud into a chord
    /// of itself.
    public var pitchSpread: Double

    /// How far each grain is thrown to one side or the other, `0...1`.
    ///
    /// At 0 every grain is in the middle. At 1 they land anywhere across the
    /// stereo picture, which is what makes a cloud sound like a space rather
    /// than a point. A ``Synth`` placed in the 3D scene is one stream by
    /// definition, so a placed instrument folds this back to the middle.
    public var panSpread: Double

    /// How irregularly the grains start, `0...1`.
    ///
    /// At 0 they start on a strict clock, and a fast one is heard as a pitch
    /// of its own at ``density`` hertz. At 1 the gap between them is random
    /// with the same average, which is what makes a cloud a cloud.
    public var timingJitter: Double

    /// The shape each grain fades in and out with.
    public var shape: GrainShape

    /// Which timingJitter this is. The same seed gives the same cloud, so a cloud
    /// can be tuned and kept.
    public var seed: Int

    public init(size: Double = 0.06, density: Double = 30, position: Double = 0,
                positionJitter: Double = 0.02, speed: Double = 1,
                pitchSpread: Double = 0, panSpread: Double = 0,
                timingJitter: Double = 1, shape: GrainShape = .bell,
                seed: Int = 0x5EED) {
        self.size = min(max(0.001, size), 1)
        self.density = min(max(0.1, density), 1000)
        self.position = min(max(0, position), 1)
        self.positionJitter = min(max(0, positionJitter), 1)
        self.speed = min(max(-4, speed), 4)
        self.pitchSpread = min(max(0, pitchSpread), 24)
        self.panSpread = min(max(0, panSpread), 1)
        self.timingJitter = min(max(0, timingJitter), 1)
        self.shape = shape
        self.seed = seed
    }

    /// A cloud held at one place in the source, which is the sound this is
    /// here for: the note keeps going and the sound stops moving.
    public static func frozen(at position: Double, size: Double = 0.06,
                              density: Double = 40) -> GrainCloud {
        GrainCloud(size: size, density: density, position: position,
                   positionJitter: 0.005, speed: 0)
    }
}

extension Voice {
    /// A voice built from grains cut out of the synth's ``Synth/grainSource``.
    ///
    /// Which sound is set separately, because it is far too large to travel
    /// inside a note. This says only how it is cut up.
    public init(
        granular cloud: GrainCloud,
        envelope: Envelope = .sustained,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .granular(cloud), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// How this voice cuts its grains, or nil if it is not a cloud.
    public var granular: GrainCloud? {
        get {
            if case .granular(let cloud) = source { return cloud }
            return nil
        }
        set { if let newValue { source = .granular(newValue) } }
    }

    /// A held moment, scattered wide: the position stops, the grains keep
    /// coming, and each one lands somewhere else in the picture.
    public static let cloud = Voice(
        granular: GrainCloud(size: 0.08, density: 45, positionJitter: 0.01, speed: 0,
                             pitchSpread: 0.15, panSpread: 0.8),
        envelope: Envelope(attack: 0.4, decay: 0.3, sustain: 0.85, release: 1.2),
        gain: 0.7
    )

    /// The source crawling past at a fraction of its own speed, in pieces:
    /// the same sound, stretched, with nothing moved in pitch.
    public static let smear = Voice(
        granular: GrainCloud(size: 0.12, density: 24, positionJitter: 0.004, speed: 0.15,
                             panSpread: 0.4, shape: .plateau),
        envelope: Envelope(attack: 0.05, decay: 0.2, sustain: 0.9, release: 0.6),
        gain: 0.75
    )

    /// Short, sparse, and sharp at the front: grains heard one at a time.
    public static let rain = Voice(
        granular: GrainCloud(size: 0.012, density: 90, positionJitter: 0.5, speed: 0,
                             pitchSpread: 9, panSpread: 1, shape: .tick),
        envelope: Envelope(attack: 0.08, decay: 0.2, sustain: 0.8, release: 0.5),
        gain: 0.6
    )
}

/// Where a grain cloud's reading was dragged to, and when.
///
/// A scrub is a control rather than an onset, so it is written down only when
/// it changes and applied at the next block during an export, the way a
/// placing is.
struct RecordedScrub: Equatable {
    var at: Double
    var value: Double
}
