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

    /// Changes the line's length in whole samples and keeps what is in it,
    /// which is how a sounding note is bent: the wave already traveling the
    /// line arrives a little sooner or later from here on.
    mutating func setLength(_ length: Int) {
        self.length = max(1, min(capacity - 1, length))
    }

    /// Reads the sample that has traveled the whole line.
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
///
/// The bow's grip is scaled by how much of it is on the string. Lifted, the
/// junction passes both waves straight through, and the string rings down over
/// its `decay` like a plucked one.
struct BowVoice {
    private var bridgeSide: WaveguideLine
    private var nutSide: WaveguideLine

    /// What the bridge reflection keeps each time, which sets how long the
    /// string rings when the bow is lifted. The whole loop's loss is taken
    /// here, once a period; the nut reflects without loss.
    private var loopGain = 0.99
    /// The one-zero loss filter's coefficient, and also its delay in samples.
    private var shade = 0.4
    /// Where the rosin lets go, as a velocity difference. Bow force widens it.
    private var slipThreshold = 0.1
    /// The tuning allpass coefficient, on the bridge side only.
    private var eta = 0.0
    /// Where along the string the bow sits, kept so a bend keeps the split.
    private var split = 0.13

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
        // The loss filter and what the loop keeps, so that a lifted bow lets
        // the note ring for `decay` at any pitch (`loopLoss`).
        (shade, loopGain) = loopLoss(decay: spec.decay, damping: spec.damping,
                                     frequency: frequency, sampleRate: sampleRate)

        // The two sides together are one round trip, so they add up to a period
        // once the loss filter's own delay is taken out of the budget. The bow
        // position is where the period is split between them.
        split = min(max(0.02, spec.position), 0.5)
        let (bridgeWhole, nutWhole, allpass) = lengths(frequency: frequency, sampleRate: sampleRate)
        eta = allpass
        bridgeSide.reset(length: bridgeWhole)
        nutSide.reset(length: nutWhole)

