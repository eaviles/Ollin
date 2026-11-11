import AVFoundation
import os

// MARK: - An echo

/// An echo: the sound again, later and quieter each time.
///
/// The sound goes into a line, comes out `time` seconds later, and a share of
/// what comes out goes back in, so one note is heard again and again, each
/// repeat quieter and a little duller than the last.
///
/// ```swift
/// synth.delay = Delay(time: 0.28, feedback: 0.5)
/// synth.delay = Delay(time: 8, feedback: 0.9, mix: 0.5)     // a phrase, coming round
/// ```
///
/// A short `time` is an echo. A long one with a high `feedback` is a loop:
/// what is played comes round again `time` seconds later under whatever is
/// played next, fading a little on each pass.
public struct Delay: Sendable, Hashable, Codable {
    /// Seconds before the first repeat, `0...60`. The repeat lands on the
    /// sample that time names. Sixty seconds is the longest the echo can
    /// wait, ``maxTime``, so a longer time is held there.
    public var time: Double
    /// How much of each repeat feeds the next, `0...0.95`. Higher runs longer.
    public var feedback: Double
    /// How much of the result is the echo rather than the sound itself, `0...1`.
    public var mix: Double
    /// Where the repeats start losing their top end, in Hz. Lower makes each
    /// repeat duller than the last, the way a real one is. At 20,000 and
    /// above nothing is taken, and every repeat is the sound as it went in.
    public var damping: Double

    public init(time: Double = 0.25, feedback: Double = 0.4, mix: Double = 0.3, damping: Double = 6000) {
        self.time = min(max(0, time), Delay.maxTime)
        self.feedback = min(max(0, feedback), 0.95)
        self.mix = min(max(0, mix), 1)
        self.damping = damping
    }

    /// The longest `time` the echo can wait, in seconds.
    public static let maxTime = 60.0

    /// The damping at and above which the repeats lose nothing, in Hz.
    static let openAbove = 20000.0
}

// MARK: - The work

/// The echo itself: a line of samples for each side, and the loop around it.
///
/// What is heard `time` later is read from the line, loses its top end to
/// one low-pass, and goes back in under the new sound, so each repeat has
/// been through the loss once more than the one before. The read is a whole
/// number of samples behind the write, so a repeat lands on its sample.
///
/// The line is as long as the time it was first asked for wants, in steps
/// (two seconds, four, eight, up to the longest), so a short echo does not
/// hold a minute of memory. A time turned past what the standing line holds
/// starts a longer line that reads the old one for everything from before
/// it began, so the repeats in flight keep sounding across the change.
///
/// The settings cross to the audio thread under a lock and are read once per
/// block. A turn of `time` moves the read from one place to the other across
/// a short fade, so it does not click.
final class DelayEffect: @unchecked Sendable {

    let sampleRate: Double
    /// How many samples behind the write the line can be read: the longest
    /// wait it serves.
    let capacity: Int

    private struct Shared {
        var delay: Delay
        /// Set by the audio thread once this line has been written all the
        /// way round, after which nothing older than it is ever read.
        var isFull = false
    }

    private let shared: OSAllocatedUnfairLock<Shared>

    /// The two sides' samples, one after the other. Memory the object owns,
    /// since it is written from the audio thread.
    private let line: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    /// Samples written since this line began, held at `capacity` once it has
    /// gone all the way round.
    private var written = 0

    /// The shorter line this one took over from, read for whatever was
    /// played before this one began. Let go from the main thread once this
    /// line is full, which the audio thread reports under the lock.
    private var previous: DelayEffect?
    /// Whether the audio thread has taken up where `previous` left off.
    private var hasAdopted = false

    /// How far behind the write the line is being read, in samples, the
    /// place it is moving to while a fade runs, and how much of the fade is
    /// left.
    private var tap: Int
    private var nextTap: Int
    private var fadeLeft = 0
    private let fadeLength: Int
    /// Each side's low-pass, which is the loop's loss.
    private var damped: (Float, Float) = (0, 0)

    /// The steps a line's length comes in, in seconds.
    private static let tiers: [Double] = [2, 4, 8, 16, 32, 64]

    /// How many samples behind the write `delay` asks to be read at `rate`.
    static func distance(for delay: Delay, at rate: Double) -> Int {
        let seconds = min(max(0, delay.time), Delay.maxTime)
        return max(1, Int((seconds * rate).rounded()))
    }

