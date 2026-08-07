import Foundation
import Testing
@testable import OllinAudio

/// The synthesis side is a pure renderer: events in, samples out, no clock and
/// no engine. So it is tested by rendering and measuring, and each test that
/// could pass for the wrong reason is run against the twin that should fail.
@Suite struct SynthTests {

    static let sampleRate = 44100.0

    // MARK: Pitch

    @Test func pitchNamesAndNumbersAgree() {
        #expect(Pitch(69).frequency == 440)
        #expect(Pitch("A4").midi == 69)
        #expect(Pitch("C4").midi == 60)
        #expect(Pitch("C-1").midi == 0)
        // Sharps and flats reach the same key from either side.
        #expect(Pitch("F#3").midi == Pitch("Gb3").midi)
        #expect(Pitch("A#4").midi == Pitch("Bb4").midi)
        // A name without an octave lands in the one middle C sits in.
        #expect(Pitch("C").midi == 60)
        #expect(Pitch(name: "banana") == nil)
    }

    @Test func anOctaveIsAlwaysADoubling() {
        for midi in stride(from: 24.0, through: 96.0, by: 7.0) {
            let low = Pitch(midi).frequency
            let high = Pitch(midi + 12).frequency
            #expect(abs(high / low - 2) < 1e-12)
        }
    }

    @Test func frequencyRoundTripsThroughPitch() {
        for hz in [55.0, 261.6255653, 440.0, 1760.0] {
            #expect(abs(Pitch(frequency: hz).frequency - hz) < 1e-9)
        }
    }

    // MARK: Envelope

    @Test func attackReachesFullLevelInTheStatedTime() {
        var runner = EnvelopeRunner()
        runner.prepare(Envelope(attack: 0.1, decay: 1, sustain: 1, release: 0.1), sampleRate: Self.sampleRate)
        runner.noteOn()

        let expected = Int(0.1 * Self.sampleRate)
        var level = 0.0
        for _ in 0..<expected { level = runner.next() }
        #expect(abs(level - 1) < 0.01)

        // The counterfactual: half as long, and it is only halfway there.
        var quick = EnvelopeRunner()
        quick.prepare(Envelope(attack: 0.2, decay: 1, sustain: 1, release: 0.1), sampleRate: Self.sampleRate)
        quick.noteOn()
        var half = 0.0
        for _ in 0..<expected { half = quick.next() }
        #expect(abs(half - 0.5) < 0.01)
    }

    @Test func decayLandsOnSustainWithinTheStatedTime() {
        var runner = EnvelopeRunner()
        runner.prepare(
            Envelope(attack: 0, decay: 0.2, sustain: 0.4, release: 0.1),
            sampleRate: Self.sampleRate
        )
        runner.noteOn()
        for _ in 0..<Int(0.2 * Self.sampleRate) { _ = runner.next() }
        // "Within a thousandth of where it is headed" is the documented meaning.
        #expect(abs(runner.level - 0.4) < 0.001)
    }

    @Test func releaseRunsFromWhereTheNoteActuallyWas() {
        // A note let go halfway through its attack must fall from there, not
        // jump to full level first and not cut to silence: either is a click.
        var runner = EnvelopeRunner()
        runner.prepare(
            Envelope(attack: 0.2, decay: 0.1, sustain: 0.8, release: 0.2),
            sampleRate: Self.sampleRate
        )
        runner.noteOn()
        for _ in 0..<Int(0.1 * Self.sampleRate) { _ = runner.next() }
        let atRelease = runner.level
        #expect(abs(atRelease - 0.5) < 0.02)

        runner.noteOff()
        let firstAfter = runner.next()
        #expect(abs(firstAfter - atRelease) < 0.001)   // no step at the join
        #expect(runner.stage == .release)
    }

