import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The effect side as routing rather than as slots. Most of what is checked
/// here is the chain as a value, since what the units themselves do is
/// Apple's; the two that reach the sound are that a chain reaches an export
/// and that order is kept.
@Suite(.serialized) struct EffectChainTests {

    // MARK: - The chain as a value

    @MainActor
    @Test func aSynthStartsWithNoEffects() {
        let synth = Synth(.pluck)
        #expect(synth.effects.isEmpty)
        #expect(synth.delay == nil)
        #expect(synth.reverb == nil)
    }

    /// The bare form that existed before the chain still works, and now reads
    /// and writes through it.
    @MainActor
    @Test func delayAndReverbAreViewsOverTheChain() {
        let synth = Synth(.pluck)
        synth.reverb = Reverb(.hall, mix: 0.4)
        #expect(synth.effects.count == 1)
        #expect(synth.effects[0].kind == .reverb)
        #expect(synth.reverb == Reverb(.hall, mix: 0.4))

        synth.delay = Delay(time: 0.3)
        #expect(synth.effects.count == 2)
        #expect(synth.delay == Delay(time: 0.3))

        // Setting one again replaces it rather than adding another.
        synth.reverb = Reverb(.plate, mix: 0.2)
        #expect(synth.effects.count == 2)
        #expect(synth.reverb?.space == .plate)

        // And nil takes it out, leaving the rest.
        synth.reverb = nil
        #expect(synth.effects.count == 1)
        #expect(synth.effects[0].kind == .delay)
        #expect(synth.reverb == nil)
    }

    /// Setting the same one twice must not walk it down the chain, or an echo
    /// would move behind a reverb just by being adjusted.
    @MainActor
    @Test func replacingAnEffectKeepsItsPlace() {
        let synth = Synth(.pluck)
        synth.effects = [.reverb(Reverb(.room)), .delay(Delay(time: 0.2))]
        synth.reverb = Reverb(.cathedral, mix: 0.5)
        #expect(synth.effects.map(\.kind) == [.reverb, .delay])
        synth.delay = Delay(time: 0.4)
        #expect(synth.effects.map(\.kind) == [.reverb, .delay])
    }

    /// Order is the whole point of a chain, so it has to survive being set.
    @MainActor
    @Test func theChainKeepsTheOrderItWasWrittenIn() {
        let synth = Synth(.pluck)
        let forward: [Effect] = [.distortion(Distortion()), .delay(Delay()), .reverb(Reverb())]
        synth.effects = forward
        #expect(synth.effects == forward)

        let backward: [Effect] = forward.reversed()
        synth.effects = backward
        #expect(synth.effects == backward)
        #expect(synth.effects != forward)
    }

    @MainActor
    @Test func anEffectKnowsItsOwnKind() {
        #expect(Effect.delay(Delay()).kind == .delay)
        #expect(Effect.reverb(Reverb()).kind == .reverb)
        #expect(Effect.equalizer(Equalizer()).kind == .equalizer)
        #expect(Effect.distortion(Distortion()).kind == .distortion)
        #expect(Effect.custom(CustomEffect("mine") { _ in }).kind == .custom)
        // A reverb carrying a room of its own runs on its own unit, so it
        // reads as its own kind; the rest of that story is in ConvolutionTests.
        let room = ImpulseResponse(seconds: 0.01, sampleRate: 48000) { time, _ in exp(-100 * time) }
        #expect(Effect.reverb(Reverb(room)).kind == .convolution)
        #expect(Effect.Kind.allCases.count == 13)   // the four motions and the three levels included
    }

    @MainActor
    @Test func achainCanHoldSeveralOfOneKind() {
        let synth = Synth(.pluck)
        synth.effects = [.delay(Delay(time: 0.12)), .delay(Delay(time: 0.37))]
        #expect(synth.effects.count == 2)
        // The view reads the first, which is what a view over a list can mean.
        #expect(synth.delay == Delay(time: 0.12))
    }

    /// Every unit type really does connect in a chain. The probe said so; this
    /// keeps it true, since a format refused at connect time throws rather than
    /// returning an error.
    @MainActor
    @Test func everyKindWiresWithoutThrowing() {
        let synth = Synth(.pluck)
        synth.effects = [
            .distortion(Distortion(.overdrive)),
            .equalizer(.warm),
            .delay(Delay(time: 0.2)),
            .custom("nothing") { _ in },
            .reverb(Reverb(.decay(seconds: 0.1, seed: 1), mix: 0.2)),
            .reverb(Reverb(.hall)),
        ]
        #expect(synth.effects.count == 6)
        // And in the other order, since a chain is not a fixed rack.
        synth.effects = synth.effects.reversed()
        #expect(synth.effects.map(\.kind) == [.reverb, .convolution, .custom, .delay, .equalizer, .distortion])
    }

