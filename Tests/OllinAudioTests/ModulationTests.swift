import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The four motions: chorus, flanger, phaser, and tremolo. The laws here are
/// the ones that make each what it says it is rather than a wobble: a
/// tremolo breathes between full and the depth at the rate asked, a chorus
/// is a copy twenty milliseconds behind sliding by the wave, a flanger held
/// still is a comb whose first notch sits where its delay says and whose
/// feedback sharpens it, a phaser held still notches where its stages sit
/// and adds a notch per pair of stages, a mix of zero is the plain sound, a
/// setting turned in flight keeps the motion's phase, and the export path
/// carries the motion.
@Suite(.serialized) struct ModulationTests {

    // MARK: - Helpers

    private let rate = 48000.0

    /// Runs a motion over a stereo signal the way the chain would, block by
    /// block in the given sizes, and returns both sides.
    private func run(_ motion: ModulationEffect, left: [Float], right: [Float],
                     blocks: [Int] = [512], change: (Int, ModulationEffect) -> Void = { _, _ in })
    -> (left: [Float], right: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: motion.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var outLeft = [Float](), outRight = [Float]()
        var position = 0
        var turn = 0
        while position < left.count {
            change(position, motion)
            let count = min(blocks[turn % blocks.count], left.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for index in 0..<count {
                data[0][index] = left[position + index]
                data[1][index] = right[position + index]
            }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let block = AudioBlock(list: list, frameCount: count, sampleRate: motion.sampleRate,
                                   time: Double(position) / motion.sampleRate)
            motion.process(block)
            outLeft += Array(UnsafeBufferPointer(start: data[0], count: count))
            outRight += Array(UnsafeBufferPointer(start: data[1], count: count))
            position += count
            turn += 1
        }
        return (outLeft, outRight)
    }

    private func sine(_ frequency: Double, seconds: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    /// The bottom of every dip of a signal: the lowest sample of each run
    /// below the midpoint of its range. A run rather than a local minimum,
    /// since a level near full rounds to a flat top in single precision and
    /// a level read over windows ripples.
    private func minima(of samples: [Float]) -> [Int] {
        guard let top = samples.max(), let bottom = samples.min(), top > bottom else { return [] }
        let midline = (top + bottom) / 2
        var found: [Int] = []
        var lowest: Int? = nil
        for (index, value) in samples.enumerated() {
            if value < midline {
                if let at = lowest, samples[at] <= value { continue }
                lowest = index
            } else if let at = lowest {
                found.append(at)
                lowest = nil
            }
        }
        if let at = lowest { found.append(at) }
        return found
    }

    // MARK: - Tremolo

    @Test func aTremoloBreathesBetweenFullAndTheDepthAtItsRate() {
        let motion = ModulationEffect(.tremolo(Tremolo(rate: 4, depth: 0.7)), sampleRate: rate)
        let steady = [Float](repeating: 1, count: Int(rate * 2))
        let out = run(motion, left: steady, right: steady, blocks: [480, 1024, 64])
        #expect(abs(Double(out.left.max()!) - 1) < 1e-4, "the top of a breath is full level")
        #expect(abs(Double(out.left.min()!) - 0.3) < 1e-3, "the bottom is one minus the depth")
        let dips = minima(of: out.left)
        #expect(dips.count == 8, "four breaths a second over two seconds: \(dips.count)")
        for pair in zip(dips, dips.dropFirst()) {
            #expect(abs(Double(pair.1 - pair.0) - rate / 4) <= 2, "the breaths are a quarter second apart")
        }
    }

    @Test func aTremoloSpreadToOneSwingsTheSidesAgainstEachOther() {
        let motion = ModulationEffect(.tremolo(Tremolo(rate: 3, depth: 0.8, spread: 1)), sampleRate: rate)
        let steady = [Float](repeating: 1, count: Int(rate))
        let out = run(motion, left: steady, right: steady)
        // Opposite turns of the same wave: the two levels always add up to
        // the same thing, and the sides trade the top of the breath.
        for index in stride(from: 0, to: out.left.count, by: 97) {
            #expect(abs(Double(out.left[index] + out.right[index]) - 1.2) < 2e-3)
        }
        let leftDips = minima(of: out.left), rightDips = minima(of: out.right)
        #expect(leftDips.count == 3 && rightDips.count == 3)
        #expect(abs(abs(Double(rightDips[0] - leftDips[0])) - rate / 6) <= 2, "the sides dip half a turn apart")
    }

    // MARK: - Chorus

    @Test func aChorusHeldStillIsACopyTwentyMillisecondsLater() {
        let motion = ModulationEffect(.chorus(Chorus(rate: 1, depth: 0, mix: 1)), sampleRate: rate)
        var click = [Float](repeating: 0, count: Int(rate / 2))
        click[1000] = 1
        let out = run(motion, left: click, right: click, blocks: [300, 700])
        let expected = 1000 + Int(0.020 * rate)
        for side in [out.left, out.right] {
            let peak = side.indices.max { side[$0] < side[$1] }!
            #expect(abs(peak - expected) <= 1, "the copy lands twenty milliseconds on: \(peak) against \(expected)")
            #expect(side[peak] > 0.9, "and it is the whole click")
            #expect(rms(side[0..<expected - 4]) < 1e-6, "nothing comes out before it")
        }
    }

    @Test func aChorusSlidesTheCopyByTheWave() {
        let motion = ModulationEffect(.chorus(Chorus(rate: 1, depth: 1, mix: 1)), sampleRate: rate)
        // A click every tenth of a second, so the delay can be read at ten
        // points along one turn of the wave.
        var clicks = [Float](repeating: 0, count: Int(rate * 1.05))
        let spacing = Int(rate / 10)
        for tick in 0..<10 { clicks[tick * spacing + spacing / 2] = 1 }
        let out = run(motion, left: clicks, right: clicks)
        var delays: [Double] = []
        for tick in 0..<10 {
            let at = tick * spacing + spacing / 2
            let window = at..<(at + spacing)
            // The centroid of the copy, since the interpolation spreads a
            // click over two samples. The copy arrives when the sliding read
            // reaches the click, so the delay is the wave's value at the
            // arrival rather than at the click: the slide while the click
            // waits is the detune a chorus is for.
            func arrival(_ side: [Float]) -> Double {
                var weight = 0.0, moment = 0.0
                for index in window { weight += Double(side[index]); moment += Double(side[index]) * Double(index) }
                return moment / weight / rate
            }
            let landed = arrival(out.left)
            let delay = (landed - Double(at) / rate) * 1000
            delays.append(delay)
            let expected = 20 + 6 * sin(2 * .pi * landed)
            #expect(abs(delay - expected) < 0.25,
                    "at \(landed) s the copy is \(delay) ms behind, the wave says \(expected)")
            // The right side rides a quarter turn ahead.
            let landedR = arrival(out.right)
            let delayR = (landedR - Double(at) / rate) * 1000
            #expect(abs(delayR - (20 + 6 * cos(2 * .pi * landedR))) < 0.25)
        }
        #expect(delays.max()! - delays.min()! > 10, "the copy sweeps most of twelve milliseconds")
    }

    // MARK: - Flanger

    @Test func aFlangerHeldStillIsACombWithItsFirstNotchAtHalfTheDelay() {
        let still = Flanger(rate: 1, depth: 0, feedback: 0, mix: 0.5)
        // A one-millisecond gap: the first notch at five hundred hertz, the
        // first peak at a thousand.
        for (frequency, expectedGain) in [(500.0, 0.0), (1000.0, 1.0), (1500.0, 0.0)] {
            let motion = ModulationEffect(.flanger(still), sampleRate: rate)
            let tone = sine(frequency, seconds: 0.2)
            let out = run(motion, left: tone, right: tone)
            let settled = out.left[Int(rate * 0.05)...]
            let gain = rms(settled) / rms(tone[Int(rate * 0.05)...])
            #expect(abs(gain - expectedGain) < 0.03, "\(frequency) Hz comes through at \(gain)")
        }
    }

    @Test func flangerFeedbackSharpensThePeaks() {
        func peakGain(feedback: Double) -> Double {
            let motion = ModulationEffect(.flanger(Flanger(rate: 1, depth: 0, feedback: feedback, mix: 0.5)),
                                          sampleRate: rate)
            let tone = sine(1000, seconds: 0.3)
            let out = run(motion, left: tone, right: tone)
            return rms(out.left[Int(rate * 0.1)...]) / rms(tone[Int(rate * 0.1)...])
        }
        let plain = peakGain(feedback: 0), fed = peakGain(feedback: 0.7)
        #expect(abs(plain - 1) < 0.03)
        // Half the sound plus half a copy that keeps feeding itself back:
        // 0.5 + 0.5 / (1 - 0.7).
        #expect(abs(fed - (0.5 + 0.5 / 0.3)) < 0.1, "with feedback the peak stands at \(fed)")
    }

    // MARK: - Phaser

    @Test func aPhaserHeldStillNotchesWhereItsStagesSit() {
        // Depth zero holds the stages at two hundred hertz. Two stages turn a
        // tone there half a turn, so it cancels against the plain sound; a
        // tone far above is turned a whole turn and comes through whole.
        for (frequency, expectedGain) in [(200.0, 0.0), (4000.0, 1.0)] {
            let motion = ModulationEffect(.phaser(Phaser(rate: 1, depth: 0, stages: 2, feedback: 0, mix: 0.5)),
                                          sampleRate: rate)
            let tone = sine(frequency, seconds: 0.3)
            let out = run(motion, left: tone, right: tone)
            let gain = rms(out.left[Int(rate * 0.1)...]) / rms(tone[Int(rate * 0.1)...])
            #expect(abs(gain - expectedGain) < 0.04, "\(frequency) Hz through two stages: \(gain)")
        }
    }

    @Test func everyPairOfStagesAddsANotch() {
        // Four stages at two hundred hertz: the notches sit where the turn
        // reaches half and one and a half, at 200·tan(π/8) and 200·tan(3π/8)
        // hertz, and two hundred itself, a whole turn, passes.
        let corner = 200.0
        let notches = [corner * tan(.pi / 8), corner * tan(3 * .pi / 8)]
        for (frequency, expectedGain) in [(notches[0], 0.0), (notches[1], 0.0), (corner, 1.0)] {
            let motion = ModulationEffect(.phaser(Phaser(rate: 1, depth: 0, stages: 4, feedback: 0, mix: 0.5)),
                                          sampleRate: rate)
            let tone = sine(frequency, seconds: 0.4)
            let out = run(motion, left: tone, right: tone)
            let gain = rms(out.left[Int(rate * 0.15)...]) / rms(tone[Int(rate * 0.15)...])
            #expect(abs(gain - expectedGain) < 0.05, "\(frequency) Hz through four stages: \(gain)")
        }
    }

    // MARK: - Shared laws

    @Test func aMixOfZeroIsThePlainSound() {
        let tone = sine(330, seconds: 0.1)
        let settings: [ModulationEffect.Settings] = [
            .chorus(Chorus(mix: 0)), .flanger(Flanger(mix: 0)), .phaser(Phaser(mix: 0)),
            .tremolo(Tremolo(depth: 0)),
        ]
        for setting in settings {
            let motion = ModulationEffect(setting, sampleRate: rate)
            let out = run(motion, left: tone, right: tone, blocks: [100, 333])
            #expect(out.left == tone && out.right == tone, "\(setting.kind) at nothing passes the sound through")
        }
    }

    @Test func aSettingTurnedInFlightKeepsTheMotionsPhase() {
        // A tremolo at two hertz dips at 0.375 s and 0.875 s. The depth is
        // turned at half a second; the second dip still lands where the wave
        // was going, at the new depth.
        let motion = ModulationEffect(.tremolo(Tremolo(rate: 2, depth: 0.5)), sampleRate: rate)
        let steady = [Float](repeating: 1, count: Int(rate))
        let out = run(motion, left: steady, right: steady, blocks: [480]) { position, motion in
            if position == Int(rate * 0.5) { motion.update(.tremolo(Tremolo(rate: 2, depth: 0.9))) }
        }
        let dips = minima(of: out.left)
        #expect(dips.count == 2, "two dips in a second: \(dips)")
        #expect(abs(Double(dips[0]) - rate * 0.375) <= 2)
        #expect(abs(Double(dips[1]) - rate * 0.875) <= 2, "the second dip is where the wave was going")
        #expect(abs(Double(out.left[dips[0]]) - 0.5) < 1e-3)
        #expect(abs(Double(out.left[dips[1]]) - 0.1) < 1e-3, "at the new depth")
    }

    @Test func theKindsAndTheirValuesRoundTrip() throws {
        #expect(Effect.chorus(Chorus()).kind == .chorus)
        #expect(Effect.flanger(Flanger()).kind == .flanger)
        #expect(Effect.phaser(Phaser()).kind == .phaser)
        #expect(Effect.tremolo(Tremolo()).kind == .tremolo)
        #expect(Effect.Kind.allCases.count == 13)   // the four motions and the three levels included
        let chain: [Effect] = [
            .chorus(Chorus(rate: 1.5, depth: 0.3, mix: 0.4)),
            .flanger(Flanger(rate: 0.2, depth: 0.9, feedback: -0.4, mix: 0.6)),
            .phaser(Phaser(rate: 0.7, depth: 0.5, stages: 6, feedback: 0.2, mix: 0.3)),
            .tremolo(Tremolo(rate: 6, depth: 0.4, spread: 0.5)),
        ]
        let data = try JSONEncoder().encode(chain)
        let back = try JSONDecoder().decode([Effect].self, from: data)
        #expect(back == chain)
        // The settings are clamped on the way in.
        #expect(Phaser(stages: 40).stages == 12)
        #expect(Flanger(feedback: 2).feedback == 0.95)
        #expect(Tremolo(depth: 3).depth == 1)
    }

    @MainActor
    @Test func theExportPathCarriesTheMotion() {
        // A held note through a deep tremolo: the export's level breathes at
        // the rate asked, which it cannot unless the chain built for the
        // export carries the same motion the speakers would.
        let synth = Synth(.pad, polyphony: 4)
        synth.gain = 0.6
        synth.effects = [.tremolo(Tremolo(rate: 4, depth: 0.95))]
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        synth.play(Pitch(57), velocity: 1, for: 2.5)
        var elapsed = 0.0
        while elapsed < 2.5 {
            synth.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        let rendered = synth.renderExportAudio(upTo: 2.5, sampleRate: 44100)
        #expect(rendered.count > 44100 * 4, "two and a half seconds of stereo")
        // The level over ten-millisecond windows, from half a second in, once
        // the note has risen.
        var levels: [Double] = []
        let window = 441
        var frame = 22050
        while (frame + window) * 2 <= rendered.count {
            var sum = 0.0
            for index in frame..<(frame + window) {
                let sample = Double(rendered[index * 2])
                sum += sample * sample
            }
            levels.append((sum / Double(window)).squareRoot())
            frame += window
        }
        let loud = levels.max()!, quiet = levels.min()!
        #expect(loud > 0.01, "the note sounds")
        #expect(quiet < loud * 0.25, "and its level dips deep: \(quiet) against \(loud)")
        let dips = minima(of: levels.map { Float($0) })
        // Four breaths a second over the two seconds read: eight dips, give
        // or take the one at either end.
        #expect((6...10).contains(dips.count), "the level dips four times a second: \(dips.count) dips")
    }
}
