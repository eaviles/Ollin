import Accelerate
import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The two effects that work in the spectrum, and the stretch beside them.
/// The laws are the ones that make a phase vocoder honest rather than a
/// smear: a shift of nothing is the sound itself, sample for sample; a
/// shifted tone lands exactly where the ratio says at the level it had; a
/// harmonizer keeps the original under the moved copy; the two sides move on
/// their own; a freeze holds the instant it caught after the sound is gone,
/// passes the sound through at nothing, and follows it again when let go; a
/// stretch of one is the recording itself, and any other keeps the pitch
/// and changes the length. Plus the two the chain owes: a setting turned in
/// flight rides the standing frames, and the export path carries the work.
@Suite(.serialized) struct SpectralTests {

    // MARK: - Helpers

    private let rate = 48000.0

    /// Runs one of these over a stereo signal the way the chain would, block
    /// by block, and returns both sides.
    private func run(_ effect: SpectralEffect, left: [Float], right: [Float],
                     blocks: [Int] = [512],
                     change: (Int, SpectralEffect) -> Void = { _, _ in })
    -> (left: [Float], right: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: effect.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var outLeft = [Float](), outRight = [Float]()
        var position = 0
        var turn = 0
        while position < left.count {
            change(position, effect)
            let count = min(blocks[turn % blocks.count], left.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for index in 0..<count {
                data[0][index] = left[position + index]
                data[1][index] = right[position + index]
            }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let block = AudioBlock(list: list, frameCount: count, sampleRate: effect.sampleRate,
                                   time: Double(position) / effect.sampleRate)
            effect.process(block)
            outLeft += Array(UnsafeBufferPointer(start: data[0], count: count))
            outRight += Array(UnsafeBufferPointer(start: data[1], count: count))
            position += count
            turn += 1
        }
        return (outLeft, outRight)
    }

    /// A sine at a level given in decibels below full scale.
    private func sine(_ frequency: Double, seconds: Double, level: Double = -6) -> [Float] {
        let amplitude = pow(10, level / 20)
        return (0..<Int(seconds * rate)).map {
            Float(amplitude * sin(2 * .pi * frequency * Double($0) / rate))
        }
    }

    /// A struck note: two partials that fade at their own rates.
    private func note(_ frequency: Double, seconds: Double) -> [Float] {
        (0..<Int(seconds * rate)).map {
            let t = Double($0) / rate
            let low = exp(-t * 1.5) * sin(2 * .pi * frequency * t)
            let high = 0.4 * exp(-t * 4) * sin(2 * .pi * frequency * 2.76 * t + 0.7)
            return Float(0.5 * (low + high))
        }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    private func decibels(_ samples: ArraySlice<Float>) -> Double {
        20 * log10(max(rms(samples), 1e-12))
    }

    /// The magnitude spectrum of a stretch of signal, Hann windowed, over the
    /// largest power of two that fits: one value per bin, `rate / n` apart.
    private func spectrum(_ samples: ArraySlice<Float>, rate: Double? = nil) -> (magnitudes: [Float], binWidth: Double) {
        let rate = rate ?? self.rate
        let n = 1 << Int(log2(Double(samples.count)))
        let half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        let start = samples.startIndex
        for index in 0..<n {
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(n))
            windowed[index] = Float(Double(samples[start + index]) * window)
        }
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        let log2n = vDSP_Length(log2(Double(n)))
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { win in
                    win.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        magnitudes[0] = 0
        return (magnitudes, rate / Double(n))
    }

    /// Where the loudest bin sits, in Hz, refined between bins by the
    /// parabola through it and its neighbors.
    private func peakFrequency(_ samples: ArraySlice<Float>, rate: Double? = nil) -> Double {
        let (magnitudes, width) = spectrum(samples, rate: rate)
        var best = 1
        for k in 2..<(magnitudes.count - 1) where magnitudes[k] > magnitudes[best] { best = k }
        let a = log(Double(max(magnitudes[best - 1], 1e-12)))
        let b = log(Double(max(magnitudes[best], 1e-12)))
        let c = log(Double(max(magnitudes[best + 1], 1e-12)))
        let denominator = a - 2 * b + c
        let offset = abs(denominator) > 1e-12 ? 0.5 * (a - c) / denominator : 0
        return (Double(best) + offset) * width
    }

    /// How loud a stretch of signal is at one frequency, relative to its
    /// loudest bin: 1 at the peak, 0 where there is nothing.
    private func relativeLevel(at frequency: Double, in samples: ArraySlice<Float>) -> Double {
        let (magnitudes, width) = spectrum(samples)
        let bin = Int((frequency / width).rounded())
        let near = magnitudes[max(1, bin - 1)...min(magnitudes.count - 1, bin + 1)].max() ?? 0
        return Double(near) / Double(magnitudes.max() ?? 1)
    }

    private func shift(_ semitones: Double, mix: Double = 1) -> SpectralEffect {
        SpectralEffect(.pitchShift(PitchShift(semitones: semitones, mix: mix)), sampleRate: rate)
    }

    private func freeze(_ amount: Double) -> SpectralEffect {
        SpectralEffect(.freeze(Freeze(amount: amount)), sampleRate: rate)
    }

    // MARK: - The values

    @Test func theKindsAndTheirValuesRoundTrip() throws {
        let effects: [Effect] = [
            .pitchShift(PitchShift(semitones: 7, mix: 0.5)),
            .freeze(Freeze(amount: 0.3)),
        ]
        #expect(effects.map(\.kind) == [.pitchShift, .freeze])
        let data = try JSONEncoder().encode(effects)
        let back = try JSONDecoder().decode([Effect].self, from: data)
        #expect(back == effects, "the settings survive a round trip")
        // Out-of-range settings are pulled into range rather than trusted.
        #expect(PitchShift(semitones: 40).semitones == 24)
        #expect(PitchShift(semitones: -40).semitones == -24)
        #expect(PitchShift(mix: 3).mix == 1)
        #expect(Freeze(amount: -1).amount == 0)
        #expect(Freeze(amount: 2).amount == 1)
        #expect(abs(PitchShift(semitones: 12).ratio - 2) < 1e-12)
    }

    // MARK: - The pitch shift

    @Test func aShiftOfNothingIsTheSoundItself() {
        // A note with two partials fading, which is not a steady state: the
        // frames read it, carry its phases on by exactly what they moved, and
        // put it back, one frame later than it went in.
        let input = note(220, seconds: 1.0)
        let effect = shift(0)
        let out = run(effect, left: input, right: input, blocks: [512, 100, 3, 1024])
        let latency = effect.latency
        #expect(latency == 2048, "one frame late at this rate")
        var worst: Float = 0
        for index in 0..<(input.count - latency) {
            worst = max(worst, abs(out.left[index + latency] - input[index]))
        }
        #expect(worst < 2e-3, "the sound comes back as it went in: worst \(worst)")
        #expect(out.left[0..<latency].allSatisfy { $0 == 0 }, "nothing before the first frame is ready")
    }

    @Test func aShiftedToneLandsWhereTheRatioSaysItShould() {
        let tone = sine(440, seconds: 1.5)
        let held = Int(rate * 0.5)...
        for semitones in [12.0, -12.0, 7.0, 3.5, -5.0] {
            let expected = 440 * pow(2, semitones / 12)
            let out = run(shift(semitones), left: tone, right: tone)
            let found = peakFrequency(out.left[held])
            #expect(abs(found - expected) < expected * 0.005,
                    "\(semitones) semitones puts 440 at \(found), not \(expected)")
        }
    }

    @Test func theLevelSurvivesTheShift() {
        // The shape of each partial is carried whole to its new place, so the
        // level is kept to within the small loss the fraction of a bin costs.
        let tone = sine(440, seconds: 1.5)
        let held = Int(rate * 0.5)...
        let before = decibels(tone[held])
        for semitones in [12.0, -12.0, 5.0] {
            let out = run(shift(semitones), left: tone, right: tone)
            let after = decibels(out.left[held])
            #expect(abs(after - before) < 1.5, "\(semitones) semitones: \(after) dB against \(before)")
        }
    }

    @Test func aHarmonizerKeepsTheOriginalUnderneath() {
        let tone = sine(440, seconds: 1.5)
        let held = Int(rate * 0.5)...
        let out = run(shift(7, mix: 0.5), left: tone, right: tone)
        let original = relativeLevel(at: 440, in: out.left[held])
        let fifth = relativeLevel(at: 440 * pow(2, 7.0 / 12), in: out.left[held])
        #expect(original > 0.6 && fifth > 0.6, "both voices sound: \(original) and \(fifth)")
        #expect(relativeLevel(at: 1000, in: out.left[held]) < 0.05, "and nothing else does")
    }

    @Test func theTwoSidesShiftOnTheirOwn() {
        let left = sine(440, seconds: 1.5), right = sine(660, seconds: 1.5)
        let held = Int(rate * 0.5)...
        let out = run(shift(12), left: left, right: right)
        #expect(abs(peakFrequency(out.left[held]) - 880) < 4)
        #expect(abs(peakFrequency(out.right[held]) - 1320) < 6)
    }

    @Test func aSettingTurnedInFlightRidesTheStandingFrames() {
        // Up an octave halfway through. The pitch is at the new place soon
        // after, and the level never drops out on the way, which is only true
        // if the frames in flight and the phases behind them were kept.
        let tone = sine(440, seconds: 1.6)
        let effect = shift(0)
        let out = run(effect, left: tone, right: tone, blocks: [256]) { position, effect in
            if position >= Int(rate * 0.8) {
                effect.update(.pitchShift(PitchShift(semitones: 12)))
            }
        }
        #expect(abs(peakFrequency(out.left[Int(rate * 0.4)..<Int(rate * 0.75)]) - 440) < 3)
        #expect(abs(peakFrequency(out.left[Int(rate * 1.1)...]) - 880) < 4)
        let steady = rms(out.left[Int(rate * 0.4)..<Int(rate * 0.75)])
        let window = Int(rate * 0.02)
        var start = Int(rate * 0.2)
        var quietest = Double.infinity
        while start + window <= out.left.count {
            quietest = min(quietest, rms(out.left[start..<(start + window)]))
            start += window
        }
        #expect(quietest > steady * 0.5, "no dropout on the way: \(quietest) against \(steady)")
    }

    // MARK: - The freeze

    @Test func aFreezeHoldsTheInstantAfterTheSoundHasGone() {
        // A tone for six tenths of a second, then nothing. Frozen at four
        // tenths, the tone is still there a second after the input went
        // silent, at the frequency and the level it had.
        let input = sine(440, seconds: 0.6) + [Float](repeating: 0, count: Int(rate * 1.4))
        let effect = freeze(0)
        let out = run(effect, left: input, right: input, blocks: [480]) { position, effect in
            if position >= Int(rate * 0.4) { effect.update(.freeze(Freeze(amount: 1))) }
        }
        let late = Int(rate * 1.5)..<Int(rate * 1.9)
        #expect(abs(peakFrequency(out.left[late]) - 440) < 3, "the held tone is the tone")
        #expect(abs(decibels(out.left[late]) - decibels(input[Int(rate * 0.1)..<Int(rate * 0.5)])) < 1.5,
                "at the level it had: \(decibels(out.left[late]))")
        #expect(effect.isHolding)
        // Before the freeze the sound passed through, one frame late.
        let latency = effect.latency
        var worst: Float = 0
        for index in 0..<(Int(rate * 0.4) - latency) {
            worst = max(worst, abs(out.left[index + latency] - input[index]))
        }
        #expect(worst < 1e-5, "until then it passed as it was: \(worst)")
    }

