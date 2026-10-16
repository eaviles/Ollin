import AVFoundation
import os

// MARK: - The three that hold a level

/// Holding the loud parts down so the quiet ones can come up.
///
/// Above `threshold` the sound is let through at a fraction of what it does:
/// a `ratio` of 4 means four decibels over the threshold arrive as one. What
/// that buys is not a quieter sound but a narrower one, so raising `makeupGain`
/// afterwards brings the whole thing up with the loud parts still in place.
/// `attack` is how long it takes to clamp down and `release` how long it takes
/// to let go, and the two of them are what a compressor sounds like: a fast
/// attack flattens every transient, and a slow release breathes.
///
/// ```swift
/// synth.effects = [.compressor(Compressor(threshold: -18, ratio: 4, makeupGain: 6))]
/// ```
///
/// The level is read from both sides at once, so a loud note on one side pulls
/// the other down with it and the image stays where it was put.
public struct Compressor: Sendable, Hashable, Codable {
    /// Where it starts working, in decibels below full scale, `-80...0`.
    public var threshold: Double
    /// How much of what is over the threshold gets through, `1...40`. At 1
    /// nothing is held back; at 4, four decibels over arrive as one.
    public var ratio: Double
    /// How long it takes to clamp down, in seconds, `0.0001...1`.
    public var attack: Double
    /// How long it takes to let go, in seconds, `0.005...5`.
    public var release: Double
    /// How wide the bend at the threshold is, in decibels, `0...36`. A knee
    /// of 0 is a corner; a wide one starts working before the threshold and
    /// is what makes a compressor hard to hear working.
    public var knee: Double
    /// Level put back afterwards, in decibels, `0...36`.
    public var makeupGain: Double

    public init(threshold: Double = -18, ratio: Double = 4, attack: Double = 0.01,
                release: Double = 0.15, knee: Double = 6, makeupGain: Double = 0) {
        self.threshold = min(max(-80, threshold), 0)
        self.ratio = min(max(1, ratio), 40)
        self.attack = min(max(0.0001, attack), 1)
        self.release = min(max(0.005, release), 5)
        self.knee = min(max(0, knee), 36)
        self.makeupGain = min(max(0, makeupGain), 36)
    }
}

/// A ceiling nothing gets over.
///
/// The last thing in a chain, where a compressor is a shape and this is a
/// promise: whatever arrives, nothing leaves above `ceiling`. It gets there by
/// listening `Limiter.lookahead` ahead of what it plays, so the level is
/// already down when a peak arrives and comes down smoothly over that time
/// rather than flattening the wave, then letting go over `release`. A single
/// loud note ducks the sound around it for that long rather than tearing, and
/// the sound leaves `lookahead` later than it came in.
///
/// ```swift
/// synth.effects = [.distortion(Distortion(.softClip)), .limiter(Limiter())]
/// ```
public struct Limiter: Sendable, Hashable, Codable {
    /// The loudest anything may leave at, in decibels below full scale,
    /// `-40...0`. A little under zero leaves room for what a file's own
    /// conversion adds.
    public var ceiling: Double
    /// How long it takes to let go after a peak, in seconds, `0.005...5`.
    public var release: Double

    public init(ceiling: Double = -0.5, release: Double = 0.05) {
        self.ceiling = min(max(-40, ceiling), 0)
        self.release = min(max(0.005, release), 5)
    }

    /// How far ahead the limiter listens, in seconds, which is also how much
    /// later the sound leaves it: long enough to bring the level down over a
    /// whole cycle of a low note's wave, short enough not to be heard as late.
    public static let lookahead = 0.005
}

/// Silence between the notes.
///
/// Below `threshold` the sound is turned down by `depth`, which takes the hiss,
/// the hum, and the room out of the gaps without touching anything loud enough
/// to be the point. `hold` is how long it stays open after the level drops,
/// which is what keeps a decaying note from being chopped off, and `release`
/// is how long the closing takes.
///
/// ```swift
/// synth.effects = [.gate(Gate(threshold: -40, hold: 0.08))]
/// ```
public struct Gate: Sendable, Hashable, Codable {
    /// The level it opens at, in decibels below full scale, `-100...0`.
    public var threshold: Double
    /// How long the opening takes, in seconds, `0.0001...1`.
    public var attack: Double
    /// How long it stays open after the level drops, in seconds, `0...5`.
    public var hold: Double
    /// How long the closing takes, in seconds, `0.005...5`.
    public var release: Double
    /// How far down it closes, `0...1`. At 1 the gaps are silent; less
    /// leaves the room in, quieter.
    public var depth: Double

