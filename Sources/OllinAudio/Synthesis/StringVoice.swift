import Foundation

/// One plucked string's running state: a delay line with a filtered loop.
///
/// The disturbance traveling up and down a string is a delay line, and what
/// the string loses at each reflection is a filter in the loop. That is the
/// whole model. Everything a player hears comes out of three refinements on it,
/// each of which fixes something audible:
///
/// - **The loop is not a whole number of samples long.** Rounding it to one puts
///   the note out of tune, and the error grows as the loop gets shorter, so the
///   top two octaves are audibly wrong. A first-order allpass supplies the
///   fraction, and the loop filter's own delay is counted into the budget, so
///   changing how bright the string is cannot move its pitch.
/// - **A pluck happens somewhere.** Plucking at a point holds it still, so every
///   harmonic with a node there is missing. A comb on the excitation, notched at
///   the pick position, is what puts that in.
/// - **A pluck has a hardness.** A fingertip releases slowly and only sets the
///   low part of the string moving. A one-pole lowpass on the excitation is that.
///
/// The buffer is memory the renderer owns and hands out, not an array, because
/// this is written from the render thread and an array is one value with one
/// owner that could decide to copy itself. It is twice as long as the longest
/// loop: the second half is scratch the excitation needs, since the comb has to
/// read the burst it is in the middle of overwriting.
struct StringVoice {
    private let buffer: UnsafeMutablePointer<Double>
    private let scratch: UnsafeMutablePointer<Double>
    private let capacity: Int

    /// How many doubles one string needs, given the longest loop it may hold.
    static func memoryNeeded(capacity: Int) -> Int { 2 * max(4, capacity) }

    /// The whole-sample part of the loop.
    private var delay = 2
    /// Where the next sample is written.
    private var write = 0
    /// What the loop keeps each time round, which sets how long the note rings.
    private var loopGain = 0.99
    /// The one-zero loop filter's coefficient, which is also its delay in
    /// samples. Higher takes more off the top and rings shorter up there.
    private var shade = 0.5
    /// The tuning allpass coefficient.
    private var eta = 0.0

    private var lastFilterInput = 0.0
    private var lastAllpassInput = 0.0
    private var lastAllpassOutput = 0.0
    private var noiseState: UInt64

    /// - Parameter buffer: `memoryNeeded(capacity:)` doubles the caller owns.
    init(buffer: UnsafeMutablePointer<Double>, capacity: Int, seed: UInt64) {
        let usable = max(4, capacity)
        self.buffer = buffer
        self.scratch = buffer + usable
        self.capacity = usable
        // A zero state would leave the generator stuck at zero forever.
        self.noiseState = seed | 1
        buffer.update(repeating: 0, count: 2 * usable)
    }

    /// Silences the string without plucking it.
    mutating func reset() {
        buffer.update(repeating: 0, count: 2 * capacity)
        write = 0
        lastFilterInput = 0
        lastAllpassInput = 0
        lastAllpassOutput = 0
    }

    /// Sets the string up for a note and excites it.
    mutating func pluck(
        frequency: Double, velocity: Double, spec: PluckedString, sampleRate: Double
    ) {
        reset()

        // How much of the top the loop filter takes off. Half is the most it
        // can take (it puts a zero exactly on Nyquist); past that it starts
        // giving the top back, so the useful range is the half below.
        shade = min(max(0, spec.damping), 1) * 0.5

        // The loop has to come out exactly as long as one period, and the loop
        // filter is part of it: a one-zero filter with coefficient `shade`
        // delays by `shade` samples. Take that out first, then leave the
        // fraction to the allpass, keeping it in the range where a first-order
        // allpass is well behaved (a fraction near zero puts its pole on the
        // unit circle).
        let period = sampleRate / max(1e-6, frequency)
        let remaining = period - shade
        delay = max(2, min(capacity - 1, Int((remaining - 0.2).rounded(.down))))
        let fraction = min(max(0.2, remaining - Double(delay)), 1.2)
        eta = (1 - fraction) / (1 + fraction)

        // What the loop keeps each round trip, so that the note falls to a
        // thousandth of itself after `decay` seconds. The loop runs once per
        // period, so the number of round trips in that time is what sets it.
        let trips = max(1e-6, spec.decay * frequency)
        loopGain = min(exp(-6.907_755_278_982_137 / trips), 0.999_99)

        excite(spec: spec, velocity: velocity, sampleRate: sampleRate)
    }

