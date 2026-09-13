import AVFoundation
import os

// MARK: - The two that work in the spectrum

/// The pitch moved without the length.
///
/// A sampler moves pitch and length together, like a tape. This moves the
/// pitch alone: a chord an octave up still lasts as long as it did, a phrase
/// a fifth up still lands on the beat. Under a `mix` of 1 the original sounds
/// with it, which is a harmonizer: a fifth at half mix puts a second voice
/// under every note.
///
/// ```swift
/// synth.effects = [.pitchShift(PitchShift(semitones: 7, mix: 0.5))]
/// ```
///
/// The sound is read in frames of about forty milliseconds, and the whole
/// effect arrives that much later than it went in. A struck attack comes out
/// a little softer than it went in, which is what every pitch shifter of this
/// kind does, and a plain tone comes out clean.
public struct PitchShift: Sendable, Hashable, Codable {
    /// How far to move the pitch, in semitones, `-24...24`. Twelve is an
    /// octave; a fraction is a fine tuning.
    public var semitones: Double
    /// How much of the result is the moved sound rather than the original,
    /// `0...1`. At 1 only the moved sound is heard; under it the two sound
    /// together.
    public var mix: Double

    public init(semitones: Double = 12, mix: Double = 1) {
        self.semitones = min(max(-24, semitones), 24)
        self.mix = min(max(0, mix), 1)
    }

    /// The moved pitch as a ratio of the original.
    var ratio: Double { pow(2, semitones / 12) }
}

/// The sound of one instant, held for as long as you like.
///
/// The moment `amount` rises above 0, the spectrum of what is playing at
/// that instant is caught: every partial at its level and its exact
/// frequency. From then on that instant is played back, its partials
/// carried on at the frequencies they had, for as long as the amount stays
/// up. A struck chord becomes a pad; a consonant becomes a drone. Back at 0
/// the instant is let go and the sound passes as it was.
///
/// ```swift
/// synth.effects = [.freeze(Freeze(amount: mouseIsPressed ? 1 : 0))]
/// ```
///
/// `amount` is also the blend, so a freeze can be eased in and out rather
/// than switched. Put it in the chain at 0 and raise it when there is
/// something to hold: a freeze that starts at 1 holds the silence before
/// the first note.
public struct Freeze: Sendable, Hashable, Codable {
    /// How much of the result is the held instant rather than what is
    /// playing, `0...1`. Rising from 0 catches the instant; back at 0 lets
    /// it go.
    public var amount: Double

    public init(amount: Double = 1) {
        self.amount = min(max(0, amount), 1)
    }
}

// MARK: - The work

/// The spectrum itself: one channel of sound run through the phase vocoder.
///
/// Holds the frame of sound being assembled, the dry sound delayed by one
/// frame so the two halves of a blend line up, and the overlap-add of the
/// frames written back. Everything is allocated once, here.
final class SpectralChannel {
    let vocoder: PhaseVocoder
    private let frameSize: Int
    private let hop: Int

    /// The last `frameSize` samples that came in, as a ring.
    private let input: UnsafeMutablePointer<Float>
    private var inputWrite = 0
    private var received = 0
    private var sinceFrame = 0
    /// The frame in order, oldest first, for the analysis.
    private let assembled: UnsafeMutablePointer<Float>
    /// The dry sound, one frame late.
    private let dry: UnsafeMutablePointer<Float>
    private var dryIndex = 0

    /// The frames written back, summed, and the window weight under each
    /// sample, both indexed by the sample's own position.
    private let ringMask: Int
    private let sum: UnsafeMutablePointer<Float>
    private let weight: UnsafeMutablePointer<Float>
    /// Where the next frame lands. Framing starts as soon as a hop has come
    /// in, over a ring that is otherwise still silent, so the first frames
    /// land before position zero and the first sample read is under a full
    /// stack of windows like every other.
    private var framePosition: Int
    private var readPosition = 0
    private var hasFirstFrame = false
    private var wantsFreshPhases = false

