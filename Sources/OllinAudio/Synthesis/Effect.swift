import AVFoundation

/// One thing done to the sound after it is made.
///
/// The voice side of this library is routing as a value: a ``Patch`` says what
/// an instrument is made of and how the pieces are wired. This is the same idea
/// on the way out. A `Synth` holds an ordered chain of these rather than a
/// fixed pair of slots, so an instrument is finished rather than merely
/// decorated.
///
/// ```swift
/// synth.effects = [
///     .distortion(Distortion(.softClip, mix: 0.3)),
///     .delay(Delay(time: 0.28, feedback: 0.5)),
///     .reverb(Reverb(.hall, mix: 0.4)),
/// ]
/// ```
///
/// **Order is the point.** An echo of a distorted sound and a distorted echo
/// are different, and so are a reverb of an echo and an echo of a reverb: the
/// first repeats a room and the second puts repeats in one. Writing the chain
/// down as a list is how that becomes something you can say.
public enum Effect: Sendable, Hashable, Codable {
    /// The sound again, later and quieter each time.
    case delay(Delay)
    /// A room around it.
    case reverb(Reverb)
    /// Lifting or cutting part of the spectrum.
    case equalizer(Equalizer)
    /// Driving it past where it fits, from a warm edge to a broken one.
    case distortion(Distortion)
    /// A copy of the sound sliding a little later and earlier, so it reads as
    /// several voices. See ``Chorus``.
    case chorus(Chorus)
    /// The sound and a copy a hair apart, the gap sweeping a comb of notches
    /// through it. See ``Flanger``.
    case flanger(Flanger)
    /// A few notches swept up and down the spectrum. See ``Phaser``.
    case phaser(Phaser)
    /// The level breathing. See ``Tremolo``.
    case tremolo(Tremolo)
    /// Holding the loud parts down so the quiet ones can come up. See
    /// ``Compressor``.
    case compressor(Compressor)
    /// A ceiling nothing gets over. See ``Limiter``.
    case limiter(Limiter)
    /// Silence between the notes. See ``Gate``.
    case gate(Gate)
    /// One you wrote yourself: a closure over the samples. See ``CustomEffect``.
    case custom(CustomEffect)

