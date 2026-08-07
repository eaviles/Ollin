import Foundation

/// One struck body's running state: a bank of tones, each fading at its own rate.
///
/// A tone that fades is a two-pole resonator, and a struck object is a handful
/// of them ringing at once. Hitting it is a short push into all of them, so the
/// whole model is: work out the coefficients when the note starts, then add up
/// sixteen numbers a sample.
///
/// The sixteen run as vectors rather than a loop, which is what a bank of
/// identical recursions is, and it means a body with three tones costs the same
/// as one with sixteen. Nothing here allocates: the state is inline.
struct ModalVoice {
    /// The last two outputs of every tone.
    private var previous = SIMD16<Double>()
    private var before = SIMD16<Double>()
    /// How far each tone is carried forward, and how much is taken back.
    private var carry = SIMD16<Double>()
    private var pull = SIMD16<Double>()
    /// How much of the strike goes into each tone.
    private var input = SIMD16<Double>()

    /// The strike itself: a short push, longer for a softer one.
    private var pushLeft = 0
    private var pushLength = 1
    private var pushHeight = 0.0

    /// Silences the body without striking it.
    mutating func reset() {
        previous = SIMD16<Double>()
        before = SIMD16<Double>()
        pushLeft = 0
    }

    /// Sets the body up for a note and hits it.
    mutating func strike(
        frequency: Double, velocity: Double, body: ModalBody, sampleRate: Double
    ) {
        reset()
        let (ratios, gains, count) = body.lanes()
        let nyquist = sampleRate / 2

        carry = SIMD16<Double>()
        pull = SIMD16<Double>()
        input = SIMD16<Double>()

        var total = 0.0
        for index in 0..<count {
            let tone = frequency * ratios[index]
            // A tone past half the sample rate cannot be represented, and
            // trying folds it back down the spectrum as something that was
            // never struck. It is dropped instead.
            guard tone > 1, tone < nyquist * 0.98 else { continue }

            // How long this tone lasts. Higher ones go sooner, by as much as
            // `damping` says, which is most of the difference between a bell
            // and a block of wood.
            let life = max(0.005, body.decay / pow(ratios[index], body.damping))
            let keep = exp(-6.907_755_278_982_137 / (life * sampleRate))
            let angle = 2 * .pi * tone / sampleRate

            carry[index] = 2 * keep * cos(angle)
            pull[index] = keep * keep
            // Scaled by the sine of its own angle, which is what makes every
            // tone come out at the height it was asked for rather than at
            // whatever its frequency happens to give.
            input[index] = gains[index] * sin(angle)
            total += gains[index]
        }

        // Sixteen tones at once must not be sixteen times as loud as one, so
        // the strike is divided by what it is being spread across.
        let level = total > 1e-9 ? min(max(0, velocity), 1) / total : 0
        pushLength = 2 + Int((1 - body.hardness) * (1 - body.hardness) * 0.012 * sampleRate)
        pushHeight = level
        pushLeft = pushLength
    }

    /// The next sample: one push in, sixteen tones on.
    mutating func next() -> Double {
        var push = 0.0
        if pushLeft > 0 {
            // A raised cosine rather than a single spike. Its width is how hard
            // the strike was: a narrow one reaches every tone, a wide one only
            // the low ones, which is a hard mallet against a soft one.
            let through = Double(pushLength - pushLeft) / Double(pushLength)
            push = 0.5 * (1 - cos(2 * .pi * through)) * pushHeight
            pushLeft -= 1
        }

        let now = carry * previous - pull * before + input * SIMD16(repeating: push)
        before = previous
        previous = now

        var sum = 0.0
        for lane in 0..<16 { sum += now[lane] }
        return sum
    }
}
