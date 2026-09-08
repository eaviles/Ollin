import AVFoundation
import os

// MARK: - The four that move

/// A copy of the sound, sliding a little later and a little earlier.
///
/// The copy sits about twenty milliseconds behind, and a slow wave moves it
/// back and forth, so it is never quite in tune with the original. Two
/// voices that can never agree read as several, which is where the name
/// comes from. The two sides of the sound are moved a quarter turn apart,
/// so the effect is wide by itself.
///
/// ```swift
/// synth.effects = [.chorus(Chorus(rate: 0.8, depth: 0.5))]
/// ```
public struct Chorus: Sendable, Hashable, Codable {
    /// How many times a second the copy slides back and forth, in Hz.
    public var rate: Double
    /// How far it slides, `0...1`. At 1 the copy moves six milliseconds
    /// either side of where it sits.
    public var depth: Double
    /// How much of the result is the copy rather than the sound, `0...1`.
    /// Half is the classic.
    public var mix: Double

    public init(rate: Double = 0.8, depth: Double = 0.5, mix: Double = 0.5) {
        self.rate = min(max(0.01, rate), 20)
        self.depth = min(max(0, depth), 1)
        self.mix = min(max(0, mix), 1)
    }
}

/// The sound and a copy of it a hair apart, the gap sweeping.
///
/// A copy less than ten milliseconds behind does not read as a second voice
/// but as a comb of notches cut through the spectrum, one every so many Hz.
/// Sweeping the gap sweeps the comb, the jet-plane whoosh every record has
/// used. Feeding the copy back into itself sharpens the teeth; a negative
/// feedback hollows the sound instead.
///
/// ```swift
/// synth.effects = [.flanger(Flanger(rate: 0.25, depth: 0.7, feedback: 0.5))]
/// ```
public struct Flanger: Sendable, Hashable, Codable {
    /// How many times a second the gap sweeps out and back, in Hz.
    public var rate: Double
    /// How far the gap opens, `0...1`. At 1 it sweeps from one millisecond
    /// to seven.
    public var depth: Double
    /// How much of the copy goes back in to be copied again, `-0.95...0.95`.
    /// Positive sharpens the comb, negative turns it inside out.
    public var feedback: Double
    /// How much of the result is the copy rather than the sound, `0...1`.
    public var mix: Double

    public init(rate: Double = 0.25, depth: Double = 0.7, feedback: Double = 0.5,
                mix: Double = 0.5) {
        self.rate = min(max(0.01, rate), 20)
        self.depth = min(max(0, depth), 1)
        self.feedback = min(max(-0.95, feedback), 0.95)
        self.mix = min(max(0, mix), 1)
    }
}

/// A few notches swept up and down the spectrum.
///
/// The sound goes through a row of stages that each turn its phase without
/// touching its level; added back to the original, the turned parts cancel
/// at a few frequencies, one notch for every two stages. A slow wave moves
/// the row up and down the spectrum, so the notches sweep. Fewer notches
/// than a flanger, and wider apart, which is the softer swirl.
///
/// ```swift
/// synth.effects = [.phaser(Phaser(rate: 0.4, stages: 4))]
/// ```
public struct Phaser: Sendable, Hashable, Codable {
    /// How many times a second the notches sweep up and back, in Hz.
    public var rate: Double
    /// How far up the spectrum they sweep, `0...1`. At 1 the sweep runs from
    /// two hundred hertz to four thousand; at 0 the notches stand still at
    /// the bottom of that range.
    public var depth: Double
    /// How many stages, `1...12`. Two stages make one notch, so four make
    /// two, which is the usual count.
    public var stages: Int
    /// How much of the result goes back through the stages, `-0.95...0.95`.
    /// More makes the peaks between the notches ring.
    public var feedback: Double
    /// How much of the result is the turned sound rather than the plain one,
    /// `0...1`. Half cuts the deepest notches.
    public var mix: Double

