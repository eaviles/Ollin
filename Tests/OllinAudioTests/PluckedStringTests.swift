import Foundation
import Testing
@testable import OllinAudio

/// A plucked string is a model rather than a shape, so what is checked is that
/// it behaves the way the thing it models does: it lands on the pitch it was
/// asked for, it loses its top before its bottom, and where it was plucked is
/// audible in what is missing from it. Every claim is measured against a twin
/// that differs in exactly one setting.
@Suite struct PluckedStringTests {

    static let sampleRate = 44100.0

    // MARK: - Tuning

    /// The loop has to come out exactly one period long, counting the loop
    /// filter's own delay and the fraction the allpass supplies. A whole number
    /// of samples cannot do that, and the error grows as the loop gets shorter,
    /// which is why an integer delay line is audibly wrong at the top.
    @Test func everyNoteIsInTuneAcrossTheRange() {
        let capacity = 3000
        let memory = UnsafeMutablePointer<Double>.allocate(
            capacity: StringVoice.memoryNeeded(capacity: capacity)
        )
        defer { memory.deallocate() }

        var worstCents = 0.0
        var worstIfRounded = 0.0
        for midi in 21...105 {
            let wanted = 440 * pow(2, (Double(midi) - 69) / 12)
            var string = StringVoice(buffer: memory, capacity: capacity, seed: 1)
            string.pluck(frequency: wanted, velocity: 0.8, spec: .steel,
                         sampleRate: Self.sampleRate)

            let sounded = string.soundingFrequency(sampleRate: Self.sampleRate)
            worstCents = max(worstCents, abs(1200 * log2(sounded / wanted)))

            // What the same note would come out as if the loop were rounded to
            // a whole number of samples, which is the thing being fixed.
            let period = Self.sampleRate / wanted
            let rounded = Self.sampleRate / period.rounded()
            worstIfRounded = max(worstIfRounded, abs(1200 * log2(rounded / wanted)))
        }

        #expect(worstCents < 0.01, "worst tuning error \(worstCents) cents")
        // The counterfactual, so the tolerance above means something: rounding
        // is out by most of a semitone at the top of the range.
        #expect(worstIfRounded > 40, "rounding would only be \(worstIfRounded) cents out")
    }