    @Test func aFreezeAtNothingPassesTheSoundThrough() {
        let input = note(330, seconds: 0.8)
        let effect = freeze(0)
        let out = run(effect, left: input, right: input, blocks: [512, 37])
        let latency = effect.latency
        var worst: Float = 0
        for index in 0..<(input.count - latency) {
            worst = max(worst, abs(out.left[index + latency] - input[index]))
        }
        #expect(worst < 1e-5, "nothing held, nothing changed: \(worst)")
        #expect(!effect.isHolding)
    }

    @Test func aFreezeLetGoFollowsTheSoundAgain() {
        // Held from three tenths to eight, then let go; the input moves to a
        // new note at one second, and the output is that note, exactly.
        let input = sine(440, seconds: 1.0) + sine(660, seconds: 1.0)
        let effect = freeze(0)
        let out = run(effect, left: input, right: input, blocks: [512]) { position, effect in
            let seconds = Double(position) / rate
            effect.update(.freeze(Freeze(amount: seconds >= 0.3 && seconds < 0.8 ? 1 : 0)))
        }
        let late = Int(rate * 1.5)..<Int(rate * 1.9)
        #expect(abs(peakFrequency(out.left[late]) - 660) < 3)
        #expect(!effect.isHolding)
        let latency = effect.latency
        var worst: Float = 0
        for index in Int(rate * 1.2)..<(input.count - latency) {
            worst = max(worst, abs(out.left[index + latency] - input[index]))
        }
        #expect(worst < 1e-5, "let go, it is the live sound again: \(worst)")
        // And while it was held, it was the first note, not the silence
        // between blocks or a mixture.
        let during = Int(rate * 0.5)..<Int(rate * 0.75)
        #expect(abs(peakFrequency(out.left[during]) - 440) < 3)
    }

