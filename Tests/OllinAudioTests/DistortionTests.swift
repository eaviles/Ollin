import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The five characters of the distortion, each held to its name by what a
/// tone through it comes out as: a soft clip adds odd harmonics and nothing
/// else, an overdrive adds the even ones too, a bit crush comes out on a
/// staircase held for several samples, a ring replaces a tone by the two
/// either side of it, and a squeeze lets a band through. None of them delays
/// the sound or leaves anything sounding after it.
///
/// Until 2026-11-11 each was a preset of the system's distortion unit, and
/// measured with a tone none did what its name says: the soft clip was an
/// echo 357 ms behind, the overdrive sounded the octave above three times
/// louder than the note, the bit crush was a ring at 90 Hz with a 28 ms
/// slap, the ring was a polynomial with no ring in it, and the squeeze was
/// the ring.
@Suite(.serialized) struct DistortionTests {

    private let rate = 44100.0

    // MARK: - Helpers

    /// Runs a distortion over a signal the way the chain would, in blocks of
    /// 512, both sides fed the same, and returns the left.
    private func run(_ distortion: Distortion, _ signal: [Float], rate: Double? = nil) -> [Float] {
        let effect = DistortionEffect(distortion, sampleRate: rate ?? self.rate)
        let format = AVAudioFormat(standardFormatWithSampleRate: effect.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        var out = [Float]()
        out.reserveCapacity(signal.count)
        var position = 0
        while position < signal.count {
            let count = min(512, signal.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for index in 0..<count {
                data[0][index] = signal[position + index]
                data[1][index] = signal[position + index]
            }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            effect.process(AudioBlock(list: list, frameCount: count, sampleRate: effect.sampleRate,
                                      time: Double(position) / effect.sampleRate))
            out += UnsafeBufferPointer(start: data[0], count: count)
            position += count
        }
        return out
    }

    private func tone(_ hz: Double, level: Double, seconds: Double = 1) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(level * sin(2 * .pi * hz * Double($0) / rate)) }
    }

    /// The level of one frequency in a slice, as the height of a sine there.
    private func line(_ samples: ArraySlice<Float>, hz: Double) -> Double {
        var re = 0.0, im = 0.0
        let w = 2 * Double.pi * hz / rate
        var n = 0.0
        for value in samples {
            re += Double(value) * cos(w * n)
            im -= Double(value) * sin(w * n)
            n += 1
        }
        return (re * re + im * im).squareRoot() / (Double(samples.count) / 2)
    }

    /// The end of a signal, past anything a start leaves: as many whole
    /// periods of `hz` as fit in its second half, so a line reads as itself
    /// and a wave's mean is its own. `hz` has to divide the rate.
    private func settled(_ samples: [Float], periodsOf hz: Double) -> ArraySlice<Float> {
        let period = Int((rate / hz).rounded())
        let count = (samples.count / 2) / period * period
        return samples[(samples.count - count)...]
    }