        // More force means the rosin holds over a wider range of speeds, so the
        // string stays stuck to the bow for longer in each cycle.
        slipThreshold = 0.02 + 0.34 * min(max(0, spec.force), 1)
    }

    /// Moves a sounding string to another pitch without emptying it, which is
    /// what a bend under the finger asks for. The bow position, the loss, and
    /// the ring time stay what the note started with.
    mutating func retune(frequency: Double, sampleRate: Double) {
        let (bridgeWhole, nutWhole, allpass) = lengths(frequency: frequency, sampleRate: sampleRate)
        eta = allpass
        bridgeSide.setLength(bridgeWhole)
        nutSide.setLength(nutWhole)
    }

    /// The two sides' whole-sample lengths and the allpass coefficient for
    /// the fraction, for one period at `frequency`.
    private func lengths(frequency: Double, sampleRate: Double) -> (bridge: Int, nut: Int, eta: Double) {
        // The two sides together are one round trip, so they add up to a period
        // once the loss filter's own delay is taken out of the budget. The bow
        // position is where the period is split between them.
        let period = sampleRate / max(1e-6, frequency)
        let remaining = max(4, period - shade)

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
        return (bridgeWhole, nutWhole, (1 - fraction) / (1 + fraction))
    }

    /// One sample, with the bow moving at `bowVelocity` and `contact` of it
    /// on the string, `0...1`: 0 is lifted clear, 1 is the whole bow.
    mutating func next(bowVelocity: Double, contact: Double) -> Double {
        let fromBridge = bridgeSide.head
        let fromNut = nutSide.head

        // What the bow is doing relative to the string under it. A bow resting
        // still on the string grips it all the same and mutes it, so it is
        // the contact, not the speed, that lets a lifted string ring.
        let difference = bowVelocity - (fromBridge + fromNut)
        let injected = contact * friction(difference) * difference

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
        nutSide.advance(-toNut)

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

    /// The pressure under which the bow starts to leave the string: its grip
    /// is scaled by `pressure / liftedBelow` there, and is whole above. Low
    /// enough that no preset speaks under it (each does from about 0.15), so
    /// a sounding note is untouched.
    static let liftedBelow = 0.1

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
/// instrument, and here that is a reed.
///
/// A reed is pushed shut by the pressure that is driving it. Fully shut it
/// is a rigid wall, so the wave comes back untouched; fully open the mouthpiece
/// is simply held at the player's breath pressure. Between those two limits the
/// reflection is a mixture of the two, and that mixture depends on the pressure
/// itself, which is the feedback that makes it oscillate.
///
/// The breath is reckoned in the reed's own closing pressure. A tube starts to
/// sound once the breath reaches a fraction of it that depends on how much the
/// bore loses (half, for a bore that lost nothing), so each note's start is
/// worked out from its own loss and placed at the same point of the pressure
/// dial (`TubeVoice.speaksFrom`) whatever the pitch or the reed. Full pressure
/// blows `1.1 / closingPressure` of it, so a tighter bite comes nearer to
/// shutting the reed. And what is heard is the bore's pressure with its
/// standing part taken out, since the breath holds the mouthpiece above the
/// room's pressure while the sound the tube radiates swings about it.
struct TubeVoice {
    private var bore: WaveguideLine

    private var loopGain = 0.99
    private var shade = 0.4
    private var lastFilterInput = 0.0
    private var closingPressure = 1.0
    /// The breath, in closing pressures, at which this note starts to sound.
    private var onset = 0.5
    /// The breath, in closing pressures, full pressure blows.
    private var full = 1.1
    private var eta = 0.0
    private var lastAllpassInput = 0.0
    private var lastAllpassOutput = 0.0
    private var noiseState: UInt64
    /// The DC block on what radiates: its pole, and its last input and output.
    private var blockPole = 0.997
    private var lastRadiatedInput = 0.0
    private var lastRadiated = 0.0

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
        lastRadiatedInput = 0
        lastRadiated = 0
    }

    /// The point of the pressure dial, `0...1`, at which every tube starts to
    /// sound, whatever its pitch or its reed. Below it the breath rises to the
    /// note's onset and nothing is heard; above it the breath rises on to
    /// full.
    static let speaksFrom = 0.3

    /// Where the standing pressure is taken out of what the tube radiates, in
    /// Hz: under every note it plays, and quick enough that a step in the
    /// breath settles in a few milliseconds rather than holding an offset.
    static let blockedBelow = 20.0

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
        let (whole, allpass) = length(frequency: frequency, sampleRate: sampleRate)
        eta = allpass
        bore.reset(length: whole)

        // The loop runs twice per period, so a given fade takes twice as many
        // trips as it would on a string of the same pitch.
        let trips = max(1e-6, spec.decay * frequency * 2)
        loopGain = min(exp(-6.907_755_278_982_137 / trips), 0.999_99)

        // Biting harder shuts the reed at a lower pressure.
        closingPressure = 1.6 - 1.3 * min(max(0, spec.embouchure), 1)

        // Where this note starts to sound, from the reed's small-signal gain.
        // With the breath and both waves in closing pressures, the reed hands
        // back 2x - 1 of a small change in the returning wave, x being how far
        // the reed is pushed toward shut (mouth minus twice the returning
        // wave). Round the bore, half a period of delay turns the fundamental
        // over once and the open end once more, so it comes back with the
        // loop's gain G at the note, and the note grows once (2x - 1) G passes
        // 1. The bore holds still at the operating point the loop's gain g at
        // no frequency sets, x² + 2(k - 1)x = 2k m with k = (1 + g) / 2g,
        // which gives the breath m there. Measured against a sweep of the
        // breath at five pitches on each preset, it lands within 0.005.
        let w = 2 * Double.pi * frequency / sampleRate
        let response = (1 - 2 * shade * (1 - shade) * (1 - cos(w))).squareRoot()
        let x = (1 + 1 / (loopGain * response)) / 2
        let k = (1 + loopGain) / (2 * loopGain)
        onset = (x * x + 2 * (k - 1) * x) / (2 * k)
        // Full pressure blows what it always did; a tube whose onset is
        // nearly that still swells over the top of the dial.
        full = max(1.1 / closingPressure, onset * 1.15)
        blockPole = exp(-2 * Double.pi * TubeVoice.blockedBelow / sampleRate)
    }

    /// The breath at `pressure`, in closing pressures: up to the note's
    /// onset over the first `speaksFrom` of the dial, then on to full.
    private func breath(at pressure: Double) -> Double {
        let p = min(max(0, pressure), 1)
        let from = TubeVoice.speaksFrom
        return p <= from ? onset * p / from : onset + (full - onset) * (p - from) / (1 - from)
    }

    /// Moves a sounding tube to another pitch without emptying it. The reed,
    /// the loss, and the ring time stay what the note started with.
    mutating func retune(frequency: Double, sampleRate: Double) {
        let (whole, allpass) = length(frequency: frequency, sampleRate: sampleRate)
        eta = allpass
        bore.setLength(whole)
    }

    /// The bore's whole-sample length and the allpass coefficient for the
    /// fraction, for half a period at `frequency`.
    private func length(frequency: Double, sampleRate: Double) -> (whole: Int, eta: Double) {
        let period = sampleRate / max(1e-6, frequency)
        let target = max(2.2, period / 2 - shade)
        let whole = max(1, Int((target - 0.2).rounded(.down)))
        let fraction = min(max(0.2, target - Double(whole)), 1.2)
        return (whole, (1 - fraction) / (1 + fraction))
    }

    /// One sample, with the player blowing at `pressure`, `0...1`.
    mutating func next(pressure: Double, breathiness: Double) -> Double {
        // Real air is turbulent, and a wind instrument with none of that in it
        // sounds synthetic in a way that is hard to place until it is put back.
        let mouth = closingPressure * breath(at: pressure) * (1 + breathiness * 0.35 * nextNoise())

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

        // What radiates: the bore's pressure less its standing part, through
        // a one-pole DC block.
        let radiated = returned - lastRadiatedInput + blockPole * lastRadiated
        lastRadiatedInput = returned
        lastRadiated = radiated
        return radiated
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