    // MARK: - The stretch

    @Test func aStretchOfOneIsTheRecordingItself() {
        let frames = note(220, seconds: 0.5)
        let recording = SampledInstrument.Recording(frames: frames, sampleRate: rate, rootKey: 57)
        let same = recording.stretched(by: 1)
        #expect(same.frames.count == frames.count)
        #expect(same.rootKey == 57 && same.sampleRate == rate)
        var worst: Float = 0
        for index in frames.indices { worst = max(worst, abs(same.frames[index] - frames[index])) }
        #expect(worst < 1e-4, "a stretch of one changes nothing: \(worst)")
    }

    @Test func aStretchKeepsThePitchAndChangesTheLength() {
        let tone = sine(440, seconds: 0.5)
        let recording = SampledInstrument.Recording(frames: tone, sampleRate: rate, rootKey: 69)
        for factor in [2.0, 0.5, 3.0] {
            let stretched = recording.stretched(by: factor)
            let expected = Int((Double(tone.count) * factor).rounded())
            #expect(stretched.frames.count == expected, "\(factor) times as long: \(stretched.frames.count)")
            let middle = stretched.frames.count / 4..<(stretched.frames.count * 3 / 4)
            let found = peakFrequency(stretched.frames[middle])
            #expect(abs(found - 440) < 2, "and at the same pitch: \(found) at \(factor)")
            let level = decibels(stretched.frames[middle])
            #expect(abs(level - decibels(tone[tone.count / 4..<(tone.count * 3 / 4)])) < 1,
                    "and the same level: \(level) at \(factor)")
        }
    }

    @Test func aStretchedRoomIsLongerAtTheSamePitch() {
        let room = ImpulseResponse(seconds: 0.5, sampleRate: rate) { t, _ in exp(-4 * t) * sin(2 * .pi * 300 * t) }
        let bigger = room.stretched(by: 3)
        #expect(bigger.channelCount == 2)
        #expect(abs(bigger.duration - 1.5) < 0.001)
        let early = 0..<Int(rate * 0.5)
        #expect(abs(peakFrequency(bigger.channels[0][early]) - 300) < 3)
        // Rung three times as long: the same level a third of the way in as
        // the original had at its own third.
        let original = decibels(room.channels[0][Int(rate * 0.1)..<Int(rate * 0.15)])
        let slowed = decibels(bigger.channels[0][Int(rate * 0.3)..<Int(rate * 0.45)])
        #expect(abs(original - slowed) < 1.5, "\(slowed) against \(original)")
        // And a room past the limit is cut there.
        let long = ImpulseResponse.decay(seconds: 8, sampleRate: 8000).stretched(by: 4)
        #expect(abs(long.duration - ImpulseResponse.maxSeconds) < 0.001)
    }

    // MARK: - The chain

    @MainActor
    @Test func bothKindsWireInAChain() {
        let synth = Synth(.pluck)
        synth.effects = [
            .pitchShift(PitchShift(semitones: 7, mix: 0.5)),
            .freeze(Freeze(amount: 0)),
            .reverb(Reverb(.hall)),
        ]
        #expect(synth.effects.map(\.kind) == [.pitchShift, .freeze, .reverb])
        // A turn of a setting keeps the same wiring.
        synth.effects[0] = .pitchShift(PitchShift(semitones: 12))
        #expect(synth.effects.map(\.kind) == [.pitchShift, .freeze, .reverb])
    }

    @MainActor
    @Test func theExportPathCarriesTheWork() {
        // A held sine through the export, plain and an octave up: the second
        // file's peak sits at twice the first's, which it cannot unless the
        // chain built for the export carries the same work the speakers would.
        func rendered(_ effects: [Effect]) -> [Float] {
            let synth = Synth(.sine, polyphony: 2)
            synth.gain = 0.6
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            defer { OllinApp.isRenderingHeadless = false }
            synth.play(Pitch(69), velocity: 1, for: 1.6)
            var elapsed = 0.0
            while elapsed < 1.6 {
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            let stereo = synth.renderExportAudio(upTo: 1.6, sampleRate: 44100)
            return stride(from: 0, to: stereo.count, by: 2).map { stereo[$0] }
        }
        let plain = rendered([])
        let octave = rendered([.pitchShift(PitchShift(semitones: 12))])
        #expect(plain.count > 44100)
        let window = 22050..<min(plain.count, octave.count, 66150)
        let low = peakFrequency(plain[window], rate: 44100)
        let high = peakFrequency(octave[window], rate: 44100)
        #expect(abs(low - 440) < 4, "the plain export sits at A: \(low)")
        #expect(abs(high - 880) < 8, "and the shifted one an octave up: \(high)")
    }
}
