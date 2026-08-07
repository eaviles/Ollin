import Foundation

/// A delay line over memory somebody else owns.
///
/// The driven models are two of these each, and they are written from the
/// render thread, so the memory is taken once before the first note and handed
/// out rather than allocated here.
struct WaveguideLine {
    private let buffer: UnsafeMutablePointer<Double>
    private let capacity: Int
    private var length = 2
    private var write = 0

    init(buffer: UnsafeMutablePointer<Double>, capacity: Int) {
        self.buffer = buffer
        self.capacity = max(2, capacity)
        buffer.update(repeating: 0, count: self.capacity)
    }

    /// Sets the line's length in whole samples and empties it.
    mutating func reset(length: Int) {
        self.length = max(1, min(capacity - 1, length))
        write = 0
        buffer.update(repeating: 0, count: capacity)
    }

    /// Reads the sample that has travelled the whole line.
    var head: Double {
        let read = write >= length ? write - length : write + capacity - length
        return buffer[read]
    }

    /// Writes the next sample in and advances one step.
    mutating func advance(_ value: Double) {
        buffer[write] = value
        write = write + 1 == capacity ? 0 : write + 1
    }

    var sampleLength: Int { length }
}

/// A bowed string's running state.
///
/// The string is two delay lines meeting at the bow: one running to the bridge
/// and back, one running to the nut and back. What arrives at the bow from each
/// side is a velocity wave, and what leaves is decided by the bow.
///
/// The junction is the published one. The bow and the string have a difference
/// in velocity, the rosin's grip is a function of that difference, and the two
/// outgoing waves are each the *other* side's incoming wave plus the grip times
/// the difference. Written out:
///
/// ```
/// vd  = bowVelocity - (fromNut + fromBridge)
/// out = friction(vd) * vd
/// toBridge = fromNut    + out
/// toNut    = fromBridge + out
/// ```
///
/// The friction curve is the part that makes it a bow rather than a string
/// being pushed. It holds at its maximum while the two are moving together
/// closely enough to stay stuck, then falls away quickly once they tear loose.
/// A note is that cycle repeating: stick, drag, slip, snap back, stick.
struct BowVoice {
    private var bridgeSide: WaveguideLine
    private var nutSide: WaveguideLine

    /// What the bridge reflection keeps each time, which sets how long the
    /// string rings when the bow is lifted.
    private var loopGain = 0.99
    /// The one-zero loss filter's coefficient, and also its delay in samples.
    private var shade = 0.4
    /// Where the rosin lets go, as a velocity difference. Bow force widens it.
    private var slipThreshold = 0.1
    /// The tuning allpass coefficient, on the bridge side only.
    private var eta = 0.0

    private var lastFilterInput = 0.0
    private var lastAllpassInput = 0.0
    private var lastAllpassOutput = 0.0

    static func memoryNeeded(capacity: Int) -> Int { 2 * max(4, capacity) }

    init(buffer: UnsafeMutablePointer<Double>, capacity: Int) {
        let usable = max(4, capacity)
        bridgeSide = WaveguideLine(buffer: buffer, capacity: usable)
        nutSide = WaveguideLine(buffer: buffer + usable, capacity: usable)
    }

    mutating func reset() {
        bridgeSide.reset(length: 2)
        nutSide.reset(length: 2)
        lastFilterInput = 0
        lastAllpassInput = 0
        lastAllpassOutput = 0
    }