    init(_ delay: Delay, sampleRate: Double, replacing previous: DelayEffect? = nil) {
        self.sampleRate = max(1000, sampleRate)
        let wanted = DelayEffect.distance(for: delay, at: self.sampleRate)
        let seconds = DelayEffect.tiers.first { Int($0 * max(1000, sampleRate)) >= wanted }
            ?? DelayEffect.tiers[DelayEffect.tiers.count - 1]
        capacity = max(wanted, Int(seconds * self.sampleRate))
        shared = OSAllocatedUnfairLock(initialState: Shared(delay: delay))
        line = .allocate(capacity: 2 * capacity)
        line.initialize(repeating: 0, count: 2 * capacity)
        // A line that carries on from another keeps only one at the same
        // rate: samples counted on another clock are not where it would
        // look for them.
        self.previous = previous?.sampleRate == self.sampleRate ? previous : nil
        tap = wanted
        nextTap = wanted
        fadeLength = max(1, Int(0.03 * self.sampleRate))
    }

    deinit {
        line.deallocate()
    }

    /// Whether this line can carry these settings at this rate: the same
    /// clock, and a wait it is long enough to hold.
    func serves(_ delay: Delay, at rate: Double) -> Bool {
        rate == sampleRate && DelayEffect.distance(for: delay, at: rate) <= capacity
    }

    /// New settings for the echo already running.
    func update(_ new: Delay) {
        let isFull = shared.withLock { state -> Bool in
            state.delay = new
            return state.isFull
        }
        // Past this point the audio thread reads only its own line, so the
        // one it took over from can go.
        if isFull { previous = nil }
    }

    /// The settings as the audio thread last read them.
    var current: Delay { shared.withLock { $0.delay } }

    // MARK: Running

    /// Rewrites one block in place.
    func process(_ block: AudioBlock) {
        let count = block.frameCount
        guard count > 0 else { return }
        let nowFull = written >= capacity
        let held = shared.withLock { state -> Delay in
            if nowFull { state.isFull = true }
            return state.delay
        }
        if !hasAdopted {
            // Carry on where the shorter line stopped: the place it was
            // reading and its low-pass, so the change of line is not heard.
            hasAdopted = true
            if let previous {
                tap = previous.fadeLeft > 0 ? previous.nextTap : previous.tap
                nextTap = tap
                damped = previous.damped
            }
        }

        let channels = min(block.channelCount, 2)
        let wanted = min(capacity, DelayEffect.distance(for: held, at: sampleRate))
        let feedback = Float(min(max(0, held.feedback), 0.95))
        let mix = Float(min(max(0, held.mix), 1))
        // One pole, whose corner is `damping`; wide open it is taken out.
        let keeps: Float = held.damping >= Delay.openAbove
            ? 1
            : Float(1 - exp(-2 * Double.pi * max(10, held.damping) / sampleRate))
        let left = block[0]
        let right = block[channels - 1]

        for index in 0..<count {
            if fadeLeft == 0, wanted != tap {
                nextTap = wanted
                fadeLeft = fadeLength
            }
            for channel in 0..<channels {
                let samples = channel == 0 ? left : right
                let x = samples[index]
                var delayed = read(channel, behind: tap)
                if fadeLeft > 0 {
                    let staying = Float(fadeLeft) / Float(fadeLength)
                    delayed = delayed * staying + read(channel, behind: nextTap) * (1 - staying)
                }
                var wet = channel == 0 ? damped.0 : damped.1
                wet += keeps * (delayed - wet)
                // A repeat that has faded past anything a sample can hold
                // is nothing, and is stored as nothing.
                if abs(wet) < 1e-20 { wet = 0 }
                if channel == 0 { damped.0 = wet } else { damped.1 = wet }
                line[channel * capacity + writeIndex] = x + feedback * wet
                samples[index] = x * (1 - mix) + wet * mix
            }
            if fadeLeft > 0 {
                fadeLeft -= 1
                if fadeLeft == 0 { tap = nextTap }
            }
            writeIndex += 1
            if writeIndex == capacity { writeIndex = 0 }
            if written < capacity { written += 1 }
        }
    }

    /// The sample written `distance` samples before the one about to be
    /// written: this line's own while it reaches that far back, and the line
    /// it took over from for anything older.
    @inline(__always)
    private func read(_ channel: Int, behind distance: Int) -> Float {
        if distance <= written {
            var index = writeIndex - distance
            if index < 0 { index += capacity }
            return line[channel * capacity + index]
        }
        return previous?.read(channel, behind: distance - written) ?? 0
    }
}