    @Test func aFinishedEnvelopeFreesItsVoice() {
        var runner = EnvelopeRunner()
        runner.prepare(Envelope(attack: 0, decay: 0.01, sustain: 0, release: 0.01), sampleRate: Self.sampleRate)
        runner.noteOn()
        runner.noteOff()
        for _ in 0..<Int(0.2 * Self.sampleRate) { _ = runner.next() }
        #expect(runner.isFinished)
    }

    @Test func theDrawableEnvelopeMatchesTheOneThatIsPlayed() {
        // `level(at:heldFor:)` is what a sketch draws its sound from, so it has
        // to be the same shape the voices actually run, not a picture of one.
        let shapes: [Envelope] = [
            .percussive, .organ, .swell, .standard,
            Envelope(attack: 0, decay: 0, sustain: 1, release: 0.05),
            Envelope(attack: 0.05, decay: 0.2, sustain: 0.3, release: 0.4),
        ]
        for envelope in shapes {
            for hold in [0.02, 0.3, 1.2] {
                var runner = EnvelopeRunner()
                runner.prepare(envelope, sampleRate: Self.sampleRate)
                runner.noteOn()

                let holdSamples = Int(hold * Self.sampleRate)
                let total = holdSamples + Int((envelope.release + 0.3) * Self.sampleRate)
                var released = false
                var worst = 0.0
                for sample in 0..<total {
                    if sample == holdSamples, !released {
                        runner.noteOff()
                        released = true
                    }
                    let played = runner.next()
                    // The runner's first output is one sample into the note,
                    // where `level(at: 0)` is the instant it starts.
                    let drawn = envelope.level(at: Double(sample + 1) / Self.sampleRate, heldFor: hold)
                    worst = max(worst, abs(played - drawn))
                }
                #expect(worst < 0.02, "\(envelope) held \(hold)s drifted by \(worst)")
            }
        }
    }

    // MARK: Filter

    @Test func theCutoffIsWhereItWasAskedFor() {
        // At the cutoff a lowpass set to k = sqrt(2) passes 1/k of the signal,
        // which is the half-power point the number is supposed to name.
        let cutoff = 1000.0
        let resonance = (2 - 2.0.squareRoot()) / 2      // k = sqrt(2)

        let atCutoff = filterGain(inputHz: cutoff, cutoff: cutoff, resonance: resonance)
        #expect(abs(atCutoff - 1 / 2.0.squareRoot()) < 0.02)

        // Well below it the signal comes through untouched, and an octave above
        // it is down by about four (a two-pole rolloff).
        let wellBelow = filterGain(inputHz: cutoff / 16, cutoff: cutoff, resonance: resonance)
        #expect(abs(wellBelow - 1) < 0.02)
        let octaveAbove = filterGain(inputHz: cutoff * 2, cutoff: cutoff, resonance: resonance)
        #expect(octaveAbove < 0.3 && octaveAbove > 0.2)
    }

    @Test func resonanceLiftsTheCutoffAndOnlyTheCutoff() {
        let cutoff = 1000.0
        let quiet = filterGain(inputHz: cutoff, cutoff: cutoff, resonance: 0.2)
        let loud = filterGain(inputHz: cutoff, cutoff: cutoff, resonance: 0.9)
        #expect(loud > quiet * 3)

        // Far below the cutoff the two agree: resonance is a peak, not a gain.
        let quietLow = filterGain(inputHz: 50, cutoff: cutoff, resonance: 0.2)
        let loudLow = filterGain(inputHz: 50, cutoff: cutoff, resonance: 0.9)
        #expect(abs(loudLow - quietLow) < 0.05)
    }

    @Test func theFilterStaysStableWhileTheCutoffSweeps() {
        // The reason for integrating the circuit rather than folding a static
        // answer: a cutoff that moves every sample must not blow up.
        var filter = StateVariableFilter()
        var oscillator = Oscillator(seed: 1)
        var peak = 0.0
        let frames = Int(Self.sampleRate)
        for frame in 0..<frames {
            let sweep = 100 * pow(2, 7 * Double(frame) / Double(frames))   // 100 Hz to 12.8 kHz
            filter.setCoefficients(cutoff: sweep, resonance: 0.9, sampleRate: Self.sampleRate)
            let sample = oscillator.next(.sawtooth, increment: 220 / Self.sampleRate)
            peak = max(peak, abs(filter.next(sample, mode: .lowpass)))
        }
        #expect(peak.isFinite && peak < 8)
    }