    /// The instant a freeze holds.
    private let heldMagnitude: UnsafeMutablePointer<Float>
    private let heldPhase: UnsafeMutablePointer<Float>
    private let heldFrequency: UnsafeMutablePointer<Float>
    private(set) var isHolding = false

    /// How many samples later than it went in the sound comes out.
    var latency: Int { frameSize }

    init(frameSize: Int) {
        vocoder = PhaseVocoder(frameSize: frameSize)
        self.frameSize = frameSize
        hop = vocoder.hop
        framePosition = hop - frameSize
        func floats(_ count: Int) -> UnsafeMutablePointer<Float> {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
            pointer.initialize(repeating: 0, count: count)
            return pointer
        }
        input = floats(frameSize)
        assembled = floats(frameSize)
        dry = floats(frameSize)
        let ring = frameSize * 4
        ringMask = ring - 1
        sum = floats(ring)
        weight = floats(ring)
        heldMagnitude = floats(vocoder.bins)
        heldPhase = floats(vocoder.bins)
        heldFrequency = floats(vocoder.bins)
    }

    deinit {
        for pointer in [input, assembled, dry, sum, weight, heldMagnitude, heldPhase, heldFrequency] {
            pointer.deallocate()
        }
    }

    /// Rewrites `count` samples in place.
    ///
    /// - Parameters:
    ///   - ratio: what to multiply every frequency by; 1 leaves the pitch.
    ///   - holding: whether to hold the instant being played rather than
    ///     follow the sound. The first frame after this turns true is caught.
    ///   - amount: how much of the result is the worked sound, the rest being
    ///     the sound as it came in, delayed to match.
    func process(_ samples: UnsafeMutableBufferPointer<Float>, count: Int,
                 ratio: Float, holding: Bool, amount: Float) {
        guard let base = samples.baseAddress else { return }
        for index in 0..<count {
            let sample = base[index]
            input[inputWrite] = sample
            inputWrite = (inputWrite + 1) & (frameSize - 1)
            let delayed = dry[dryIndex]
            dry[dryIndex] = sample
            dryIndex = (dryIndex + 1) & (frameSize - 1)
            received += 1
            sinceFrame += 1
            if sinceFrame == hop {
                sinceFrame = 0
                runFrame(ratio: ratio, holding: holding)
            }
            var wet: Float = 0
            if received > frameSize {
                let slot = readPosition & ringMask
                let under = weight[slot]
                wet = under > 1e-6 ? sum[slot] / under : 0
                sum[slot] = 0
                weight[slot] = 0
                readPosition += 1
            }
            base[index] = delayed + (wet - delayed) * amount
        }
    }