    public init(rate: Double = 0.4, depth: Double = 1, stages: Int = 4,
                feedback: Double = 0.3, mix: Double = 0.5) {
        self.rate = min(max(0.01, rate), 20)
        self.depth = min(max(0, depth), 1)
        self.stages = min(max(1, stages), 12)
        self.feedback = min(max(-0.95, feedback), 0.95)
        self.mix = min(max(0, mix), 1)
    }
}

/// The level breathing.
///
/// The loudness rises and falls with a slow wave, from full down to
/// `1 - depth` and back. Nothing else changes, which is what makes it the
/// plainest of the four and the one a guitar amplifier had a knob for.
/// `spread` moves the two sides apart in time: at 1 they breathe in
/// opposite turns, and the sound swings from one side to the other.
///
/// ```swift
/// synth.effects = [.tremolo(Tremolo(rate: 5, depth: 0.6))]
/// ```
public struct Tremolo: Sendable, Hashable, Codable {
    /// How many times a second the level breathes, in Hz.
    public var rate: Double
    /// How far it dips, `0...1`. At 1 it falls to silence at the bottom of
    /// every breath.
    public var depth: Double
    /// How far apart the two sides breathe, `0...1`: together at 0, in
    /// opposite turns at 1, which swings the sound from side to side.
    public var spread: Double

    public init(rate: Double = 5, depth: Double = 0.6, spread: Double = 0) {
        self.rate = min(max(0.01, rate), 40)
        self.depth = min(max(0, depth), 1)
        self.spread = min(max(0, spread), 1)
    }
}

// MARK: - The work

/// The motion itself: one slow wave, and what it moves.
///
/// One object serves one kind of motion on one unit. The settings cross to
/// the audio thread under a lock and are read once per block; the wave's
/// phase, the delay lines, and the stages' memories live on, so a turn of
/// any setting changes the motion in flight rather than starting it over.
final class ModulationEffect: @unchecked Sendable {

    /// Which motion, with its settings.
    enum Settings: Hashable, Sendable {
        case chorus(Chorus)
        case flanger(Flanger)
        case phaser(Phaser)
        case tremolo(Tremolo)

        var kind: Effect.Kind {
            switch self {
            case .chorus:  return .chorus
            case .flanger: return .flanger
            case .phaser:  return .phaser
            case .tremolo: return .tremolo
            }
        }
    }

    let kind: Effect.Kind
    let sampleRate: Double
    private let settings: OSAllocatedUnfairLock<Settings>

    /// The longest delay any of the motions asks for, with room for the
    /// interpolation to read one sample past it.
    private static let maxDelaySeconds = 0.03
    private var lines: [[Float]]
    private var lineLength: Int
    private var writeIndex = 0
    /// The wave's phase, in turns.
    private var phase = 0.0
    /// Each channel's stages: the previous input and output of each.
    private var stageInputs: [[Float]]
    private var stageOutputs: [[Float]]
    /// The last wet sample of each channel, for the feedback.
    private var lastWet: [Float] = [0, 0]

    init(_ settings: Settings, sampleRate: Double) {
        self.kind = settings.kind
        self.sampleRate = max(1000, sampleRate)
        self.settings = OSAllocatedUnfairLock(initialState: settings)
        let length = Int(ModulationEffect.maxDelaySeconds * self.sampleRate) + 4
        lineLength = length
        lines = [[Float](repeating: 0, count: length), [Float](repeating: 0, count: length)]
        stageInputs = [[Float](repeating: 0, count: 12), [Float](repeating: 0, count: 12)]
        stageOutputs = [[Float](repeating: 0, count: 12), [Float](repeating: 0, count: 12)]
    }

    /// Whether this object can carry these settings at this rate: the same
    /// kind of motion on the same clock.
    func serves(_ settings: Settings, at rate: Double) -> Bool {
        settings.kind == kind && rate == sampleRate
    }

    /// New settings for the motion already running.
    func update(_ new: Settings) {
        settings.withLock { $0 = new }
    }

    /// The settings as the audio thread last read them.
    var current: Settings { settings.withLock { $0 } }

    // MARK: Running