    /// Steady-state gain of a lowpass fed a sine.
    private func filterGain(inputHz: Double, cutoff: Double, resonance: Double) -> Double {
        var filter = StateVariableFilter()
        filter.setCoefficients(cutoff: cutoff, resonance: resonance, sampleRate: Self.sampleRate)
        let total = Int(Self.sampleRate * 0.5)
        let settle = total / 2
        var peak = 0.0
        for frame in 0..<total {
            let input = sin(2 * .pi * inputHz * Double(frame) / Self.sampleRate)
            let output = filter.next(input, mode: .lowpass)
            if frame >= settle { peak = max(peak, abs(output)) }
        }
        return peak
    }

    // MARK: Oscillator

    @Test func correctedWavesFoldFarLessEnergyBackDownTheSpectrum() {
        // A sawtooth at 3 kHz has harmonics every 3 kHz. The ones past Nyquist
        // fold back to 2100, 5100, 8100 and so on, none of which is a multiple
        // of 3000, so 2100 Hz hears only the aliasing and nothing real.
        let f0 = 3000.0
        let frames = 1 << 15

        var corrected = Oscillator(seed: 1)
        var correctedSamples = [Double]()
        var naiveSamples = [Double]()
        correctedSamples.reserveCapacity(frames)
        naiveSamples.reserveCapacity(frames)

        var phase = 0.0
        let increment = f0 / Self.sampleRate
        for _ in 0..<frames {
            correctedSamples.append(corrected.next(.sawtooth, increment: increment))
            naiveSamples.append(2 * phase - 1)
            phase += increment
            if phase >= 1 { phase -= 1 }
        }

        let correctedAlias = magnitude(of: correctedSamples, atHz: 2100, sampleRate: Self.sampleRate)
        let naiveAlias = magnitude(of: naiveSamples, atHz: 2100, sampleRate: Self.sampleRate)
        #expect(correctedAlias < naiveAlias / 10)

        // And the wave itself is still there: the fundamental is untouched.
        let correctedFundamental = magnitude(of: correctedSamples, atHz: f0, sampleRate: Self.sampleRate)
        let naiveFundamental = magnitude(of: naiveSamples, atHz: f0, sampleRate: Self.sampleRate)
        #expect(abs(correctedFundamental - naiveFundamental) < naiveFundamental * 0.1)
    }

    @Test func everyWaveStaysInsideTheRangeItIsAllowed() {
        // The triangle is the one worth checking: it is integrated rather than
        // drawn, so its level is a consequence of the integrator's gain rather
        // than something written down.
        for waveform in Waveform.allCases {
            for hz in [55.0, 220.0, 880.0, 3520.0] {
                var oscillator = Oscillator(seed: 7)
                var peak = 0.0
                let frames = Int(Self.sampleRate * 0.2)
                for _ in 0..<frames {
                    peak = max(peak, abs(oscillator.next(waveform, increment: hz / Self.sampleRate)))
                }
                #expect(peak <= 1.10, "\(waveform) at \(hz) Hz peaked at \(peak)")
                if waveform != .noise {
                    #expect(peak > 0.80, "\(waveform) at \(hz) Hz only reached \(peak)")
                }
            }
        }
    }

    @Test func aResetOscillatorRepeatsItself() {
        var oscillator = Oscillator(seed: 3)
        let first = (0..<64).map { _ in oscillator.next(.sawtooth, increment: 0.01) }
        oscillator.reset()
        let second = (0..<64).map { _ in oscillator.next(.sawtooth, increment: 0.01) }
        #expect(first == second)
    }

    // MARK: The renderer