    /// Which kind of effect this is, ignoring its settings.
    ///
    /// What the chain is rebuilt against: two chains of the same kinds in the
    /// same order are the same wiring, whatever their settings say, so changing
    /// a setting never disturbs the graph. The one setting that is a kind of
    /// its own is a reverb's room: a ``Reverb`` carrying an ``ImpulseResponse``
    /// runs on its own unit, so it reads as `.convolution` here.
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case delay, reverb, equalizer, distortion, chorus, flanger, phaser, tremolo
        case compressor, limiter, gate, custom
        /// A reverb of a recorded or drawn room, `Reverb(impulse)`.
        case convolution
    }

    public var kind: Kind {
        switch self {
        case .delay:      return .delay
        case .reverb(let reverb):
            return reverb.impulse == nil ? .reverb : .convolution
        case .equalizer:  return .equalizer
        case .distortion: return .distortion
        case .chorus:     return .chorus
        case .flanger:    return .flanger
        case .phaser:     return .phaser
        case .tremolo:    return .tremolo
        case .compressor: return .compressor
        case .limiter:    return .limiter
        case .gate:       return .gate
        case .custom:     return .custom
        }
    }

    /// The motion this effect is, for the unit that carries one, or nil for
    /// an effect that does not move.
    var motion: ModulationEffect.Settings? {
        switch self {
        case .chorus(let chorus):   return .chorus(chorus)
        case .flanger(let flanger): return .flanger(flanger)
        case .phaser(let phaser):   return .phaser(phaser)
        case .tremolo(let tremolo): return .tremolo(tremolo)
        default:                    return nil
        }
    }

    /// The level work this effect is, for the unit that carries one, or nil
    /// for an effect that leaves the level alone.
    var dynamics: DynamicsEffect.Settings? {
        switch self {
        case .compressor(let compressor): return .compressor(compressor)
        case .limiter(let limiter):       return .limiter(limiter)
        case .gate(let gate):             return .gate(gate)
        default:                          return nil
        }
    }

    /// A unit that can do this kind of work. The settings are applied
    /// separately, so one unit serves every setting of its kind. For a custom
    /// effect the closure itself is the setting, which is what lets a sketch
    /// swap the work without the chain being rewired; a convolution reverb
    /// and the four motions ride the same unit, each prepared and swapped in
    /// the same way.
    static func makeUnit(for kind: Kind) -> AVAudioUnit {
        switch kind {
        case .delay:       return AVAudioUnitDelay()
        case .reverb:      return AVAudioUnitReverb()
        case .equalizer:   return AVAudioUnitEQ(numberOfBands: 3)
        case .distortion:  return AVAudioUnitDistortion()
        case .chorus, .flanger, .phaser, .tremolo:
            return ClosureAudioUnit.makeUnit()
        case .compressor, .limiter, .gate:
            return ClosureAudioUnit.makeUnit()
        case .custom:      return ClosureAudioUnit.makeUnit()
        case .convolution: return ClosureAudioUnit.makeUnit()
        }
    }

    /// Puts this effect's settings onto a unit of its kind. `sampleRate` is
    /// the rate the chain runs at, which a room has to be prepared for.
    func apply(to unit: AVAudioUnit, sampleRate: Double) {
        switch self {
        case .delay(let delay):
            guard let unit = unit as? AVAudioUnitDelay else { return }
            Synth.configure(unit, with: delay)
        case .reverb(let reverb):
            if let unit = unit as? AVAudioUnitReverb {
                Synth.configure(unit, with: reverb)
            } else if let closureUnit = unit.auAudioUnit as? ClosureAudioUnit,
                      let impulse = reverb.impulse {
                closureUnit.setRoom(reverb, impulse: impulse, sampleRate: sampleRate)
            }
        case .equalizer(let equalizer):
            guard let unit = unit as? AVAudioUnitEQ else { return }
            equalizer.apply(to: unit)
        case .distortion(let distortion):
            guard let unit = unit as? AVAudioUnitDistortion else { return }
            distortion.apply(to: unit)
        case .chorus, .flanger, .phaser, .tremolo:
            guard let closureUnit = unit.auAudioUnit as? ClosureAudioUnit,
                  let motion else { return }
            closureUnit.setMotion(motion, sampleRate: sampleRate)
        case .compressor, .limiter, .gate:
            guard let closureUnit = unit.auAudioUnit as? ClosureAudioUnit,
                  let dynamics else { return }
            closureUnit.setDynamics(dynamics, sampleRate: sampleRate)
        case .custom(let custom):
            guard let closureUnit = unit.auAudioUnit as? ClosureAudioUnit else { return }
            closureUnit.slot.set(custom.runner)
        }
    }

    /// An effect you wrote yourself, in place: the closure is handed each
    /// ``AudioBlock`` on its way out and rewrites the samples.
    public static func custom(
        _ name: String = "effect",
        _ process: @escaping @Sendable (AudioBlock) -> Void
    ) -> Effect {
        .custom(CustomEffect(name, process))
    }

    /// An effect of your own that remembers something between blocks; the
    /// memory goes in as `state:` and comes back `inout` every time.
    public static func custom<State: Sendable>(
        _ name: String = "effect", state: State,
        _ process: @escaping @Sendable (AudioBlock, inout State) -> Void
    ) -> Effect {
        .custom(CustomEffect(name, state: state, process))
    }
}

// MARK: - Equalizer

/// Lifting or cutting parts of the spectrum.
///
/// Three controls, which is what most sounds need: the bottom, the top, and one
/// place in the middle you can put wherever the problem is.
///
/// ```swift
/// synth.effects = [.equalizer(Equalizer(lowGain: -6, highGain: 3))]
/// ```
///
/// Gains are in decibels, so zero is untouched, positive lifts and negative
/// cuts. A few decibels is a great deal more than it sounds like written down.
public struct Equalizer: Sendable, Hashable, Codable {
    /// How much to lift or cut everything below `lowEdge`, in decibels.
    public var lowGain: Double
    /// Where the bottom shelf turns over, in Hz.
    public var lowEdge: Double
    /// How much to lift or cut around `midFrequency`, in decibels.
    public var midGain: Double
    /// Where the middle band sits, in Hz.
    public var midFrequency: Double
    /// How narrow that middle band is. Higher is narrower: around 1 is a broad
    /// tilt and past 5 is a notch aimed at one thing.
    public var midWidth: Double
    /// How much to lift or cut everything above `highEdge`, in decibels.
    public var highGain: Double
    /// Where the top shelf turns over, in Hz.
    public var highEdge: Double

