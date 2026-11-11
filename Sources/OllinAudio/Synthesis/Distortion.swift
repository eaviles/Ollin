import AVFoundation
import os

// MARK: - Distortion

/// Driving a sound past where it fits.
///
/// The mildest settings are a warm edge on something clean; the strongest stop
/// being a treatment and become the instrument. `mix` is how much of the result
/// is the driven sound rather than the original, so it can be dialed all the
/// way back to nothing.
///
/// ```swift
/// synth.effects = [.distortion(Distortion(.softClip, mix: 0.35))]
/// synth.effects = [.distortion(Distortion(.bitCrush, drive: 6, mix: 1))]
/// ```
///
/// Each character is one piece of arithmetic on the samples, with nothing
/// delayed and nothing left ringing, so a note stops when it stops.
public struct Distortion: Sendable, Hashable, Codable {
    /// The character of the breaking up.
    public enum Character: String, Sendable, Hashable, Codable, CaseIterable {
        /// A gentle rounding of the peaks: warmth rather than damage. The
        /// wave is bent the same way above and below, which adds only odd
        /// harmonics, and full scale stays full scale.
        case softClip
        /// Harder, with the edge of something overdriven. The peaks flatten
        /// rather than round, and one side flattens before the other, which
        /// adds the even harmonics a soft clip leaves out.
        case overdrive
        /// Broken into steps, the sound of too few bits to describe it with.
        /// The level is rounded to a staircase and each step is held for
        /// several samples; more drive is coarser on both counts.
        case bitCrush
        /// A ring rather than a fuzz, which is metallic and unmusical on
        /// purpose. The sound is multiplied by a sine at 300 Hz, so each
        /// tone in it is replaced by two, one that far above and one that
        /// far below.
        case ring
        /// Squeezed through something much too small for it. Only a band
        /// around 1,200 Hz gets through, and it is driven until it
        /// flattens: a pocket radio's speaker.
        case squeeze
    }

    public var character: Character
    /// How hard it is driven in, in decibels, `-80...20`. More is more broken.
    public var drive: Double
    /// How much of the result is the driven sound, `0...1`.
    public var mix: Double

    public init(_ character: Character = .softClip, drive: Double = -6, mix: Double = 0.3) {
        self.character = character
        self.drive = min(max(-80, drive), 20)
        self.mix = min(max(0, mix), 1)
    }

    /// The sine a ring multiplies the sound by, in Hz: on no note of the
    /// scale, so the tones it makes belong to no chord.
    static let ringFrequency = 300.0
    /// The middle of the band a squeeze lets through, in Hz, and how narrow
    /// the band is.
    static let squeezeCenter = 1200.0
    static let squeezeWidth = 0.7
}

// MARK: - The curves

/// The shapes the characters bend a sample through. Free functions over
/// plain numbers, so a test can ask each one what it does.
enum DistortionCurve {

    /// A soft clip: the hyperbolic tangent, scaled so full scale stays full
    /// scale. At a small `gain` it is a straight line.
    @inline(__always)
    static func soft(_ x: Double, gain: Double) -> Double {
        gain < 1e-3 ? x : tanh(gain * x) / tanh(gain)
    }

    /// A harder clip in three pieces: a straight run, a parabola that turns
    /// it over, and a flat top from two thirds on.
    @inline(__always)
    static func hard(_ u: Double) -> Double {
        let size = abs(u)
        let shaped: Double
        if size < 1.0 / 3 {
            shaped = 2 * size
        } else if size < 2.0 / 3 {
            let rest = 2 - 3 * size
            shaped = (3 - rest * rest) / 3
        } else {
            shaped = 1
        }
        return u < 0 ? -shaped : shaped
    }

    /// How far off center the overdrive's curve sits, which is what makes
    /// one side flatten before the other.
    static let overdriveBias = 0.12