    public init(threshold: Double = -45, attack: Double = 0.002, hold: Double = 0.05,
                release: Double = 0.12, depth: Double = 1) {
        self.threshold = min(max(-100, threshold), 0)
        self.attack = min(max(0.0001, attack), 1)
        self.hold = min(max(0, hold), 5)
        self.release = min(max(0.005, release), 5)
        self.depth = min(max(0, depth), 1)
    }
}

// MARK: - The work

/// The level itself: what reads the sound's loudness and what it does about it.
///
/// One object serves one kind on one unit. The settings cross to the audio
/// thread under a lock and are read once per block; the follower's own level
/// and the gain it has reached live on, so a turn of any setting changes what
/// is happening rather than starting it over.
///
/// The compressor is the feed-forward design worked out in decibels: the level
/// is followed from crest to crest, the curve says what that loudness should
/// leave as, and the difference between them is what gets smoothed by the
/// attack and the release before it is applied. Smoothing the *reduction* rather than the level is what keeps
/// the attack honest across every input level, and doing it in decibels is
/// what makes the times mean what they say.
final class DynamicsEffect: @unchecked Sendable {

    /// Which one, with its settings.
    enum Settings: Hashable, Sendable {
        case compressor(Compressor)
        case limiter(Limiter)
        case gate(Gate)

        var kind: Effect.Kind {
            switch self {
            case .compressor: return .compressor
            case .limiter:    return .limiter
            case .gate:       return .gate
            }
        }
    }

    let kind: Effect.Kind
    let sampleRate: Double
    private let settings: OSAllocatedUnfairLock<Settings>

    /// The gain reduction the compressor has reached, in decibels.
    private var reduction = 0.0
    /// The gain the limiter and the gate have reached, as a multiplier.
    private var gain = 1.0
    /// The follower's own level, as a multiplier, and how long the gate has
    /// been held open since the level last dropped, in samples.
    private var level = 0.0
    private var heldFor = 0

    /// The limiter's lookahead, in samples, and what it keeps for it: the
    /// sound waiting to leave (two channels), the gain each of the waiting
    /// samples asks for with the release laid over it, and the running sum
    /// of those gains. Memory the object owns, since it is written from the
    /// audio thread. Empty for the other two kinds.
    private let ahead: Int
    private let waiting: UnsafeMutablePointer<Double>
    private let asked: UnsafeMutablePointer<Double>
    /// The smallest gain asked for over the window, as a queue of sample
    /// positions whose gains rise from front to back (the oldest that could
    /// still be the smallest at the front).
    private let smallest: UnsafeMutablePointer<Int>
    private let needs: UnsafeMutablePointer<Double>
    private var smallestFront = 0
    private var smallestCount = 0
    private var position = 0
    private var askedSum = 0.0
    private var released = 1.0

    init(_ settings: Settings, sampleRate: Double) {
        self.kind = settings.kind
        self.sampleRate = max(1000, sampleRate)
        self.settings = OSAllocatedUnfairLock(initialState: settings)
        let window = settings.kind == .limiter ? max(1, Int((Limiter.lookahead * self.sampleRate).rounded())) : 0
        ahead = window
        waiting = .allocate(capacity: 2 * (window + 1))
        waiting.initialize(repeating: 0, count: 2 * (window + 1))
        asked = .allocate(capacity: window + 1)
        asked.initialize(repeating: 1, count: window + 1)
        needs = .allocate(capacity: window + 1)
        needs.initialize(repeating: 1, count: window + 1)
        smallest = .allocate(capacity: window + 1)
        smallest.initialize(repeating: 0, count: window + 1)
        askedSum = Double(window + 1)
    }