    public init(
        lowGain: Double = 0, lowEdge: Double = 200,
        midGain: Double = 0, midFrequency: Double = 1000, midWidth: Double = 1,
        highGain: Double = 0, highEdge: Double = 4000
    ) {
        self.lowGain = min(max(-24, lowGain), 24)
        self.lowEdge = min(max(20, lowEdge), 20000)
        self.midGain = min(max(-24, midGain), 24)
        self.midFrequency = min(max(20, midFrequency), 20000)
        self.midWidth = min(max(0.05, midWidth), 20)
        self.highGain = min(max(-24, highGain), 24)
        self.highEdge = min(max(20, highEdge), 20000)
    }

    /// Everything under the edge, and nothing else. The one to reach for when
    /// a sound is muddy rather than wrong.
    public static func lowCut(below edge: Double, by decibels: Double = -12) -> Equalizer {
        Equalizer(lowGain: decibels, lowEdge: edge)
    }

    /// Warm: a lift at the bottom and a little off the top.
    public static let warm = Equalizer(lowGain: 4, lowEdge: 250, highGain: -3, highEdge: 5000)

    /// The opposite: thinner and more present.
    public static let bright = Equalizer(lowGain: -5, lowEdge: 300, highGain: 5, highEdge: 3500)

    /// A hole in the middle, which is how a sound makes room for another.
    public static let scooped = Equalizer(midGain: -9, midFrequency: 900, midWidth: 1.2)

    func apply(to unit: AVAudioUnitEQ) {
        guard unit.bands.count >= 3 else { return }
        unit.bands[0].filterType = .lowShelf
        unit.bands[0].frequency = Float(lowEdge)
        unit.bands[0].gain = Float(lowGain)
        unit.bands[0].bypass = lowGain == 0

        unit.bands[1].filterType = .parametric
        unit.bands[1].frequency = Float(midFrequency)
        unit.bands[1].bandwidth = Float(1 / max(0.05, midWidth))
        unit.bands[1].gain = Float(midGain)
        unit.bands[1].bypass = midGain == 0

        unit.bands[2].filterType = .highShelf
        unit.bands[2].frequency = Float(highEdge)
        unit.bands[2].gain = Float(highGain)
        unit.bands[2].bypass = highGain == 0

        unit.globalGain = 0
        unit.bypass = lowGain == 0 && midGain == 0 && highGain == 0
    }
}

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
/// ```
public struct Distortion: Sendable, Hashable, Codable {
    /// The character of the breaking up.
    public enum Character: String, Sendable, Hashable, Codable, CaseIterable {
        /// A gentle rounding of the peaks: warmth rather than damage.
        case softClip
        /// Harder, with the edge of something overdriven.
        case overdrive
        /// Broken into steps, the sound of too few bits to describe it with.
        case bitCrush
        /// A ring rather than a fuzz, which is metallic and unmusical on
        /// purpose.
        case ring
        /// Squeezed through something much too small for it.
        case squeeze

        var preset: AVAudioUnitDistortionPreset {
            switch self {
            case .softClip:  return .multiEcho1
            case .overdrive: return .drumsBitBrush
            case .bitCrush:  return .speechRadioTower
            case .ring:      return .multiCellphoneConcert
            case .squeeze:   return .speechCosmicInterference
            }
        }
    }

    public var character: Character
    /// How hard it is driven in, in decibels. More is more broken.
    public var drive: Double
    /// How much of the result is the driven sound, `0...1`.
    public var mix: Double

    public init(_ character: Character = .softClip, drive: Double = -6, mix: Double = 0.3) {
        self.character = character
        self.drive = min(max(-80, drive), 20)
        self.mix = min(max(0, mix), 1)
    }

    func apply(to unit: AVAudioUnitDistortion) {
        unit.loadFactoryPreset(character.preset)
        unit.preGain = Float(drive)
        unit.wetDryMix = Float(mix * 100)
    }
}