    /// The overdrive: the hard clip read off center, scaled so a full-scale
    /// peak on the side that flattens later reaches full scale and no
    /// further. At a small `gain` it is a straight line.
    @inline(__always)
    static func overdrive(_ x: Double, gain: Double) -> Double {
        let bias = overdriveBias
        let rest = hard(bias)
        let reach = rest - hard(bias - gain / 3)
        return reach < 1e-9 ? x : (hard(gain * x / 3 + bias) - rest) / reach
    }

    /// The staircase a bit crush rounds to. Zero is a step, so silence stays
    /// silence.
    @inline(__always)
    static func stepped(_ x: Double, step: Double) -> Double {
        step <= 0 ? x : step * (x / step).rounded()
    }

    /// The gain each character applies before its curve, from the drive in
    /// decibels. At the default drive of -6 dB a soft clip runs at 2, an
    /// overdrive and a squeeze at 4, and a ring at 1, which is the sound at
    /// its own level; every six decibels more doubles it.
    static func gain(_ character: Distortion.Character, drive: Double) -> Double {
        let linear = pow(10, (drive + 6) / 20)
        switch character {
        case .softClip:  return 2 * linear
        case .overdrive: return 4 * linear
        case .squeeze:   return 4 * linear
        case .ring:      return linear
        case .bitCrush:  return 1
        }
    }

    /// The height of one step of the bit crush: a thirty-second of full
    /// scale at the default drive (six bits), and twice that for every six
    /// decibels more.
    static func step(drive: Double) -> Double {
        pow(10, (drive + 6) / 20) / 32
    }

    /// How many times a second the bit crush takes a new sample: 11,025 at
    /// the default drive, and half that for every twelve decibels more.
    static func holdRate(drive: Double) -> Double {
        11025 * pow(10, -(drive + 6) / 40)
    }
}

// MARK: - The work

/// The driving itself, on the unit the other effects of Ollin's own run on.
///
/// One object serves every character, since what each remembers is small:
/// the overdrive's standing level, the bit crush's held sample, the ring's
/// place in its sine, the squeeze's two filters. The settings cross to the
/// audio thread under a lock and are read once per block.
final class DistortionEffect: @unchecked Sendable {

    let sampleRate: Double
    private let settings: OSAllocatedUnfairLock<Distortion>

    /// The overdrive's DC block, each side: its last input and output.
    private var blockInput = (0.0, 0.0)
    private var blockOutput = (0.0, 0.0)
    private let blockPole: Double
    /// The bit crush: how far through the current hold it is, and what each
    /// side is holding.
    private var holdPhase = 1.0
    private var holding = (0.0, 0.0)
    /// The ring's place in its sine, in turns.
    private var ringPhase = 0.0
    /// The squeeze's band, before the clip and after it, each side.
    private var bandIn = (Band(), Band())
    private var bandOut = (Band(), Band())
    private let band: Band.Shape

    init(_ distortion: Distortion, sampleRate: Double) {
        self.sampleRate = max(1000, sampleRate)
        settings = OSAllocatedUnfairLock(initialState: distortion)
        blockPole = exp(-2 * Double.pi * 20 / self.sampleRate)
        band = Band.Shape(center: Distortion.squeezeCenter, width: Distortion.squeezeWidth,
                          sampleRate: self.sampleRate)
    }

    /// Whether this object can carry the driving at this rate. Every
    /// character runs on the same one.
    func serves(at rate: Double) -> Bool { rate == sampleRate }

    /// New settings for the driving already running.
    func update(_ new: Distortion) {
        settings.withLock { $0 = new }
    }

    /// The settings as the audio thread last read them.
    var current: Distortion { settings.withLock { $0 } }