    /// Fills the line with the disturbance a pluck leaves behind.
    private mutating func excite(spec: PluckedString, velocity: Double, sampleRate: Double) {
        let count = delay

        // Noise is every frequency at once, which is a string held in a random
        // shape and let go. What follows takes out the parts a real pluck would
        // not have put in. It is built in the scratch half, because the comb
        // below reads the burst while it writes the line.
        for index in 0..<count { scratch[index] = nextNoise() }

        // How hard the pluck is, as the top of what it sets moving. Playing
        // harder is brighter, which is what a stronger pluck does, so velocity
        // moves it as well as the setting.
        let strength = min(max(0, spec.hardness), 1) * (0.35 + 0.65 * min(max(0, velocity), 1))
        let bandwidth = 300 * pow(sampleRate / 2 / 300, strength)
        let pole = exp(-2 * .pi * bandwidth / sampleRate)
        var carried = 0.0
        for index in 0..<count {
            carried = (1 - pole) * scratch[index] + pole * carried
            scratch[index] = carried
        }

        // The pick position. A string held at a point cannot move there, so
        // every harmonic with a node at that point is missing from the sound.
        // Subtracting the excitation from itself, that far round the loop,
        // notches exactly those harmonics; the subtraction wraps because the
        // line is a loop, so the notches land on the harmonics rather than near
        // them.
        let offset = max(1, min(count - 1, Int((spec.pick * Double(count)).rounded())))
        var peak = 0.0
        for index in 0..<count {
            buffer[index] = scratch[index] - scratch[(index + count - offset) % count]
            peak = max(peak, abs(buffer[index]))
        }

        // A pluck is as loud as it was played, whatever the shaping above left
        // behind, so the burst is scaled to a known height rather than to
        // whatever the noise happened to reach.
        let scale = peak > 1e-9 ? min(max(0, velocity), 1) / peak : 0
        for index in 0..<count { buffer[index] *= scale }
        for index in count..<capacity { buffer[index] = 0 }

        // The line is read a whole loop behind where it is written, so the
        // burst has to sit in the samples the first read will reach. Leaving
        // the write head at the start instead points it at the empty tail, and
        // the string never sounds at all.
        write = count == capacity ? 0 : count
    }

    /// The next sample, advancing the loop once.
    mutating func next() -> Double {
        let read = write >= delay ? write - delay : write + capacity - delay
        let out = buffer[read]

        // What the string loses at the reflection: a one-zero filter, which
        // takes nothing off the fundamental and everything off Nyquist when it
        // is set halfway.
        let damped = (1 - shade) * out + shade * lastFilterInput
        lastFilterInput = out

        // The fraction of a sample the whole-number delay could not supply.
        let allpassed = eta * damped + lastAllpassInput - eta * lastAllpassOutput
        lastAllpassInput = damped
        lastAllpassOutput = allpassed

        buffer[write] = loopGain * allpassed
        write = write + 1 == capacity ? 0 : write + 1
        return out
    }

    /// The pitch this string is actually set up to sound, in Hz.
    ///
    /// The whole loop, counting the loop filter's delay and the fraction the
    /// allpass supplies. Used to check the tuning rather than to make sound.
    func soundingFrequency(sampleRate: Double) -> Double {
        let fraction = (1 - eta) / (1 + eta)
        return sampleRate / (Double(delay) + shade + fraction)
    }

    private mutating func nextNoise() -> Double {
        noiseState &+= 0x9E37_79B9_7F4A_7C15
        var z = noiseState
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1.0
    }
}