    /// Tunes the string for a note. Nothing is excited: a bow makes no sound
    /// until it moves, which is the whole difference from a pluck.
    mutating func start(frequency: Double, spec: BowedString, sampleRate: Double) {
        shade = min(max(0, spec.damping), 1) * 0.5

        // The two sides together are one round trip, so they add up to a period
        // once the loss filter's own delay is taken out of the budget. The bow
        // position is where the period is split between them.
        let period = sampleRate / max(1e-6, frequency)
        let remaining = max(4, period - shade)
        let split = min(max(0.02, spec.position), 0.5)

        // Only one of the two sides can be a whole number of samples and have
        // the loop still come out exactly one period long. So the nut side
        // rounds and the bridge side takes whatever is left over, whole part in
        // the line and fraction in the allpass. Rounding both would leave the
        // loop up to half a sample out, which is nothing at the bottom of the
        // range and most of a semitone at the top.
        var nutWhole = max(1, Int((remaining * (1 - split)).rounded()))
        // The bridge side needs room for a whole sample and the fraction.
        nutWhole = min(nutWhole, max(1, Int(remaining) - 2))
        let bridgeTotal = max(1.2, remaining - Double(nutWhole))
        let bridgeWhole = max(1, Int((bridgeTotal - 0.2).rounded(.down)))
        let fraction = min(max(0.2, bridgeTotal - Double(bridgeWhole)), 1.2)
        eta = (1 - fraction) / (1 + fraction)

        bridgeSide.reset(length: bridgeWhole)
        nutSide.reset(length: nutWhole)

        let trips = max(1e-6, spec.decay * frequency)
        loopGain = min(exp(-6.907_755_278_982_137 / trips), 0.999_99)

        // More force means the rosin holds over a wider range of speeds, so the
        // string stays stuck to the bow for longer in each cycle.
        slipThreshold = 0.02 + 0.34 * min(max(0, spec.force), 1)
    }

    /// One sample, with the bow moving at `bowVelocity`.
    mutating func next(bowVelocity: Double) -> Double {
        let fromBridge = bridgeSide.head
        let fromNut = nutSide.head

        // What the bow is doing relative to the string under it.
        let difference = bowVelocity - (fromBridge + fromNut)
        let injected = friction(difference) * difference

        // Each side leaves carrying what came in from the other, plus the bow.
        let toBridge = fromNut + injected
        let toNut = fromBridge + injected

        // The string is held at both ends, so a velocity wave comes back
        // inverted. The bridge end is also where the string loses what it
        // loses, and where the fraction of a sample is made up.
        let damped = (1 - shade) * toBridge + shade * lastFilterInput
        lastFilterInput = toBridge
        let allpassed = eta * damped + lastAllpassInput - eta * lastAllpassOutput
        lastAllpassInput = damped
        lastAllpassOutput = allpassed

        bridgeSide.advance(-loopGain * allpassed)
        nutSide.advance(-loopGain * toNut)

        // What the bridge is being shaken by is what the body would radiate.
        return fromBridge
    }

    /// How hard the rosin is gripping at a given difference in velocity.
    ///
    /// Flat while the two are close enough to stay stuck together, then falling
    /// away sharply once they tear loose. That shape is the instrument: a curve
    /// that fell off gently would give a string being pushed around, not a
    /// string being bowed.
    private func friction(_ difference: Double) -> Double {
        let magnitude = abs(difference)
        guard magnitude > slipThreshold else { return BowVoice.stickingGrip }
        let ratio = slipThreshold / magnitude
        return BowVoice.stickingGrip * ratio * ratio * ratio
    }

    /// How hard the rosin holds while the string is stuck to the bow.
    ///
    /// Deliberately short of a perfect hold. At exactly 1 the bow is a perfect
    /// reflector while the string is stuck to it, so nothing is taken out of
    /// the string and the note settles at whatever amplitude the slipping
    /// threshold implies, which makes bowing harder change the tone and not the
    /// loudness. Real rosin lets a little go, and that little is what makes the
    /// note as loud as the bow is fast.
    static let stickingGrip = 0.9

    /// The pitch the string is set up to sound, for checking the tuning.
    func soundingFrequency(sampleRate: Double) -> Double {
        let fraction = (1 - eta) / (1 + eta)
        return sampleRate / (Double(bridgeSide.sampleLength) + Double(nutSide.sampleLength)
                             + shade + fraction)
    }
}

/// A blown tube's running state.
///
/// The tube is one delay line carrying a round trip, and the far end sends the
/// wave back changed. What happens at the mouth end is what makes it an
/// instrument, and it is different for the two kinds:
///
/// **A reed** is pushed shut by the pressure that is driving it. Fully shut it
/// is a rigid wall, so the wave comes back untouched; fully open the mouthpiece
/// is simply held at the player's breath pressure. Between those two limits the
/// reflection is a mixture of the two, and that mixture depends on the pressure
/// itself, which is the feedback that makes it oscillate.
///
/// **A jet** of air splits across an edge and is pushed to one side or the
/// other by whatever the tube is already doing. That deflection saturates: past
/// a point, blowing harder cannot push it further, and the odd shape of that
/// saturation is what fills in the harmonics.
struct TubeVoice {
    private var bore: WaveguideLine