    /// Rewrites one block in place.
    func process(_ block: AudioBlock) {
        let chosen = settings.withLock { $0 }
        let count = block.frameCount
        guard count > 0 else { return }
        let channels = min(block.channelCount, 2)
        let mix = Float(min(max(0, chosen.mix), 1))
        // None of itself is the sound untouched, to the sample.
        guard mix > 0 else { return }
        let drive = min(max(-80, chosen.drive), 20)
        let gain = DistortionCurve.gain(chosen.character, drive: drive)
        let left = block[0]
        let right = block[channels - 1]

        switch chosen.character {
        case .softClip:
            for index in 0..<count {
                for channel in 0..<channels {
                    let samples = channel == 0 ? left : right
                    let x = samples[index]
                    let y = Float(DistortionCurve.soft(Double(x), gain: gain))
                    samples[index] = x * (1 - mix) + y * mix
                }
            }

        case .overdrive:
            for index in 0..<count {
                for channel in 0..<channels {
                    let samples = channel == 0 ? left : right
                    let x = samples[index]
                    let shaped = DistortionCurve.overdrive(Double(x), gain: gain)
                    // One side flattening first leaves a standing level
                    // behind, which is taken back out.
                    let last = channel == 0 ? blockInput.0 : blockInput.1
                    let before = channel == 0 ? blockOutput.0 : blockOutput.1
                    var level = shaped - last + blockPole * before
                    if abs(level) < 1e-20 { level = 0 }
                    if channel == 0 {
                        blockInput.0 = shaped
                        blockOutput.0 = level
                    } else {
                        blockInput.1 = shaped
                        blockOutput.1 = level
                    }
                    samples[index] = x * (1 - mix) + Float(level) * mix
                }
            }

        case .bitCrush:
            let step = DistortionCurve.step(drive: drive)
            let advance = min(1, DistortionCurve.holdRate(drive: drive) / sampleRate)
            for index in 0..<count {
                let takes = holdPhase >= 1
                if takes { holdPhase -= 1 }
                holdPhase += advance
                for channel in 0..<channels {
                    let samples = channel == 0 ? left : right
                    let x = samples[index]
                    if takes {
                        let stepped = DistortionCurve.stepped(Double(x), step: step)
                        if channel == 0 { holding.0 = stepped } else { holding.1 = stepped }
                    }
                    let y = Float(channel == 0 ? holding.0 : holding.1)
                    samples[index] = x * (1 - mix) + y * mix
                }
            }

        case .ring:
            let turn = Distortion.ringFrequency / sampleRate
            for index in 0..<count {
                let carrier = sin(2 * Double.pi * ringPhase)
                for channel in 0..<channels {
                    let samples = channel == 0 ? left : right
                    let x = samples[index]
                    let driven = min(max(gain * Double(x), -1), 1)
                    samples[index] = x * (1 - mix) + Float(driven * carrier) * mix
                }
                ringPhase += turn
                if ringPhase >= 1 { ringPhase -= 1 }
            }

        case .squeeze:
            for index in 0..<count {
                for channel in 0..<channels {
                    let samples = channel == 0 ? left : right
                    let x = samples[index]
                    let y: Double
                    if channel == 0 {
                        let narrow = bandIn.0.next(Double(x), band)
                        y = bandOut.0.next(DistortionCurve.soft(narrow, gain: gain), band)
                    } else {
                        let narrow = bandIn.1.next(Double(x), band)
                        y = bandOut.1.next(DistortionCurve.soft(narrow, gain: gain), band)
                    }
                    samples[index] = x * (1 - mix) + Float(y) * mix
                }
            }
        }
    }

    /// One band-pass filter's memory: a second-order section whose peak
    /// passes at full level.
    struct Band {
        /// The section's numbers, worked out once for a center and a width
        /// at a rate.
        struct Shape {
            let b0: Double
            let a1: Double
            let a2: Double

            init(center: Double, width: Double, sampleRate: Double) {
                let w = 2 * Double.pi * min(center, 0.45 * sampleRate) / sampleRate
                let alpha = sin(w) / (2 * max(0.05, width))
                let a0 = 1 + alpha
                b0 = alpha / a0
                a1 = -2 * cos(w) / a0
                a2 = (1 - alpha) / a0
            }
        }

        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        /// One sample through the band: `b0 (x - x2) - a1 y1 - a2 y2`.
        @inline(__always)
        mutating func next(_ x: Double, _ shape: Shape) -> Double {
            var y = shape.b0 * (x - x2) - shape.a1 * y1 - shape.a2 * y2
            if abs(y) < 1e-20 { y = 0 }
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }
}