    @Test func aNoteWithALengthEndsByItself() {
        let events = EventRing()
        let renderer = SynthRenderer(
            voice: Voice(envelope: Envelope(attack: 0.001, decay: 0.05, sustain: 0.8, release: 0.05)),
            polyphony: 4, sampleRate: Self.sampleRate, events: events
        )
        events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 1, durationSamples: Int(0.1 * Self.sampleRate)))

        let early = render(renderer, seconds: 0.05)
        #expect(peak(early) > 0.05)

        _ = render(renderer, seconds: 0.3)
        let after = render(renderer, seconds: 0.1)
        #expect(peak(after) < 1e-4)
        #expect(renderer.activeVoiceCount == 0)
    }

    @Test func aHeldNoteKeepsSoundingUntilItIsLetGo() {
        let events = EventRing()
        let renderer = SynthRenderer(
            voice: Voice(envelope: Envelope(attack: 0.001, decay: 0.05, sustain: 0.8, release: 0.05)),
            polyphony: 4, sampleRate: Self.sampleRate, events: events
        )
        events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 1))

        _ = render(renderer, seconds: 0.5)
        #expect(peak(render(renderer, seconds: 0.1)) > 0.05)

        events.push(SynthEvent(kind: .noteOff, pitch: 60))
        _ = render(renderer, seconds: 0.3)
        #expect(peak(render(renderer, seconds: 0.1)) < 1e-4)
    }

    @Test func theSameNotesRenderTheSameSamplesEveryTime() {
        // Nothing here may read a clock or the sketch's randomness, noise
        // included, or an offline render could not reproduce a performance.
        func run() -> [Float] {
            let events = EventRing()
            let renderer = SynthRenderer(
                voice: .breath, polyphony: 8, sampleRate: Self.sampleRate, events: events
            )
            events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 1, durationSamples: 4410))
            events.push(SynthEvent(kind: .noteOn, pitch: 67, velocity: 0.6, durationSamples: 8820))
            return render(renderer, seconds: 0.5)
        }
        #expect(run() == run())
    }

    @Test func aChordSurvivesAMelodyPlayedOverIt() {
        // Voices run out, and which note is taken decides whether a held chord
        // stays intact: a note already fading is taken before a held one. The
        // claim is about what is still audible, so it is measured by listening
        // for the chord's own pitch rather than by counting voices.
        func chordStrength(melodyHeld: Bool) -> Double {
            let events = EventRing()
            let renderer = SynthRenderer(
                voice: Voice(waveform: .sine,
                             envelope: Envelope(attack: 0.001, decay: 0.1, sustain: 0.7, release: 0.2)),
                polyphony: 4, sampleRate: Self.sampleRate, events: events
            )
            for pitch in [60.0, 64, 67] {
                events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 0.8))
            }
            _ = render(renderer, seconds: 0.2)

            // Eight notes over the top, through the one voice left over.
            for pitch in stride(from: 72.0, to: 80.0, by: 1.0) {
                events.push(SynthEvent(
                    kind: .noteOn, pitch: pitch, velocity: 0.8,
                    durationSamples: melodyHeld ? 0 : 2205
                ))
                _ = render(renderer, seconds: 0.06)
            }
            _ = render(renderer, seconds: 0.4)

            let tail = render(renderer, seconds: 0.3).map(Double.init)
            return magnitude(of: tail, atHz: Pitch(60).frequency, sampleRate: Self.sampleRate)
        }

        // Short notes give their voice back, so the chord is untouched.
        let survived = chordStrength(melodyHeld: false)
        #expect(survived > 0.02)

        // Held ones cannot: eight of them into one spare voice must eventually
        // take the chord, which is what makes the first measurement mean something.
        let eaten = chordStrength(melodyHeld: true)
        #expect(eaten < survived / 5)
    }

    @Test func takingAVoiceForANewNoteDoesNotClick() {
        // A voice cut dead mid-cycle is a step in the output, which is heard as
        // a click. Its counterfactual is the same run with room to spare.
        func maximumStep(polyphony: Int) -> Float {
            let events = EventRing()
            let renderer = SynthRenderer(
                voice: Voice(waveform: .sawtooth,
                             envelope: Envelope(attack: 0.001, decay: 0.5, sustain: 0.9, release: 0.5)),
                polyphony: polyphony, sampleRate: Self.sampleRate, events: events
            )
            var samples = [Float]()
            for (index, pitch) in stride(from: 48.0, to: 72.0, by: 1.0).enumerated() {
                events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 0.9))
                samples += render(renderer, seconds: index == 0 ? 0.05 : 0.02)
            }
            var step: Float = 0
            for index in 1..<samples.count {
                step = max(step, abs(samples[index] - samples[index - 1]))
            }
            return step
        }

        let crowded = maximumStep(polyphony: 4)      // every note steals one
        let roomy = maximumStep(polyphony: 32)       // none of them do
        // Stealing is allowed to cost something, but not a jump of its own: a
        // sawtooth's own edge is the biggest step either run should contain.
        #expect(crowded < roomy * 1.5)
    }

    @Test func velocityAndGainScaleTheOutput() {
        func peakFor(velocity: Double, gain: Double) -> Float {
            let events = EventRing()
            let renderer = SynthRenderer(
                voice: Voice(waveform: .sine, envelope: .organ, gain: gain),
                polyphony: 2, sampleRate: Self.sampleRate, events: events
            )
            renderer.gain = 1
            events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: velocity))
            _ = render(renderer, seconds: 0.05)
            return peak(render(renderer, seconds: 0.1))
        }
        let full = peakFor(velocity: 1, gain: 1)
        let half = peakFor(velocity: 0.5, gain: 1)
        #expect(abs(Double(half / full) - 0.5) < 0.05)
        let quiet = peakFor(velocity: 1, gain: 0.25)
        #expect(abs(Double(quiet / full) - 0.25) < 0.05)
    }

    @Test func theSoftClipLeavesOrdinaryLevelsAlone() {
        for x in stride(from: -0.8, through: 0.8, by: 0.05) {
            #expect(softClip(x) == x)
        }
        // And holds a stacked chord inside what the speakers can take.
        #expect(softClip(4) < 1)
        #expect(softClip(-4) > -1)
        #expect(softClip(0.9) > 0.8 && softClip(0.9) < 1)
    }

    @Test func theEventRingCarriesEventsInOrderAndDropsRatherThanWaits() {
        let ring = EventRing(capacity: 4)
        #expect(ring.pop() == nil)
        for pitch in [60.0, 61, 62] {
            #expect(ring.push(SynthEvent(kind: .noteOn, pitch: pitch)))
        }
        // One slot is always left open so full and empty cannot look alike.
        #expect(!ring.push(SynthEvent(kind: .noteOn, pitch: 63)))
        #expect(ring.pop()?.pitch == 60)
        #expect(ring.pop()?.pitch == 61)
        #expect(ring.pop()?.pitch == 62)
        #expect(ring.pop() == nil)
    }

    // MARK: Helpers

    private func render(_ renderer: SynthRenderer, seconds: Double) -> [Float] {
        let frames = Int(seconds * Self.sampleRate)
        var samples = [Float](repeating: 0, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            // Rendered in blocks, the way the engine would ask for it.
            var offset = 0
            while offset < frames {
                let count = min(512, frames - offset)
                let slice = UnsafeMutableBufferPointer(
                    start: buffer.baseAddress! + offset, count: count
                )
                renderer.render(into: slice, frameCount: count)
                offset += count
            }
        }
        return samples
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// The strength of one frequency in a signal, by correlating against it.
    private func magnitude(of samples: [Double], atHz hz: Double, sampleRate: Double) -> Double {
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let angle = 2 * .pi * hz * Double(index) / sampleRate
            real += sample * cos(angle)
            imaginary += sample * sin(angle)
        }
        return 2 * (real * real + imaginary * imaginary).squareRoot() / Double(samples.count)
    }
}