    /// Rewrites one block in place.
    func process(_ block: AudioBlock) {
        let held = settings.withLock { $0 }
        let count = block.frameCount
        guard count > 0 else { return }
        let channels = min(block.channelCount, 2)
        let rate = Float(sampleRate)
        switch held {
        case .chorus(let chorus):
            let step = chorus.rate / sampleRate
            let base = Float(0.020) * rate
            let swing = Float(chorus.depth) * Float(0.006) * rate
            let mix = Float(chorus.mix)
            for index in 0..<count {
                for channel in 0..<channels {
                    let samples = block[channel]
                    let wave = Float(sin(2 * .pi * (phase + (channel == 1 ? 0.25 : 0))))
                    let x = samples[index]
                    let wet = read(channel, delay: base + swing * wave)
                    lines[channel][writeIndex] = x
                    samples[index] = x * (1 - mix) + wet * mix
                }
                advance(step)
            }
        case .flanger(let flanger):
            let step = flanger.rate / sampleRate
            let base = Float(0.001) * rate
            let swing = Float(flanger.depth) * Float(0.006) * rate
            let feedback = Float(flanger.feedback)
            let mix = Float(flanger.mix)
            for index in 0..<count {
                let wave = Float(sin(2 * .pi * phase))
                let delay = base + swing * (0.5 + 0.5 * wave)
                for channel in 0..<channels {
                    let samples = block[channel]
                    let x = samples[index]
                    let wet = read(channel, delay: delay)
                    lines[channel][writeIndex] = x + feedback * wet
                    samples[index] = x * (1 - mix) + wet * mix
                }
                advance(step)
            }
        case .phaser(let phaser):
            let step = phaser.rate / sampleRate
            let stages = phaser.stages
            let feedback = Float(phaser.feedback)
            let mix = Float(phaser.mix)
            let depth = phaser.depth
            let ceiling = 0.45 * sampleRate
            for index in 0..<count {
                let wave = sin(2 * .pi * phase)
                // The stages' corner sweeps from two hundred hertz up by as
                // much as a factor of twenty, along a logarithmic path so
                // the motion reads even across the octaves.
                let corner = min(200 * pow(20, depth * (0.5 + 0.5 * wave)), ceiling)
                let warped = tan(.pi * corner / sampleRate)
                let a = Float((warped - 1) / (warped + 1))
                for channel in 0..<channels {
                    let samples = block[channel]
                    let x = samples[index]
                    var signal = x + feedback * lastWet[channel]
                    for stage in 0..<stages {
                        let y = a * signal + stageInputs[channel][stage] - a * stageOutputs[channel][stage]
                        stageInputs[channel][stage] = signal
                        stageOutputs[channel][stage] = y
                        signal = y
                    }
                    lastWet[channel] = signal
                    samples[index] = x * (1 - mix) + signal * mix
                }
                advance(step)
            }
        case .tremolo(let tremolo):
            let step = tremolo.rate / sampleRate
            let depth = tremolo.depth
            let offset = tremolo.spread * 0.5
            for index in 0..<count {
                for channel in 0..<channels {
                    let samples = block[channel]
                    let wave = sin(2 * .pi * (phase + (channel == 1 ? offset : 0)))
                    let gain = Float(1 - depth * (0.5 - 0.5 * wave))
                    samples[index] *= gain
                }
                advance(step)
            }
        }
    }

    /// The delay line read `delay` samples behind the write position, with
    /// the fraction between two samples interpolated.
    @inline(__always)
    private func read(_ channel: Int, delay: Float) -> Float {
        let clamped = min(max(delay, 1), Float(lineLength - 2))
        let whole = Int(clamped)
        let fraction = clamped - Float(whole)
        var first = writeIndex - whole
        if first < 0 { first += lineLength }
        var second = first - 1
        if second < 0 { second += lineLength }
        let line = lines[channel]
        return line[first] * (1 - fraction) + line[second] * fraction
    }

    /// One sample on: the write position and the wave's phase.
    @inline(__always)
    private func advance(_ step: Double) {
        writeIndex += 1
        if writeIndex == lineLength { writeIndex = 0 }
        phase += step
        if phase >= 1 { phase -= 1 }
    }
}
