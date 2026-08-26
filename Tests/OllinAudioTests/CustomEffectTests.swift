import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The seam for an effect a sketch wrote itself. What is pinned here is the
/// seam, not any particular sound: the closure really runs, on every channel,
/// anywhere in the chain, with its memory intact across blocks, and reaches an
/// export exactly like the built-in kinds.
@Suite(.serialized) struct CustomEffectTests {

    /// Renders a short bell through a chain, off the live clock.
    @MainActor
    private func exported(with effects: [Effect], seconds: Double = 1.0,
                          sampleRate: Double = 44100,
                          note: Double = 0.4) -> [Float] {
        let synth = Synth(.bell)
        synth.effects = effects
        OllinApp.isRenderingHeadless = true
        var elapsed = 0.0
        while elapsed < seconds {
            if elapsed == 0 { synth.play(72, velocity: 0.9, for: note) }
            synth.advance(by: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        OllinApp.isRenderingHeadless = false
        return synth.renderExportAudio(upTo: seconds, sampleRate: sampleRate)
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) }
                / Double(samples.count)).squareRoot()
    }

    // MARK: - The closure runs

    /// The one that matters most, and per channel: the two sides of a stereo
    /// sound each pass through the closure, not just the first. Asserted as a
    /// relationship between the channels, because both merely being nonzero
    /// once hid an export whose right side was silence.
    @MainActor
    @Test func theClosureRunsOnEveryChannel() {
        let dry = exported(with: [])
        let wet = exported(with: [
            .custom("sides") { sound in
                for i in 0..<sound.frameCount {
                    sound.left[i] *= 0.5
                    sound.right[i] = 0
                }
            },
        ])
        #expect(dry.contains { abs($0) > 0.005 })
        #expect(wet.count == dry.count)

        // Interleaved L R: the left is the dry sound at half strength, the
        // right is exactly silence.
        var leftFollows = true
        var rightSilent = true
        for frame in 0..<(wet.count / 2) {
            if abs(wet[frame * 2] - dry[frame * 2] * 0.5) > 1e-4 { leftFollows = false; break }
        }
        for frame in 0..<(wet.count / 2) where wet[frame * 2 + 1] != 0 {
            rightSilent = false
            break
        }
        #expect(leftFollows, "the left channel is not the dry sound at half strength")
        #expect(rightSilent, "the right channel still carries sound")
    }

    /// A chain with a custom link keeps its order: clipping an echo and
    /// echoing a clipped sound are different pieces.
    @MainActor
    @Test func orderReachesTheExportWithACustomLink() {
        let clip = Effect.custom("clip") { sound in
            for channel in 0..<sound.channelCount {
                let samples = sound[channel]
                for i in samples.indices {
                    samples[i] = min(max(samples[i], -0.1), 0.1)
                }
            }
        }
        let echo = Effect.delay(Delay(time: 0.2, feedback: 0.6, mix: 0.6))
        #expect(exported(with: [clip, echo]) != exported(with: [echo, clip]))
    }

    /// The sample rate an export renders at is the one the closure is told.
    /// The effect here keeps the sound only if the rate reads 48000, so sound
    /// surviving a 48 kHz export is the number having arrived.
    @MainActor
    @Test func theBlockKnowsItsSampleRate() {
        let gated = exported(with: [
            .custom("gate") { sound in
                guard sound.sampleRate != 48000 else { return }
                for channel in 0..<sound.channelCount {
                    let samples = sound[channel]
                    for i in samples.indices { samples[i] = 0 }
                }
            },
        ], sampleRate: 48000)
        #expect(gated.contains { abs($0) > 0.005 })
    }

    // MARK: - Memory and time

    /// State handed in as `state:` is the same memory on every block. The
    /// effect counts the samples it has seen and shuts the sound off past a
    /// quarter second, which only works if the count survives from one block
    /// to the next.
    @MainActor
    @Test func memoryCarriesAcrossBlocks() {
        let wet = exported(with: [
            .custom("counter", state: 0) { sound, seen in
                for channel in 0..<sound.channelCount {
                    let samples = sound[channel]
                    for i in samples.indices where seen + i >= 11025 {
                        samples[i] = 0
                    }
                }
                seen += sound.frameCount
            },
        ])
        let frames = wet.count / 2
        let before = rms(wet[0..<(10000 * 2)])
        #expect(before > 0.005, "the sound never got through at all")
        var silentAfter = true
        for frame in 11025..<frames where wet[frame * 2] != 0 || wet[frame * 2 + 1] != 0 {
            silentAfter = false
            break
        }
        #expect(silentAfter, "the sample count did not carry from block to block")
    }

    /// `time` moves forward through the render. The effect mutes the first
    /// half second by the clock it is handed, so sound appearing only after
    /// that is the clock advancing.
    @MainActor
    @Test func timeAdvancesThroughTheBlocks() {
        let wet = exported(with: [
            .custom("late") { sound in
                guard sound.time < 0.5 else { return }
                for channel in 0..<sound.channelCount {
                    let samples = sound[channel]
                    for i in samples.indices { samples[i] = 0 }
                }
            },
        ], seconds: 1.5, note: 1.2)
        let early = rms(wet[0..<(Int(0.45 * 44100) * 2)])
        let late = rms(wet[(Int(0.55 * 44100) * 2)..<(Int(1.0 * 44100) * 2)])
        #expect(early < 0.0005, "sound leaked through before the clock reached it")
        #expect(late > 0.005, "no sound after the gate should have opened")
    }

    // MARK: - The effect as a value

    @MainActor
    @Test func aCustomEffectIsAValueByItsWork() {
        let effect = CustomEffect("mine") { _ in }
        let copy = effect
        #expect(effect == copy)
        let rebuilt = CustomEffect("mine") { _ in }
        #expect(effect != rebuilt, "two separately written effects are different work")
    }

    /// Writing a chain down keeps its shape and its names; the work itself
    /// cannot be written, so a decoded custom link passes sound through.
    @MainActor
    @Test func aDecodedCustomEffectIsANamedPassthrough() throws {
        let chain: [Effect] = [
            .custom("fold") { sound in
                for i in 0..<sound.frameCount { sound.left[i] = 0 }
            },
            .reverb(Reverb(.plate, mix: 0.3)),
        ]
        let decoded = try JSONDecoder().decode([Effect].self,
                                               from: JSONEncoder().encode(chain))
        #expect(decoded.map(\.kind) == [.custom, .reverb])
        guard case .custom(let custom) = decoded[0] else {
            Issue.record("the custom link lost its place")
            return
        }
        #expect(custom.name == "fold")

        // Through the decoded chain the fold is gone: both channels sound.
        let played = exported(with: [decoded[0]])
        var leftSounds = false
        for frame in 0..<(played.count / 2) where abs(played[frame * 2]) > 0.005 {
            leftSounds = true
            break
        }
        #expect(leftSounds, "a decoded custom effect should pass sound through")
    }

    /// The closure is a setting, not wiring: putting a different custom effect
    /// on the same unit swaps the work in place.
    @MainActor
    @Test func applyingSwapsTheWorkOnTheSameUnit() {
        let unit = Effect.makeUnit(for: .custom)
        guard let closureUnit = unit.auAudioUnit as? ClosureAudioUnit else {
            Issue.record("the custom unit is not the closure runner")
            return
        }

        // A block of ones to run the current work over, by hand.
        var samples: [Float] = [1, 1, 1, 1]
        samples.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(buffer.baseAddress)
                )
            )
            withUnsafeMutablePointer(to: &list) { pointer in
                let block = AudioBlock(
                    list: UnsafeMutableAudioBufferListPointer(pointer),
                    frameCount: buffer.count, sampleRate: 44100, time: 0
                )
                Effect.custom("half") { sound in
                    for i in 0..<sound.frameCount { sound.left[i] *= 0.5 }
                }.apply(to: unit)
                closureUnit.slot.run(block)
                #expect(Array(buffer) == [0.5, 0.5, 0.5, 0.5],
                        "the first closure never reached the unit")

                Effect.custom("zero") { sound in
                    for i in 0..<sound.frameCount { sound.left[i] = 0 }
                }.apply(to: unit)
                closureUnit.slot.run(block)
            }
        }
        #expect(samples == [0, 0, 0, 0], "the second closure did not replace the first")
    }
}