    private var loopGain = 0.99
    private var shade = 0.4
    private var lastFilterInput = 0.0
    private var closingPressure = 1.0
    private var eta = 0.0
    private var lastAllpassInput = 0.0
    private var lastAllpassOutput = 0.0
    private var noiseState: UInt64

    static func memoryNeeded(capacity: Int) -> Int { max(4, capacity) }

    init(buffer: UnsafeMutablePointer<Double>, capacity: Int, seed: UInt64) {
        bore = WaveguideLine(buffer: buffer, capacity: max(4, capacity))
        noiseState = seed | 1
    }

    mutating func reset() {
        bore.reset(length: 2)
        lastFilterInput = 0
        lastAllpassInput = 0
        lastAllpassOutput = 0
    }

    mutating func start(frequency: Double, spec: BlownTube, sampleRate: Double) {
        shade = min(max(0, spec.damping), 1) * 0.5

        // The load-bearing line. The tube is stopped at the reed and open at
        // the far end, so it fits a quarter of a wave rather than a half, and
        // its round trip is half a period rather than a whole one. That is
        // exactly why only the odd harmonics survive and why the tone is hollow.
        // Half a period, less what the loss filter itself delays. The leftover
        // fraction goes to an allpass for the same reason it does on a string:
        // rounding the loop to whole samples is inaudible low down and most of
        // a semitone out at the top of the range.
        let period = sampleRate / max(1e-6, frequency)
        let target = max(2.2, period / 2 - shade)
        let whole = max(1, Int((target - 0.2).rounded(.down)))
        let fraction = min(max(0.2, target - Double(whole)), 1.2)
        eta = (1 - fraction) / (1 + fraction)
        bore.reset(length: whole)

        // The loop runs twice per period, so a given fade takes twice as many
        // trips as it would on a string of the same pitch.
        let trips = max(1e-6, spec.decay * frequency * 2)
        loopGain = min(exp(-6.907_755_278_982_137 / trips), 0.999_99)

        // Biting harder shuts the reed at a lower pressure.
        closingPressure = 1.6 - 1.3 * min(max(0, spec.embouchure), 1)
    }

    /// One sample, with the player blowing at `breath`.
    mutating func next(breath: Double, breathiness: Double) -> Double {
        // Real air is turbulent, and a wind instrument with none of that in it
        // sounds synthetic in a way that is hard to place until it is put back.
        let mouth = breath * (1 + breathiness * 0.35 * nextNoise())

        // The far end of the tube: what comes back is quieter, duller, and
        // upside down, because an open end reflects pressure inverted.
        let arriving = bore.head
        let damped = (1 - shade) * arriving + shade * lastFilterInput
        lastFilterInput = arriving
        let allpassed = eta * damped + lastAllpassInput - eta * lastAllpassOutput
        lastAllpassInput = damped
        lastAllpassOutput = allpassed
        let returned = -loopGain * allpassed

        // How far the reed is open. It is pushed shut by the very pressure
        // difference that drives it, which is the feedback that makes the whole
        // thing sing.
        let difference = mouth / 2 - returned
        let opening = min(max(1 - max(0, difference) / closingPressure, 0), 1)
        // Between the two limits the reed actually has: shut, it is a rigid
        // wall and the wave comes back untouched; wide open, the mouthpiece is
        // simply held at the player's breath pressure.
        var outgoing = opening * (mouth - returned) + (1 - opening) * returned
        outgoing = min(max(outgoing, -4), 4)
        bore.advance(outgoing)
        return returned
    }

    /// The pitch the tube is set up to sound, for checking the tuning.
    func soundingFrequency(sampleRate: Double) -> Double {
        let fraction = (1 - eta) / (1 + eta)
        return sampleRate / (2 * (Double(bore.sampleLength) + shade + fraction))
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