    /// One frame: read the last `frameSize` samples, carry the phases on, and
    /// lay the result over the frames before it.
    private func runFrame(ratio: Float, holding: Bool) {
        let tail = frameSize - inputWrite
        assembled.update(from: input + inputWrite, count: tail)
        if inputWrite > 0 { (assembled + tail).update(from: input, count: inputWrite) }
        vocoder.analyze(assembled, advance: hop)

        if !hasFirstFrame || wantsFreshPhases {
            vocoder.resetAccumulated(to: vocoder.phase, frequency: vocoder.frequency, hop: Float(hop))
            hasFirstFrame = true
            wantsFreshPhases = false
        }

        if holding, !isHolding {
            // Catch this instant: its levels, its phases, and the frequencies
            // its bins are really carrying, with the synthesis starting from
            // its own phases so the held sound begins as the live one.
            heldMagnitude.update(from: vocoder.magnitude, count: vocoder.bins)
            heldPhase.update(from: vocoder.phase, count: vocoder.bins)
            heldFrequency.update(from: vocoder.frequency, count: vocoder.bins)
            vocoder.findPeaks(in: heldMagnitude)
            vocoder.resetAccumulated(to: heldPhase, frequency: heldFrequency, hop: Float(hop))
            isHolding = true
        } else if !holding, isHolding {
            isHolding = false
            // The live phases drifted from the held ones; start them again
            // from what is really there, so the passthrough is exact.
            wantsFreshPhases = true
            vocoder.resetAccumulated(to: vocoder.phase, frequency: vocoder.frequency, hop: Float(hop))
        }

        if isHolding {
            vocoder.propagate(magnitude: heldMagnitude, phase: heldPhase, frequency: heldFrequency,
                              hop: Float(hop), ratio: 1)
        } else {
            vocoder.findPeaks(in: vocoder.magnitude)
            vocoder.propagate(magnitude: vocoder.magnitude, phase: vocoder.phase,
                              frequency: vocoder.frequency, hop: Float(hop), ratio: ratio)
        }
        vocoder.synthesize()

        let frame = vocoder.frame
        let window = vocoder.window
        for j in 0..<frameSize {
            let position = framePosition + j
            guard position >= 0 else { continue }
            let slot = position & ringMask
            sum[slot] += frame[j]
            weight[slot] += window[j] * window[j]
        }
        framePosition += hop
    }
}

/// The spectral work a pitch shift or a freeze runs on a unit.
///
/// One object serves one kind on one unit, the way the level and the motion
/// do. The settings cross to the audio thread under a lock and are read once
/// per block; the frames in flight, the phases carried between them, and a
/// held instant live on, so a turn of the pitch or the amount changes what is
/// happening rather than starting it over.
final class SpectralEffect: @unchecked Sendable {

    /// Which one, with its settings.
    enum Settings: Hashable, Sendable {
        case pitchShift(PitchShift)
        case freeze(Freeze)

        var kind: Effect.Kind {
            switch self {
            case .pitchShift: return .pitchShift
            case .freeze:     return .freeze
            }
        }
    }

    let kind: Effect.Kind
    let sampleRate: Double
    private let settings: OSAllocatedUnfairLock<Settings>
    private let channels: [SpectralChannel]

    init(_ settings: Settings, sampleRate: Double) {
        kind = settings.kind
        self.sampleRate = max(1000, sampleRate)
        self.settings = OSAllocatedUnfairLock(initialState: settings)
        let frameSize = PhaseVocoder.frameSize(for: sampleRate)
        channels = [SpectralChannel(frameSize: frameSize), SpectralChannel(frameSize: frameSize)]
    }

    /// Whether this object can carry these settings at this rate: the same
    /// kind of work on the same clock.
    func serves(_ settings: Settings, at rate: Double) -> Bool {
        settings.kind == kind && rate == sampleRate
    }

    /// New settings for the work already running.
    func update(_ new: Settings) {
        settings.withLock { $0 = new }
    }

    /// The settings as the audio thread last read them.
    var current: Settings { settings.withLock { $0 } }

    /// How many samples later than it went in the sound comes out: one
    /// frame, about forty milliseconds.
    var latency: Int { channels[0].latency }

    /// Whether a freeze is holding an instant right now.
    var isHolding: Bool { channels[0].isHolding }

    /// Rewrites one block in place.
    func process(_ block: AudioBlock) {
        let held = settings.withLock { $0 }
        let count = block.frameCount
        guard count > 0 else { return }
        let sides = min(block.channelCount, channels.count)
        switch held {
        case .pitchShift(let shift):
            let ratio = Float(shift.ratio)
            let amount = Float(shift.mix)
            for side in 0..<sides {
                channels[side].process(block[side], count: count, ratio: ratio, holding: false, amount: amount)
            }
        case .freeze(let freeze):
            let amount = Float(freeze.amount)
            for side in 0..<sides {
                channels[side].process(block[side], count: count, ratio: 1,
                                       holding: freeze.amount > 0, amount: amount)
            }
        }
    }
}