    deinit {
        waiting.deallocate()
        asked.deallocate()
        needs.deallocate()
        smallest.deallocate()
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

    /// How much the level is being held down right now, in decibels, which is
    /// what a meter would show.
    var gainReduction: Double {
        switch kind {
        case .compressor: return reduction
        default:          return -20 * log10(max(gain, 1e-9))
        }
    }

    // MARK: Running

    /// The time constant of a one-pole follower that reaches most of the way
    /// in `seconds`.
    private func coefficient(_ seconds: Double) -> Double {
        exp(-1 / (max(seconds, 1e-6) * sampleRate))
    }

    /// Rewrites one block in place.
    func process(_ block: AudioBlock) {
        let held = settings.withLock { $0 }
        let count = block.frameCount
        guard count > 0 else { return }
        let channels = min(block.channelCount, 2)

        switch held {
        case .compressor(let compressor):
            let attack = coefficient(compressor.attack)
            let release = coefficient(compressor.release)
            // The level is followed from crest to crest rather than read off
            // each sample, so the reduction follows the note and not the wave
            // inside it. Without it a tone lands short of where its ratio says
            // it should, since the reduction eases every time the wave passes
            // through nothing on its way to the other side.
            let follow = coefficient(0.01)
            let threshold = compressor.threshold
            let slope = 1 / compressor.ratio - 1
            let knee = compressor.knee
            let makeupGain = compressor.makeupGain
            for index in 0..<count {
                var peak = 0.0
                for channel in 0..<channels { peak = max(peak, abs(Double(block[channel][index]))) }
                level = peak > level ? peak : follow * level + (1 - follow) * peak
                let loudness = 20 * log10(max(level, 1e-9))
                // The curve, with the knee as the quadratic that joins the two
                // straight parts smoothly across a band `knee` wide.
                let over = loudness - threshold
                var wanted: Double
                if knee > 0 && abs(2 * over) <= knee {
                    wanted = -slope * (over + knee / 2) * (over + knee / 2) / (2 * knee)
                } else if over > 0 {
                    wanted = -slope * over
                } else {
                    wanted = 0
                }
                // Attack while the reduction is growing, release while it eases.
                let coefficient = wanted > reduction ? attack : release
                reduction = coefficient * reduction + (1 - coefficient) * wanted
                let applied = Float(pow(10, (makeupGain - reduction) / 20))
                for channel in 0..<channels { block[channel][index] *= applied }
            }

        case .limiter(let limiter):
            // A lookahead limiter. The sample leaving now came in `ahead`
            // samples ago. Each gain below is the smallest any of the last
            // `ahead + 1` samples asks for (ceiling over its peak), with the
            // release laid over it so it lets go slowly; what is applied is
            // the mean of the last `ahead + 1` of those. Every one of them saw
            // the leaving sample in its window, so none is above what it
            // needs, and so neither is their mean: the ceiling holds exactly, and the gain
            // comes down along a straight line over the lookahead instead of
            // in one sample, which is what keeps a crest round.
            let release = coefficient(limiter.release)
            let ceiling = pow(10, limiter.ceiling / 20)
            let span = ahead + 1
            for index in 0..<count {
                var peak = 0.0
                for channel in 0..<channels { peak = max(peak, abs(Double(block[channel][index]))) }
                let needed = peak > ceiling ? ceiling / peak : 1
                let slot = position % span
                // The window's smallest need: drop the positions that left
                // it, and the ones this sample's need is no larger than.
                needs[slot] = needed
                if smallestCount > 0, smallest[smallestFront] <= position - span {
                    smallestFront = (smallestFront + 1) % span
                    smallestCount -= 1
                }
                while smallestCount > 0 {
                    let back = smallest[(smallestFront + smallestCount - 1) % span]
                    guard needs[back % span] >= needed else { break }
                    smallestCount -= 1
                }
                smallest[(smallestFront + smallestCount) % span] = position
                smallestCount += 1
                let windowLeast = needs[smallest[smallestFront] % span]
                released = min(windowLeast, release * released + (1 - release))
                askedSum += released - asked[slot]
                asked[slot] = released
                gain = min(1, askedSum / Double(span))
                // In comes this sample, and out goes the one that came in
                // `ahead` samples ago, which sits in the next slot round.
                let applied = Float(gain)
                let leaving = (position + 1) % span
                for channel in 0..<channels {
                    waiting[2 * slot + channel] = Double(block[channel][index])
                    block[channel][index] = Float(waiting[2 * leaving + channel]) * applied
                }
                position += 1
            }

        case .gate(let gate):
            let attack = coefficient(gate.attack)
            let release = coefficient(gate.release)
            // The level is followed quickly enough to catch the start of a note
            // and slowly enough that it does not chatter inside one.
            let follow = coefficient(0.001)
            let opening = pow(10, gate.threshold / 20)
            let hold = Int(gate.hold * sampleRate)
            let floor = 1 - gate.depth
            for index in 0..<count {
                var peak = 0.0
                for channel in 0..<channels { peak = max(peak, abs(Double(block[channel][index]))) }
                level = peak > level ? peak : follow * level + (1 - follow) * peak
                if level >= opening {
                    heldFor = hold
                } else if heldFor > 0 {
                    heldFor -= 1
                }
                let wanted = (level >= opening || heldFor > 0) ? 1.0 : floor
                let coefficient = wanted > gain ? attack : release
                gain = coefficient * gain + (1 - coefficient) * wanted
                let applied = Float(gain)
                for channel in 0..<channels { block[channel][index] *= applied }
            }
        }
    }
}
