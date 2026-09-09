import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The three that hold a level: the compressor, the limiter, and the gate. The
/// laws here are the ones that make each what it says it is rather than a
/// wobble in the loudness: a compressor lands a tone exactly where its ratio
/// says it should, its attack and release take the times asked, its knee bends
/// before the threshold, its makeup lifts by the decibels asked, and both sides
/// move together; a limiter's ceiling is a promise no sample breaks, and it
/// lets go over its release; a gate opens above its threshold and closes below,
/// and its hold keeps a decay from being chopped off. Plus the two the chain
/// itself owes: a setting turned in flight rides the standing gain, and the
/// export path carries the work.
@Suite(.serialized) struct DynamicsTests {

    // MARK: - Helpers

    private let rate = 48000.0

    /// Runs one of these over a stereo signal the way the chain would, block by
    /// block, and returns both sides.
    private func run(_ dynamics: DynamicsEffect, left: [Float], right: [Float],
                     blocks: [Int] = [512],
                     change: (Int, DynamicsEffect) -> Void = { _, _ in })
    -> (left: [Float], right: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: dynamics.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var outLeft = [Float](), outRight = [Float]()
        var position = 0
        var turn = 0
        while position < left.count {
            change(position, dynamics)
            let count = min(blocks[turn % blocks.count], left.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for index in 0..<count {
                data[0][index] = left[position + index]
                data[1][index] = right[position + index]
            }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let block = AudioBlock(list: list, frameCount: count, sampleRate: dynamics.sampleRate,
                                   time: Double(position) / dynamics.sampleRate)
            dynamics.process(block)
            outLeft += Array(UnsafeBufferPointer(start: data[0], count: count))
            outRight += Array(UnsafeBufferPointer(start: data[1], count: count))
            position += count
            turn += 1
        }
        return (outLeft, outRight)
    }

    /// A sine at a level given in decibels below full scale.
    private func sine(_ frequency: Double, seconds: Double, level: Double = 0) -> [Float] {
        let amplitude = pow(10, level / 20)
        return (0..<Int(seconds * rate)).map {
            Float(amplitude * sin(2 * .pi * frequency * Double($0) / rate))
        }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    /// The level of a stretch of a signal, in decibels, read as the loudest
    /// sample in it, so a sine reads at the level it was asked for and a
    /// window shorter than a whole cycle does not bias the answer the way a
    /// mean would.
    private func decibels(_ samples: ArraySlice<Float>) -> Double {
        20 * log10(max(Double(samples.map { abs($0) }.max() ?? 0), 1e-12))
    }

    // MARK: - The compressor

    @Test func aToneUnderTheThresholdIsLeftAlone() {
        let quiet = sine(220, seconds: 0.5, level: -30)
        let effect = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: 4, knee: 0)),
                                    sampleRate: rate)
        let out = run(effect, left: quiet, right: quiet)
        #expect(out.left == quiet, "nothing over the threshold, nothing done")
    }

    @Test func aToneOverTheThresholdLandsWhereTheRatioSaysItShould() {
        // Six decibels below full through a threshold of -18 at four to one:
        // twelve decibels over arrive as three, so the tone leaves at -15.
        let loud = sine(220, seconds: 1.0, level: -6)
        for (ratio, expected) in [(2.0, -12.0), (4.0, -15.0), (8.0, -16.5)] {
            let effect = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: ratio,
                                                              attack: 0.005, release: 0.2,
                                                              knee: 0)),
                                        sampleRate: rate)
            let out = run(effect, left: loud, right: loud)
            let settled = decibels(out.left[Int(rate * 0.5)...])
            #expect(abs(settled - expected) < 0.5,
                    "at \(ratio) to one the tone leaves at \(settled), not \(expected)")
        }
    }

    @Test func theAttackAndTheReleaseTakeTheTimeAsked() {
        // A step from silence to a loud tone, then back to a quiet one. The
        // reduction should reach about two thirds of its final depth in one
        // attack, and be about a third of the way back in one release.
        let loud = sine(220, seconds: 0.5, level: -6)
        let quiet = sine(220, seconds: 0.5, level: -30)
        let attack = 0.02, release = 0.1
        let effect = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: 4,
                                                           attack: attack, release: release,
                                                           knee: 0)),
                                    sampleRate: rate)
        let out = run(effect, left: loud + quiet, right: loud + quiet)
        let window = Int(rate * 0.01)
        func level(at seconds: Double) -> Double {
            let start = Int(seconds * rate)
            return decibels(out.left[start..<(start + window)])
        }
        let settled = level(at: 0.4)
        let full = -6 - settled
        #expect(abs(full - 9) < 0.5, "the whole reduction is nine decibels: \(full)")
        let afterOneAttack = -6 - level(at: attack)
        #expect(afterOneAttack > full * 0.5 && afterOneAttack < full * 0.85,
                "one attack reaches most of the way: \(afterOneAttack) of \(full)")
        // The reduction against the quiet tone, which asks for none at all.
        let atRelease = -30 - level(at: 0.5 + release)
        #expect(atRelease > 1 && atRelease < full * 0.55,
                "one release lets most of it go: \(atRelease) still held of \(full)")
    }

    @Test func theKneeBendsBeforeTheThreshold() {
        // A tone at the threshold itself: a corner has nothing to do there,
        // and a knee twelve wide is already a decibel in.
        let under = sine(220, seconds: 0.6, level: -18)
        let corner = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: 4, knee: 0)),
                                    sampleRate: rate)
        let rounded = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: 4, knee: 12)),
                                     sampleRate: rate)
        let plain = decibels(run(corner, left: under, right: under).left[Int(rate * 0.4)...])
        let bent = decibels(run(rounded, left: under, right: under).left[Int(rate * 0.4)...])
        #expect(abs(plain - -18) < 0.2, "the corner leaves it alone: \(plain)")
        #expect(bent < plain - 0.5 && bent > plain - 2.5,
                "the knee has started on it: \(bent) against \(plain)")
    }

    @Test func makeupLiftsByTheDecibelsAsked() {
        let loud = sine(220, seconds: 0.6, level: -6)
        func level(_ makeup: Double) -> Double {
            let effect = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: 4,
                                                               knee: 0, makeup: makeup)),
                                        sampleRate: rate)
            return decibels(run(effect, left: loud, right: loud).left[Int(rate * 0.4)...])
        }
        #expect(abs(level(6) - level(0) - 6) < 0.05, "six decibels back is six decibels")
    }

    @Test func bothSidesMoveTogetherWhicheverIsLoud() {
        // A loud side and a quiet one: the level is read from the pair, so the
        // quiet side is held down by exactly what the loud one asked for and
        // the sound does not walk across. Taken both ways round, since a
        // detector listening to one side alone would pass the first and hear
        // nothing at all in the second.
        let loud = sine(220, seconds: 0.6, level: -6)
        let quiet = sine(220, seconds: 0.6, level: -26)
        /// How far each side was pushed down, given which side is the loud one.
        func drops(loudOnTheLeft: Bool) -> (loud: Double, quiet: Double) {
            let effect = DynamicsEffect(.compressor(Compressor(threshold: -18, ratio: 4, knee: 0)),
                                        sampleRate: rate)
            let out = run(effect, left: loudOnTheLeft ? loud : quiet,
                          right: loudOnTheLeft ? quiet : loud)
            let held = Int(rate * 0.4)...
            let loudSide = loudOnTheLeft ? out.left : out.right
            let quietSide = loudOnTheLeft ? out.right : out.left
            return (-6 - decibels(loudSide[held]), -26 - decibels(quietSide[held]))
        }
        for loudOnTheLeft in [true, false] {
            let (onLoud, onQuiet) = drops(loudOnTheLeft: loudOnTheLeft)
            let side = loudOnTheLeft ? "left" : "right"
            #expect(onLoud > 2, "the loud side on the \(side) is heard: \(onLoud) down")
            #expect(abs(onLoud - onQuiet) < 0.05,
                    "and both sides drop alike: \(onLoud) and \(onQuiet)")
        }
    }

    // MARK: - The limiter

    @Test func theCeilingIsAPromise() {
        for ceiling in [-6.0, -0.5, -20.0] {
            // A tone at full scale, and a burst twice that, which is what an
            // effect earlier in the chain can hand a limiter.
            var signal = sine(220, seconds: 0.3, level: 0)
            signal += sine(220, seconds: 0.2, level: 0).map { $0 * 2 }
            let effect = DynamicsEffect(.limiter(Limiter(ceiling: ceiling)), sampleRate: rate)
            let out = run(effect, left: signal, right: signal)
            let allowed = Float(pow(10, ceiling / 20)) + 1e-6
            let worst = out.left.map { abs($0) }.max() ?? 0
            #expect(worst <= allowed, "nothing leaves over \(ceiling) dB: \(worst) against \(allowed)")
        }
    }

    @Test func theLimiterLetsGoOverItsRelease() {
        // One loud burst, then a tone under the ceiling: right after the burst
        // the tone is still ducked, and a few releases later it is not.
        let burst = sine(220, seconds: 0.05, level: 0)
        let after = sine(220, seconds: 0.6, level: -12)
        let effect = DynamicsEffect(.limiter(Limiter(ceiling: -6, release: 0.05)), sampleRate: rate)
        let out = run(effect, left: burst + after, right: burst + after)
        let window = Int(rate * 0.01)
        func level(at seconds: Double) -> Double {
            let start = Int(seconds * rate)
            return decibels(out.left[start..<(start + window)])
        }
        #expect(level(at: 0.052) < -13, "just after the burst the tone is still down: \(level(at: 0.052))")
        #expect(abs(level(at: 0.5) - -12) < 0.2, "and later it is itself again: \(level(at: 0.5))")
    }

    // MARK: - The gate

    @Test func theGateOpensAboveAndClosesBelow() {
        let loud = sine(220, seconds: 0.5, level: -20)
        let quiet = sine(220, seconds: 0.5, level: -60)
        let effect = DynamicsEffect(.gate(Gate(threshold: -45, hold: 0.02, release: 0.05)),
                                    sampleRate: rate)
        let out = run(effect, left: loud + quiet, right: loud + quiet)
        let open = decibels(out.left[Int(rate * 0.4)..<Int(rate * 0.5)])
        let shut = decibels(out.left[Int(rate * 0.8)..<Int(rate * 0.9)])
        #expect(abs(open - -20) < 0.2, "over the threshold it is left alone: \(open)")
        #expect(shut < -100, "under it the gap is silent: \(shut)")
    }

    @Test func theHoldKeepsADecayFromBeingChopped() {
        // A note that decays through the threshold. With no hold the gate shuts
        // the moment it crosses; with a long one the tail is still there.
        let seconds = 0.6
        let decaying: [Float] = (0..<Int(seconds * rate)).map {
            let t = Double($0) / rate
            return Float(pow(10, -20 / 20.0) * exp(-t * 12) * sin(2 * .pi * 220 * t))
        }
        func tail(_ hold: Double) -> Double {
            let effect = DynamicsEffect(.gate(Gate(threshold: -45, hold: hold, release: 0.05)),
                                        sampleRate: rate)
            let out = run(effect, left: decaying, right: decaying)
            return rms(out.left[Int(rate * 0.42)..<Int(rate * 0.5)])
        }
        let chopped = tail(0), held = tail(0.3)
        #expect(held > chopped * 4, "the hold keeps the tail: \(held) against \(chopped)")
    }

    // MARK: - The chain

    @Test func aSettingTurnedInFlightRidesTheStandingGain() {
        // The threshold lowered halfway through a steady tone. The gain moves
        // to the new depth over the attack rather than jumping there, which is
        // only true if the follower kept what it had reached.
        let loud = sine(220, seconds: 1.0, level: -6)
        let effect = DynamicsEffect(.compressor(Compressor(threshold: -12, ratio: 4,
                                                           attack: 0.05, release: 0.2, knee: 0)),
                                    sampleRate: rate)
        let out = run(effect, left: loud, right: loud, blocks: [256]) { position, effect in
            if position >= Int(rate * 0.5) {
                effect.update(.compressor(Compressor(threshold: -24, ratio: 4,
                                                     attack: 0.05, release: 0.2, knee: 0)))
            }
        }
        let window = Int(rate * 0.01)
        func level(at seconds: Double) -> Double {
            let start = Int(seconds * rate)
            return decibels(out.left[start..<(start + window)])
        }
        let before = level(at: 0.45)
        let justAfter = level(at: 0.505)
        let settled = level(at: 0.9)
        #expect(abs(before - -10.5) < 0.5, "the first threshold holds it at -10.5: \(before)")
        #expect(abs(settled - -19.5) < 0.5, "the second holds it at -19.5: \(settled)")
        #expect(justAfter > settled + 2,
                "and it walks there rather than jumping: \(justAfter) a step after the turn")
    }

    @Test func theKindsAndTheirValuesRoundTrip() throws {
        let effects: [Effect] = [
            .compressor(Compressor(threshold: -22, ratio: 6, attack: 0.003, release: 0.4,
                                   knee: 3, makeup: 4)),
            .limiter(Limiter(ceiling: -1.5, release: 0.08)),
            .gate(Gate(threshold: -50, attack: 0.001, hold: 0.1, release: 0.3, depth: 0.7)),
        ]
        #expect(effects.map(\.kind) == [.compressor, .limiter, .gate])
        let data = try JSONEncoder().encode(effects)
        let back = try JSONDecoder().decode([Effect].self, from: data)
        #expect(back == effects, "the settings survive a round trip")
        // Out-of-range settings are pulled into range rather than trusted.
        #expect(Compressor(ratio: 200).ratio == 40)
        #expect(Limiter(ceiling: 12).ceiling == 0)
        #expect(Gate(depth: -1).depth == 0)
    }

    @MainActor
    @Test func theExportPathCarriesTheWork() {
        // A held chord through a gate whose threshold is over the whole thing:
        // the export comes back silent, which it cannot unless the chain built
        // for the export carries the same work the speakers would.
        func rendered(_ effects: [Effect]) -> [Float] {
            let synth = Synth(.pad, polyphony: 4)
            synth.gain = 0.6
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            defer { OllinApp.isRenderingHeadless = false }
            synth.play(Pitch(57), velocity: 1, for: 1.5)
            var elapsed = 0.0
            while elapsed < 1.5 {
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            return synth.renderExportAudio(upTo: 1.5, sampleRate: 44100)
        }
        let plain = rendered([])
        let gated = rendered([.gate(Gate(threshold: -6, attack: 0.001, hold: 0, release: 0.02))])
        #expect(plain.count > 44100, "a second and a half of stereo")
        let plainLevel = rms(plain[(plain.count / 3)...])
        let gatedLevel = rms(gated[(gated.count / 3)...])
        #expect(plainLevel > 0.01, "the chord sounds")
        #expect(gatedLevel < plainLevel * 0.2,
                "and the gate takes it out: \(gatedLevel) against \(plainLevel)")
    }
}