    // MARK: - The settings

    @Test func anEqualizerIsBoundedAndItsPresetsDoWhatTheySay() {
        // A gain far past anything useful is brought back rather than trusted.
        #expect(Equalizer(lowGain: 500).lowGain == 24)
        #expect(Equalizer(lowGain: -500).lowGain == -24)
        #expect(Equalizer(midWidth: 0).midWidth == 0.05)

        #expect(Equalizer.warm.lowGain > 0 && Equalizer.warm.highGain < 0)
        #expect(Equalizer.bright.lowGain < 0 && Equalizer.bright.highGain > 0)
        #expect(Equalizer.scooped.midGain < 0)
        #expect(Equalizer.lowCut(below: 300).lowEdge == 300)
    }

    @Test func distortionIsBounded() {
        #expect(Distortion(.softClip, drive: 99).drive == 20)
        #expect(Distortion(.softClip, mix: 9).mix == 1)
        #expect(Distortion(.softClip, mix: -9).mix == 0)
        #expect(Distortion.Character.allCases.count == 5)
    }

    /// Effects are values, so they can be held, compared, and written down.
    @Test func aneffectIsAValue() throws {
        let chain: [Effect] = [.delay(Delay(time: 0.25)), .reverb(Reverb(.plate, mix: 0.3))]
        let encoded = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode([Effect].self, from: encoded)
        #expect(decoded == chain)
    }

    // MARK: - Reaching the sound

    /// The one that matters most: a chain has to reach an export, or a piece
    /// would sound one way in the window and another in the file. That was
    /// already the bug once with placing.
    @MainActor
    @Test func thechainReachesTheExport() {
        func exported(with effects: [Effect]) -> [Float] {
            let synth = Synth(.bell)
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            var elapsed = 0.0
            while elapsed < 2.0 {
                if elapsed == 0 { synth.play(72, velocity: 0.9, for: 0.4) }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: 2.0, sampleRate: 44100)
        }

        let dry = exported(with: [])
        let wet = exported(with: [.reverb(Reverb(.cathedral, mix: 0.9))])
        #expect(dry.contains { abs($0) > 0.005 })
        #expect(wet != dry, "the chain did not reach the export")

        // A long room keeps sounding well after a short note has stopped,
        // which is the effect actually doing its work rather than merely
        // being different.
        func tail(_ s: [Float]) -> Double {
            let from = Int(1.2 * 44100) * 2, to = min(s.count, Int(1.9 * 44100) * 2)
            guard to > from else { return 0 }
            return (s[from..<to].reduce(0.0) { $0 + Double($1) * Double($1) }
                    / Double(to - from)).squareRoot()
        }
        #expect(tail(wet) > 3 * tail(dry), "dry \(tail(dry)), wet \(tail(wet))")
    }

    /// Order reaches the export too, which is the whole reason the chain is a
    /// list rather than a set.
    @MainActor
    @Test func theOrderOfTheChainReachesTheExport() {
        func exported(_ effects: [Effect]) -> [Float] {
            let synth = Synth(.stab)
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            var elapsed = 0.0
            while elapsed < 1.6 {
                if elapsed == 0 { synth.play(60, velocity: 0.9, for: 0.3) }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: 1.6, sampleRate: 44100)
        }

        let distortedEcho: [Effect] = [.distortion(Distortion(.overdrive, mix: 0.8)),
                                       .delay(Delay(time: 0.2, feedback: 0.6, mix: 0.6))]
        let echoDistorted: [Effect] = distortedEcho.reversed()
        #expect(exported(distortedEcho) != exported(echoDistorted))
    }

    /// An instrument with no effects has to export exactly what it did before
    /// there was a chain at all.
    @MainActor
    @Test func anEmptyChainIsTheUntouchedSound() {
        let synth = Synth(.bell)
        OllinApp.isRenderingHeadless = true
        var elapsed = 0.0
        while elapsed < 1.0 {
            if elapsed == 0 { synth.play(72, velocity: 0.9, for: 0.4) }
            synth.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        OllinApp.isRenderingHeadless = false
        let samples = synth.renderExportAudio(upTo: 1.0, sampleRate: 44100)

        #expect(samples.contains { abs($0) > 0.005 })
        // Still centered, since nothing in an empty chain can move it.
        var identical = true
        for frame in 0..<(samples.count / 2) where samples[frame * 2] != samples[frame * 2 + 1] {
            identical = false
            break
        }
        #expect(identical)
    }
}