    /// The loop filter delays by a fraction of a sample, and how much depends on
    /// how bright the string is. If that fraction is not counted into the loop,
    /// changing the brightness moves the pitch. These two differ only in
    /// `damping`.
    @Test func brightnessDoesNotMoveThePitch() {
        for midi in [40, 64, 88] {
            let wanted = 440 * pow(2, (Double(midi) - 69) / 12)
            let dark = renderNote(
                PluckedString(hardness: 0.9, decay: 3, damping: 1.0),
                midi: Double(midi), seconds: 0.8
            )
            let bright = renderNote(
                PluckedString(hardness: 0.9, decay: 3, damping: 0.0),
                midi: Double(midi), seconds: 0.8
            )
            let darkPitch = measuredFrequency(dark, near: wanted)
            let brightPitch = measuredFrequency(bright, near: wanted)

            #expect(abs(1200 * log2(darkPitch / wanted)) < 3,
                    "damped string at midi \(midi) measured \(darkPitch), wanted \(wanted)")
            #expect(abs(1200 * log2(brightPitch / darkPitch)) < 3,
                    "brightness moved midi \(midi) from \(darkPitch) to \(brightPitch)")
        }
    }

    // MARK: - The pluck

    /// A string held at a point cannot move there, so a pluck exactly halfway
    /// along is missing every harmonic that has a node in the middle: the even
    /// ones. Its twin, plucked a quarter along, keeps them.
    @Test func pluckingInTheMiddleLosesTheEvenHarmonics() {
        let midi = 45.0
        let fundamental = 440 * pow(2, (midi - 69) / 12)

        let middle = renderNote(PluckedString(pick: 0.5, hardness: 0.95, decay: 4, damping: 0.1),
                                midi: midi, seconds: 0.5)
        let quarter = renderNote(PluckedString(pick: 0.25, hardness: 0.95, decay: 4, damping: 0.1),
                                 midi: midi, seconds: 0.5)

        let middleSecond = magnitude(middle, at: fundamental * 2)
        let quarterSecond = magnitude(quarter, at: fundamental * 2)
        let middleFirst = magnitude(middle, at: fundamental)
        let quarterFirst = magnitude(quarter, at: fundamental)

        // Both still have a fundamental, so this is about the second harmonic
        // rather than about one of them being quieter overall.
        #expect(middleFirst > 0.005)
        #expect(quarterFirst > 0.005)
        #expect(middleSecond / middleFirst < 0.1 * (quarterSecond / quarterFirst),
                "middle \(middleSecond / middleFirst) vs quarter \(quarterSecond / quarterFirst)")
    }

    /// How hard the string is plucked decides how much of it starts moving. The
    /// twins differ only in `hardness`.
    @Test func aHarderPluckStartsBrighter() {
        let fundamental = 440 * pow(2, (52.0 - 69) / 12)
        let soft = renderNote(PluckedString(hardness: 0.0, decay: 3), midi: 52, seconds: 0.15)
        let hard = renderNote(PluckedString(hardness: 1.0, decay: 3), midi: 52, seconds: 0.15)
        let softly = centroid(soft, fundamental: fundamental)
        let firmly = centroid(hard, fundamental: fundamental)
        #expect(firmly > 2 * softly, "hard \(firmly) Hz vs soft \(softly) Hz")
    }

    /// Velocity moves the same thing, because playing harder is brighter. Same
    /// string, different strike.
    @Test func playingHarderIsBrighterAsWellAsLouder() {
        let fundamental = 440 * pow(2, (52.0 - 69) / 12)
        let gentle = renderNote(.steel, midi: 52, seconds: 0.15, velocity: 0.15)
        let firm = renderNote(.steel, midi: 52, seconds: 0.15, velocity: 1.0)
        let gently = centroid(gentle, fundamental: fundamental)
        let firmly = centroid(firm, fundamental: fundamental)
        #expect(rms(firm) > rms(gentle))
        #expect(firmly > 1.2 * gently, "firm \(firmly) Hz vs gentle \(gently) Hz")
    }

    // MARK: - How it fades

    /// `decay` is how long the note takes to fall to a thousandth of itself, so
    /// a short one is nearly gone where a long one is still going.
    @Test func decaySetsHowLongTheNoteRings() {
        let short = renderNote(PluckedString(decay: 0.4), midi: 45, seconds: 1.2)
        let long = renderNote(PluckedString(decay: 6.0), midi: 45, seconds: 1.2)

        let window = Int(Self.sampleRate) / 10
        let start = Int(Self.sampleRate)              // one second in
        let shortLate = rms(Array(short[start..<(start + window)]))
        let longLate = rms(Array(long[start..<(start + window)]))

        #expect(shortLate < 0.02 * longLate, "short \(shortLate) vs long \(longLate)")
        // Both were struck the same. Measured over the first few milliseconds,
        // before the short one has had time to be short.
        let struck = Int(Self.sampleRate * 0.005)
        let shortPeak = short[0..<struck].map { abs($0) }.max() ?? 0
        let longPeak = long[0..<struck].map { abs($0) }.max() ?? 0
        #expect(abs(shortPeak - longPeak) < 0.05 * longPeak,
                "struck at \(shortPeak) vs \(longPeak)")
    }

    /// A real string loses its top before its bottom, so a held note darkens as
    /// it rings. These twins differ only in `damping`, and the fundamental is
    /// measured too, so this is about the top going rather than everything.
    @Test func theTopGoesBeforeTheBottom() {
        let fundamental = 440 * pow(2, (45.0 - 69) / 12)
        let damped = renderNote(PluckedString(hardness: 0.9, decay: 4, damping: 1.0),
                                midi: 45, seconds: 1.0)
        let ringing = renderNote(PluckedString(hardness: 0.9, decay: 4, damping: 0.02),
                                 midi: 45, seconds: 1.0)

        let window = Int(Self.sampleRate) / 4
        let start = Int(Self.sampleRate * 0.6)
        let dampedLate = Array(damped[start..<(start + window)])
        let ringingLate = Array(ringing[start..<(start + window)])

        // Measured well up the spectrum, because that is where a one-zero loss
        // in the loop actually takes hold: near the fundamental it removes
        // almost nothing however hard it is set.
        let dampedHigh = energyAbove(4000, of: dampedLate, fundamental: fundamental)
        let ringingHigh = energyAbove(4000, of: ringingLate, fundamental: fundamental)
        let dampedLow = magnitude(dampedLate, at: fundamental)
        let ringingLow = magnitude(ringingLate, at: fundamental)

        #expect(dampedHigh < 0.2 * ringingHigh,
                "above 4 kHz: damped \(dampedHigh) vs ringing \(ringingHigh)")
        // The fundamental is still there in both, which is what makes the line
        // above about color rather than about one of them having stopped.
        #expect(dampedLow > 0.3 * ringingLow,
                "fundamental: damped \(dampedLow) vs ringing \(ringingLow)")
    }

    // MARK: - Behaving itself

    @Test func theLoopStaysBoundedAtEverySettingAndPitch() {
        for midi in stride(from: 12.0, through: 120.0, by: 6) {
            for spec in [PluckedString.nylon, .steel, .harp, .muted,
                         PluckedString(pick: 0.99, hardness: 1, decay: 30, damping: 0),
                         PluckedString(pick: 0.01, hardness: 0, decay: 0.02, damping: 1)] {
                let samples = renderNote(spec, midi: midi, seconds: 0.3, velocity: 1)
                let peak = samples.map { abs($0) }.max() ?? 0
                #expect(peak.isFinite, "midi \(midi) went to \(peak)")
                #expect(peak <= 1.01, "midi \(midi) reached \(peak)")
                #expect(samples.allSatisfy { $0.isFinite })
            }
        }
    }

    @Test func theSameNoteRendersToTheSameSamples() {
        let one = renderNote(.steel, midi: 57, seconds: 0.4)
        let same = renderNote(.steel, midi: 57, seconds: 0.4)
        #expect(one == same)
    }

    /// A string is a `Voice` like any other, so everything around it is
    /// unchanged: the presets read back, and swapping the source swaps it back.
    @Test func aStringIsAnOrdinaryVoice() {
        #expect(Voice.nylon.string == .nylon)
        #expect(Voice.nylon.waveform == .sine)      // it is not a wave at all
        #expect(Voice.pluck.string == nil)

        var voice = Voice.steel
        voice.waveform = .square
        #expect(voice.string == nil)
        #expect(voice.source == .wave(.square))

        voice.string = .harp
        #expect(voice.source == .string(.harp))
    }

    @Test func settingsAreKeptInsideWhatMakesSense() {
        let wild = PluckedString(pick: 5, hardness: -3, decay: -1, damping: 9)
        #expect(wild.pick <= 0.99 && wild.pick >= 0.01)
        #expect(wild.hardness == 0)
        #expect(wild.decay > 0)
        #expect(wild.damping == 1)
    }

    // MARK: - Rendering and measuring

    /// One note through the real renderer, offline.
    private func renderNote(
        _ spec: PluckedString, midi: Double, seconds: Double, velocity: Double = 0.8
    ) -> [Float] {
        let events = EventRing()
        // A flat envelope, so what is measured is the string and not the shape
        // laid over it.
        let voice = Voice(string: spec, envelope: Envelope(attack: 0.0002, decay: 0.001,
                                                           sustain: 1, release: 0.1), gain: 1)
        let renderer = SynthRenderer(
            voice: voice, polyphony: 4, sampleRate: Self.sampleRate, events: events, seed: 99
        )
        renderer.gain = 1
        events.push(SynthEvent(kind: .noteOn, pitch: midi, velocity: velocity))

        let count = Int(seconds * Self.sampleRate)
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: count) }
        return samples
    }

    /// The pitch a stretch of samples actually came out at.
    ///
    /// Found by looking for the frequency with the most energy in it, coarsely
    /// and then finely. Reading the peak of an autocorrelation instead is
    /// limited to whole samples of lag, which at the top of the range is tens
    /// of cents wide and would not be able to see what this is measuring.
    private func measuredFrequency(_ samples: [Float], near: Double) -> Double {
        // Skip the attack: the pluck itself is not periodic yet.
        let start = Int(Self.sampleRate * 0.08)
        let length = min(samples.count - start, 20000)
        guard length > 1024 else { return 0 }
        let window = Array(samples[start..<(start + length)])

        func peak(from low: Double, to high: Double, step: Double) -> Double {
            var best = low
            var bestValue = -Double.infinity
            var probe = low
            while probe <= high {
                let value = magnitude(window, at: probe)
                if value > bestValue { bestValue = value; best = probe }
                probe += step
            }
            return best
        }

        let coarse = peak(from: near * 0.95, to: near * 1.05, step: near * 0.001)
        return peak(from: coarse - near * 0.002, to: coarse + near * 0.002, step: near * 0.00002)
    }

    /// How much of one frequency is in a stretch of samples, windowed so the
    /// ends do not smear it.
    private func magnitude(_ samples: [Float], at frequency: Double) -> Double {
        let count = samples.count
        guard count > 8 else { return 0 }
        var real = 0.0
        var imaginary = 0.0
        var weight = 0.0
        let step = 2 * Double.pi * frequency / Self.sampleRate
        for index in 0..<count {
            let hann = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(count - 1))
            let value = Double(samples[index]) * hann
            real += value * cos(step * Double(index))
            imaginary -= value * sin(step * Double(index))
            weight += hann
        }
        // Divided by what the window itself sums to, so the answer is the
        // amplitude that is really there rather than the window's share of it.
        return weight > 0 ? sqrt(real * real + imaginary * imaginary) * 2 / weight : 0
    }

    /// Where the weight of the sound sits, which is what "bright" means.
    ///
    /// Measured at the note's own harmonics rather than on a fixed grid: a grid
    /// mostly lands between them and reads the smear rather than the sound.
    private func centroid(_ samples: [Float], fundamental: Double) -> Double {
        var weighted = 0.0
        var total = 0.0
        var harmonic = 1
        while Double(harmonic) * fundamental < Self.sampleRate / 2.2 {
            let frequency = Double(harmonic) * fundamental
            let energy = magnitude(samples, at: frequency)
            weighted += frequency * energy
            total += energy
            harmonic += 1
        }
        return total > 0 ? weighted / total : 0
    }

    /// How much is left above a frequency, summed over the note's harmonics.
    private func energyAbove(_ floor: Double, of samples: [Float], fundamental: Double) -> Double {
        var total = 0.0
        var harmonic = max(1, Int(floor / fundamental))
        while Double(harmonic) * fundamental < Self.sampleRate / 2.2 {
            total += magnitude(samples, at: Double(harmonic) * fundamental)
            harmonic += 1
        }
        return total
    }

    private func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }
}