    /// The harmonics of a 441 Hz tone through a character, first to eighth,
    /// as heights. 441 divides the rate, so a half-second slice holds whole
    /// periods and one harmonic never reads as another.
    private func harmonics(_ distortion: Distortion, level: Double = 0.8) -> [Double] {
        let out = settled(run(distortion, tone(441, level: level)), periodsOf: 441)
        return (1...8).map { line(out, hz: 441 * Double($0)) }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))).squareRoot()
    }

    private func click(seconds: Double = 0.5) -> [Float] {
        var signal = [Float](repeating: 0, count: Int(seconds * rate))
        signal[100] = 1
        return signal
    }

    // MARK: - The soft clip

    /// A soft clip rounds the peaks the same way above and below: the odd
    /// harmonics come up, the even ones stay out, and no other frequency
    /// appears, so the whole of the output is the tone and its harmonics.
    @Test func aSoftClipAddsOnlyOddHarmonics() {
        let h = harmonics(Distortion(.softClip, drive: -6, mix: 1))
        #expect(h[0] > 0.5, "the tone itself is \(h[0])")
        #expect(h[2] > 0.01 * h[0], "the third harmonic is \(h[2]) against \(h[0])")
        #expect(h[4] > 0.0005 * h[0], "the fifth harmonic is \(h[4])")
        #expect(h[1] < 1e-5 && h[3] < 1e-5 && h[5] < 1e-5, "even harmonics \(h[1]), \(h[3]), \(h[5])")

        // Nothing but the harmonics: their power is the output's power.
        let out = settled(run(Distortion(.softClip, drive: -6, mix: 1), tone(441, level: 0.8)), periodsOf: 441)
        var inHarmonics = 0.0
        for k in 1...24 { let level = line(out, hz: 441 * Double(k)); inHarmonics += level * level / 2 }
        let total = rms(out) * rms(out)
        #expect(abs(inHarmonics - total) < 1e-4 * total, "\(total - inHarmonics) of \(total) lies off the harmonics")
    }

    /// A soft clip is a curve, with no memory: a click comes out on the
    /// sample it went in on and nowhere else, and full scale stays full
    /// scale while everything under it comes up.
    @Test func aSoftClipHasNoMemoryAndKeepsFullScale() {
        let out = run(Distortion(.softClip, drive: 0, mix: 1), click())
        #expect(out.indices.filter { out[$0] != 0 } == [100])
        #expect(abs(out[100] - 1) < 1e-6)

        for drive in [-20.0, -6, 0, 12, 20] {
            let gain = DistortionCurve.gain(.softClip, drive: drive)
            #expect(abs(DistortionCurve.soft(1, gain: gain) - 1) < 1e-12)
            #expect(abs(DistortionCurve.soft(-1, gain: gain) + 1) < 1e-12)
            var last = -1.0
            for step in 0...200 {
                let x = -1 + Double(step) / 100
                let y = DistortionCurve.soft(x, gain: gain)
                #expect(abs(y) >= abs(x) - 1e-12 && abs(y) <= 1 + 1e-12)
                #expect(y >= last)
                last = y
            }
        }
    }

    /// With almost no drive a soft clip is the sound itself, and more drive
    /// is more harmonics, all the way up.
    @Test func moreDriveIsMoreOfIt() {
        let quiet = run(Distortion(.softClip, drive: -80, mix: 1), tone(441, level: 0.8))
        let plain = tone(441, level: 0.8)
        var moved: Float = 0
        for index in plain.indices { moved = max(moved, abs(quiet[index] - plain[index])) }
        #expect(moved < 1e-5, "a soft clip with no drive moved a sample by \(moved)")

        for character in [Distortion.Character.softClip, .overdrive] {
            var last = 0.0
            for drive in [-18.0, -6, 6, 18] {
                let h = harmonics(Distortion(character, drive: drive, mix: 1))
                let added = (h[1...].reduce(0.0) { $0 + $1 * $1 }).squareRoot() / h[0]
                #expect(added > last, "\(character) at \(drive) dB adds \(added), no more than at the drive below")
                last = added
            }
        }
    }

    // MARK: - The overdrive

    /// An overdrive flattens one side before the other, so the even
    /// harmonics a soft clip leaves out are there, beside the odd ones, and
    /// it is the harder of the two: more of the output is harmonics at the
    /// same drive.
    @Test func anOverdriveAddsTheEvenHarmonicsToo() {
        let over = harmonics(Distortion(.overdrive, drive: -6, mix: 1))
        let soft = harmonics(Distortion(.softClip, drive: -6, mix: 1))
        #expect(over[0] > 0.4, "the tone itself is \(over[0])")
        #expect(over[1] > 0.02 * over[0], "the second harmonic is \(over[1]) against \(over[0])")
        #expect(over[2] > 0.02 * over[0], "the third harmonic is \(over[2]) against \(over[0])")
        func added(_ h: [Double]) -> Double { (h[1...].reduce(0.0) { $0 + $1 * $1 }).squareRoot() / h[0] }
        #expect(added(over) > 1.5 * added(soft), "overdrive adds \(added(over)), the soft clip \(added(soft))")
    }

    /// One side flattening first would leave the wave standing off center;
    /// the overdrive takes that back out, and holds a full-scale tone within
    /// full scale.
    @Test func anOverdriveHoldsNoOffsetAndStaysInScale() {
        for drive in [-6.0, 6, 20] {
            let out = settled(run(Distortion(.overdrive, drive: drive, mix: 1), tone(441, level: 1)), periodsOf: 441)
            let mean = out.reduce(0.0) { $0 + Double($1) } / Double(out.count)
            #expect(abs(mean) < 1e-3, "an overdrive at \(drive) dB holds an offset of \(mean)")
            let most = out.map { abs($0) }.max() ?? 0
            #expect(most <= 1.25, "an overdrive at \(drive) dB let a full-scale tone out at \(most)")
        }
        // The curve itself: its far side reaches full scale and no further.
        for drive in [-30.0, -6, 0, 20] {
            let gain = DistortionCurve.gain(.overdrive, drive: drive)
            #expect(abs(DistortionCurve.overdrive(-1, gain: gain) + 1) < 1e-9)
            #expect(DistortionCurve.overdrive(1, gain: gain) <= 1 + 1e-9)
            #expect(DistortionCurve.overdrive(0, gain: gain) == 0)
        }
    }

    // MARK: - The bit crush

    /// A bit crush comes out on a staircase: every sample is a whole number
    /// of steps, the step is a thirty-second of full scale at the default
    /// drive, and each value is held for the samples its rate says, so a
    /// second of sound changes level no more than 11,025 times.
    @Test func aBitCrushComesOutOnAStaircaseAndHolds() {
        let crush = Distortion(.bitCrush, drive: -6, mix: 1)
        let step = DistortionCurve.step(drive: -6)
        #expect(abs(step - 1.0 / 32) < 1e-12)
        #expect(abs(DistortionCurve.holdRate(drive: -6) - 11025) < 1e-9)

        let out = run(crush, tone(441, level: 0.8))
        let offTheStairs = out.filter { value in
            let steps = Double(value) / step
            return abs(steps - steps.rounded()) >= 1e-4
        }
        #expect(offTheStairs.isEmpty, "\(offTheStairs.count) samples are not a whole number of steps of \(step), the first \(offTheStairs.first ?? 0)")
        let levels = Set(out.map { (Double($0) / step).rounded() })
        #expect(levels.count <= 53, "a tone of 0.8 took \(levels.count) levels at a step of \(step)")
        #expect(levels.count >= 10)

        var changes = 0
        var longest = 0, current = 1
        for index in 1..<out.count {
            if out[index] != out[index - 1] { changes += 1; current = 1 } else { current += 1; longest = max(longest, current) }
        }
        #expect(changes <= 11025, "the level changed \(changes) times in a second")
        #expect(changes > 5000)
        // Four samples to a hold at this rate, so no value lasts fewer.
        var shortest = Int.max
        var run = 1
        for index in 1..<out.count {
            if out[index] != out[index - 1] { shortest = min(shortest, run); run = 1 } else { run += 1 }
        }
        #expect(shortest >= 4, "a value was held for only \(shortest) samples")
        #expect(longest >= 4)
    }

    /// More drive is coarser on both counts: six decibels doubles the step,
    /// twelve halve the rate, and a hard-driven crush is a handful of levels.
    @Test func moreDriveIsFewerBitsAndFewerSamples() {
        // Six decibels is a doubling to a quarter of a percent.
        #expect(abs(DistortionCurve.step(drive: 0) / DistortionCurve.step(drive: -6) - 2) < 0.01)
        #expect(abs(DistortionCurve.holdRate(drive: 6) / DistortionCurve.holdRate(drive: -6) - 0.5) < 0.01)
        var lastLevels = Int.max, lastChanges = Int.max
        for drive in [-18.0, -6, 6, 18] {
            let out = run(Distortion(.bitCrush, drive: drive, mix: 1), tone(441, level: 0.8))
            let levels = Set(out).count
            var changes = 0
            for index in 1..<out.count where out[index] != out[index - 1] { changes += 1 }
            #expect(levels < lastLevels, "\(levels) levels at \(drive) dB, \(lastLevels) at the drive below")
            #expect(changes < lastChanges, "\(changes) changes at \(drive) dB, \(lastChanges) at the drive below")
            lastLevels = levels
            lastChanges = changes
        }
        #expect(lastLevels <= 5)
    }

    // MARK: - The ring

    /// A ring replaces a tone by two: one the ring's frequency above it and
    /// one as far below, each at half its height, with nothing left where the
    /// tone was and nothing at the ring's own frequency.
    @Test func aRingReplacesAToneByTheTwoEitherSide() {
        let ring = Distortion.ringFrequency
        #expect(ring == 300)
        // 1,000 Hz and 300 Hz both divide into half a second of samples.
        let out = settled(run(Distortion(.ring, drive: -6, mix: 1), tone(1000, level: 0.5)), periodsOf: 100)
        #expect(abs(line(out, hz: 1000 + ring) - 0.25) < 1e-3, "the upper tone is \(line(out, hz: 1000 + ring))")
        #expect(abs(line(out, hz: 1000 - ring) - 0.25) < 1e-3, "the lower tone is \(line(out, hz: 1000 - ring))")
        #expect(line(out, hz: 1000) < 1e-4, "the tone itself is still there at \(line(out, hz: 1000))")
        #expect(line(out, hz: ring) < 1e-4)
        // And those two are all of it.
        let total = rms(out) * rms(out)
        #expect(abs(total - 2 * 0.25 * 0.25 / 2) < 1e-4, "the output's power is \(total)")
    }

    /// More drive on a ring is the sound louder into it, held within full
    /// scale, so a hard-driven ring is never over full scale either.
    @Test func aRingStaysInScale() {
        for drive in [-6.0, 6, 20] {
            let out = run(Distortion(.ring, drive: drive, mix: 1), tone(441, level: 1))
            #expect((out.map { abs($0) }.max() ?? 0) <= 1.0001)
        }
    }

    // MARK: - The squeeze

    /// A squeeze lets a band through: a tone at its center comes out more
    /// than ten times the height of one three octaves and a half below it or
    /// three octaves above.
    @Test func aSqueezeLetsABandThrough() {
        func through(_ hz: Double) -> Double {
            line(settled(run(Distortion(.squeeze, drive: -20, mix: 1), tone(hz, level: 0.25)), periodsOf: 100), hz: hz)
        }
        let center = through(Distortion.squeezeCenter)
        let below = through(100)
        let above = through(9600)
        #expect(center > 0.1, "a tone at the center comes out at \(center)")
        #expect(center > 10 * below, "center \(center), 100 Hz \(below)")
        #expect(center > 10 * above, "center \(center), 9,600 Hz \(above)")
    }

    /// And what gets through is driven until it flattens: a loud tone at the
    /// center gains its third harmonic, where a quiet one does not.
    @Test func aSqueezeFlattensWhatGetsThrough() {
        func third(_ level: Double) -> Double {
            let out = settled(run(Distortion(.squeeze, drive: 6, mix: 1), tone(1225, level: level)), periodsOf: 1225)
            return line(out, hz: 3675) / line(out, hz: 1225)
        }
        #expect(third(0.8) > 0.02, "a loud tone's third harmonic is \(third(0.8)) of it")
        #expect(third(0.8) > 20 * third(0.001), "loud \(third(0.8)), quiet \(third(0.001))")
        let out = run(Distortion(.squeeze, drive: 20, mix: 1), tone(1225, level: 1))
        #expect((out.map { abs($0) }.max() ?? 0) <= 1.6)
    }

    // MARK: - All five

    /// None of the five delays the sound or leaves anything sounding: 50 ms
    /// after a click the output is silent, and silence in is silence out.
    @Test(arguments: Distortion.Character.allCases)
    func noCharacterEchoesOrRingsOn(character: Distortion.Character) {
        for drive in [-6.0, 12] {
            let out = run(Distortion(character, drive: drive, mix: 1), click())
            let after = out[(100 + Int(0.05 * rate))...]
            #expect((after.map { abs($0) }.max() ?? 0) < 1e-4,
                    "\(character) still sounds \(after.map { abs($0) }.max() ?? 0) 50 ms after a click")
            let silent = run(Distortion(character, drive: drive, mix: 1), [Float](repeating: 0, count: 4096))
            #expect(silent.allSatisfy { $0 == 0 }, "\(character) made a sound out of silence")
        }
    }

    /// At a mix of 0 the sound passes untouched, to the sample; at 1 none of
    /// it is the sound as it came in.
    @Test(arguments: Distortion.Character.allCases)
    func theMixSetsHowMuchIsDriven(character: Distortion.Character) {
        let plain = tone(441, level: 0.6, seconds: 0.25)
        #expect(run(Distortion(character, drive: 6, mix: 0), plain) == plain)
        let half = run(Distortion(character, drive: 6, mix: 0.5), plain)
        let whole = run(Distortion(character, drive: 6, mix: 1), plain)
        var off: Float = 0
        for index in plain.indices { off = max(off, abs(half[index] - (plain[index] + whole[index]) / 2)) }
        #expect(off < 1e-5, "\(character) at half mix is \(off) off half way between")
    }

    /// The settings are bounded, and the character is one of five.
    @Test func theSettingsAreBounded() {
        #expect(Distortion(.softClip, drive: 99).drive == 20)
        #expect(Distortion(.softClip, drive: -500).drive == -80)
        #expect(Distortion(.softClip, mix: 9).mix == 1)
        #expect(Distortion.Character.allCases.count == 5)
    }

    /// The unit keeps its driving across a turn of the drive and a change of
    /// character, so neither restarts what is sounding.
    @MainActor
    @Test func theUnitKeepsItsDrivingAcrossATurn() throws {
        let unit = try #require(Effect.makeUnit(for: .distortion).auAudioUnit as? ClosureAudioUnit)
        unit.setDistortion(Distortion(.softClip), sampleRate: rate)
        let first = try #require(unit.driving)
        unit.setDistortion(Distortion(.ring, drive: 3, mix: 0.8), sampleRate: rate)
        #expect(unit.driving === first)
        #expect(first.current == Distortion(.ring, drive: 3, mix: 0.8))
        unit.setDistortion(Distortion(.ring), sampleRate: 48000)
        #expect(unit.driving !== first)
    }
}
