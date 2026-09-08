import Accelerate
import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// A room of your own: the convolution reverb. The laws here are the ones
/// that make it a convolution and not merely a wash: the convolver matches
/// the sum it stands for at any block size, a click through the room is the
/// room, the mix is linear, a turn of the mix keeps the tail, and the room
/// reaches an export as the dry sound convolved with it.
@Suite(.serialized) struct ConvolutionTests {

    // MARK: - Helpers

    /// The convolution as a sum, in double precision, for the convolver to
    /// be measured against.
    private func direct(_ input: [Float], _ response: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: input.count)
        for n in 0..<input.count {
            var sum = 0.0
            for k in 0...min(response.count - 1, n) {
                sum += Double(response[k]) * Double(input[n - k])
            }
            out[n] = Float(sum)
        }
        return out
    }

    private func randomSamples(_ count: Int, seed: UInt64, scale: Float = 1) -> [Float] {
        var generator = SplitMix64(seed: seed)
        return (0..<count).map { _ in Float.random(in: -1...1, using: &generator) * scale }
    }

    /// Runs a convolver over `input` in blocks of the given sizes, cycling
    /// through them, and returns the wet signal.
    private func convolve(_ response: [Float], _ input: [Float], blocks: [Int]) -> [Float] {
        let convolver = PartitionedConvolver(response: response)
        var out = [Float](repeating: 0, count: input.count)
        var position = 0
        var turn = 0
        input.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { target in
                while position < input.count {
                    let count = min(blocks[turn % blocks.count], input.count - position)
                    convolver.process(input: source.baseAddress! + position,
                                      wet: target.baseAddress! + position, count: count)
                    position += count
                    turn += 1
                }
            }
        }
        return out
    }

    /// Runs a room over a stereo signal the way the chain would, block by
    /// block, and returns both sides.
    private func run(_ room: ConvolutionReverb, left: [Float], right: [Float],
                     blocks: [Int]) -> (left: [Float], right: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: room.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var outLeft = [Float](), outRight = [Float]()
        var position = 0
        var turn = 0
        while position < left.count {
            let count = min(blocks[turn % blocks.count], left.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for index in 0..<count {
                data[0][index] = left[position + index]
                data[1][index] = right[position + index]
            }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let block = AudioBlock(list: list, frameCount: count, sampleRate: room.sampleRate,
                                   time: Double(position) / room.sampleRate)
            room.process(block)
            outLeft += Array(UnsafeBufferPointer(start: data[0], count: count))
            outRight += Array(UnsafeBufferPointer(start: data[1], count: count))
            position += count
            turn += 1
        }
        return (outLeft, outRight)
    }

    private func maxDifference(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    private func energy(_ samples: ArraySlice<Float>) -> Double {
        samples.reduce(0.0) { $0 + Double($1) * Double($1) }
    }

    // MARK: - The convolver

    /// The one that makes it a convolution: at any block size, with a
    /// response that ends partway through a partition, the output is the sum
    /// it stands for, to float precision.
    @Test func theConvolverMatchesTheSumAtAnyBlockSize() {
        let response = randomSamples(3000, seed: 1, scale: 0.02)
        let input = randomSamples(20000, seed: 2)
        let reference = direct(input, response)
        for blocks in [[512], [1024], [1, 7, 256, 513, 1024, 3, 4096, 255, 2]] {
            let wet = convolve(response, input, blocks: blocks)
            #expect(maxDifference(wet, reference) < 1e-5, "blocks \(blocks)")
        }
    }

    /// A response shorter than a partition runs on the direct head alone;
    /// one exactly a partition long, and one a sample past it, cross into
    /// the tail without a seam.
    @Test func shortResponsesAndPartitionEdgesMatchTheSum() {
        let input = randomSamples(3000, seed: 3)
        for taps in [1, 100, 256, 257, 512] {
            let response = randomSamples(taps, seed: UInt64(10 + taps), scale: 0.05)
            let wet = convolve(response, input, blocks: [512])
            #expect(maxDifference(wet, direct(input, response)) < 1e-5, "\(taps) taps")
        }
    }

    // MARK: - The room

    /// A click through the room, fully wet, comes out as the room itself,
    /// each side its own; and fully dry it comes out untouched.
    @Test func aClickThroughTheRoomIsTheRoom() {
        let rate = 48000.0
        let left = randomSamples(1500, seed: 4, scale: 0.1)
        let right = randomSamples(1500, seed: 5, scale: 0.1)
        let impulse = ImpulseResponse(left: left, right: right, sampleRate: rate)
        let prepared = impulse.prepared(at: rate, preDelay: 0)

        var click = [Float](repeating: 0, count: 2000)
        click[0] = 1
        let wetRoom = ConvolutionReverb(Reverb(impulse, mix: 1), impulse: impulse, sampleRate: rate)
        let wet = run(wetRoom, left: click, right: click, blocks: [300])
        #expect(maxDifference(Array(wet.left[..<1500]), prepared[0]) < 1e-5)
        #expect(maxDifference(Array(wet.right[..<1500]), prepared[1]) < 1e-5)
        #expect(wet.left != wet.right, "the two sides of a stereo room came out the same")
        // Past the room's own length the transform path leaves float dust,
        // nothing a listener or a meter could find.
        #expect(energy(wet.left[1500...]) < 1e-10, "the room kept sounding past its own length")

        let dryRoom = ConvolutionReverb(Reverb(impulse, mix: 0), impulse: impulse, sampleRate: rate)
        let dry = run(dryRoom, left: click, right: click, blocks: [300])
        #expect(dry.left == click)
        #expect(dry.right == click)
    }

    /// The mix is a straight line between the two: a quarter of the way is
    /// three parts sound to one part room.
    @Test func theMixIsLinear() {
        let rate = 48000.0
        let impulse = ImpulseResponse(randomSamples(800, seed: 6, scale: 0.1), sampleRate: rate)
        let input = randomSamples(4000, seed: 7)
        let prepared = impulse.prepared(at: rate, preDelay: 0)[0]
        let wet = direct(input, prepared)
        let room = ConvolutionReverb(Reverb(impulse, mix: 0.25), impulse: impulse, sampleRate: rate)
        let out = run(room, left: input, right: input, blocks: [1024])
        let expected = zip(input, wet).map { $0 * 0.75 + $1 * 0.25 }
        #expect(maxDifference(out.left, expected) < 1e-5)
        #expect(maxDifference(out.right, expected) < 1e-5)
    }

    /// A mono room is heard the same on both sides.
    @Test func aMonoRoomIsHeardOnBothSides() {
        let rate = 48000.0
        let impulse = ImpulseResponse(randomSamples(600, seed: 8, scale: 0.1), sampleRate: rate)
        var click = [Float](repeating: 0, count: 1000)
        click[10] = 1
        let room = ConvolutionReverb(Reverb(impulse, mix: 1), impulse: impulse, sampleRate: rate)
        let out = run(room, left: click, right: click, blocks: [1000])
        #expect(out.left == out.right)
        #expect(energy(out.left[..<10]) == 0 && energy(out.left[10...]) > 0)
    }

    /// Turning the mix rides the standing engine, so a tail already sounding
    /// keeps sounding; a new room or a new pre-delay is a new engine.
    @Test func turningTheMixKeepsTheTail() {
        let rate = 48000.0
        let impulse = ImpulseResponse.decay(seconds: 0.5, sampleRate: rate, seed: 9)
        let unit = ClosureAudioUnit.makeUnit()
        guard let closureUnit = unit.auAudioUnit as? ClosureAudioUnit else {
            Issue.record("the closure unit could not be made")
            return
        }
        closureUnit.setRoom(Reverb(impulse, mix: 0.5), impulse: impulse, sampleRate: rate)
        let first = closureUnit.room
        #expect(first != nil)
        #expect(abs((first?.mix ?? 0) - 0.5) < 1e-6)

        closureUnit.setRoom(Reverb(impulse, mix: 0.8), impulse: impulse, sampleRate: rate)
        #expect(closureUnit.room === first, "a change of mix rebuilt the room")
        // The mix crosses to the audio thread as a float.
        #expect(abs((first?.mix ?? 0) - 0.8) < 1e-6)

        closureUnit.setRoom(Reverb(impulse, mix: 0.8, preDelay: 0.05), impulse: impulse, sampleRate: rate)
        #expect(closureUnit.room !== first, "a change of pre-delay kept the old room")

        let other = ImpulseResponse.decay(seconds: 0.5, sampleRate: rate, seed: 10)
        let before = closureUnit.room
        closureUnit.setRoom(Reverb(other, mix: 0.8, preDelay: 0.05), impulse: other, sampleRate: rate)
        #expect(closureUnit.room !== before, "a new room kept the old engine")

        // And a different rate is a different engine too.
        let atRate = closureUnit.room
        closureUnit.setRoom(Reverb(other, mix: 0.8, preDelay: 0.05), impulse: other, sampleRate: 44100)
        #expect(closureUnit.room !== atRate)
    }

    /// The tail really does carry across a mix change: a click, then silence
    /// with the mix turned, still sounds.
    @Test func theTailSoundsThroughAMixChange() {
        let rate = 48000.0
        let impulse = ImpulseResponse.decay(seconds: 0.5, sampleRate: rate, seed: 11)
        let room = ConvolutionReverb(Reverb(impulse, mix: 0.5), impulse: impulse, sampleRate: rate)
        var click = [Float](repeating: 0, count: 512)
        click[0] = 1
        _ = run(room, left: click, right: click, blocks: [512])
        room.mix = 0.9
        let silence = [Float](repeating: 0, count: 2048)
        let after = run(room, left: silence, right: silence, blocks: [512])
        #expect(energy(after.left[...]) > 0, "the tail was cut by a change of mix")
    }

    // MARK: - Preparing a room

    /// Every room is brought to unit energy, so `mix` means the same for a
    /// quiet recording and a loud one.
    @Test func theRoomIsBroughtToUnitEnergy() {
        let quiet = ImpulseResponse(randomSamples(1000, seed: 12, scale: 0.001), sampleRate: 48000)
        let loud = ImpulseResponse(left: randomSamples(1000, seed: 13, scale: 40),
                                   right: randomSamples(1000, seed: 14, scale: 3), sampleRate: 48000)
        for room in [quiet, loud] {
            let sides = room.prepared(at: 48000, preDelay: 0)
            let total = sides.reduce(0.0) { $0 + energy($1[...]) } / Double(sides.count)
            #expect(abs(total - 1) < 1e-4)
        }
        // Silence stays silence rather than becoming infinity.
        let silent = ImpulseResponse([Float](repeating: 0, count: 100), sampleRate: 48000)
        #expect(silent.prepared(at: 48000, preDelay: 0)[0].allSatisfy { $0 == 0 })
    }

    /// The pre-delay is silence before the room, and nothing else changes.
    @Test func preDelayMovesTheRoomLater() {
        let impulse = ImpulseResponse(randomSamples(1000, seed: 15), sampleRate: 48000)
        let plain = impulse.prepared(at: 48000, preDelay: 0)[0]
        let later = impulse.prepared(at: 48000, preDelay: 0.01)[0]
        #expect(later.count == plain.count + 480)
        #expect(later[..<480].allSatisfy { $0 == 0 })
        #expect(maxDifference(Array(later[480...]), plain) < 1e-6)
        // Clamped to a second, in the value and in the preparing.
        #expect(Reverb(impulse, preDelay: 5).preDelay == 1)
    }

    /// A room recorded at another rate is resampled to the reverb's, and a
    /// click in it lands where it should.
    @Test func aRecordedRoomLoadsAndResamples() throws {
        let path = NSTemporaryDirectory() + "ollin-convolution-room-\(getpid()).wav"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let source = 22050.0
        // Written inside its own scope, since the file is only whole once
        // the writer has let go of it.
        func write() throws {
            let format = AVAudioFormat(standardFormatWithSampleRate: source, channels: 2)!
            let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2000)!
            buffer.frameLength = 2000
            buffer.floatChannelData![0][100] = 1
            buffer.floatChannelData![1][300] = 0.5
            try file.write(from: buffer)
        }
        try write()

        guard let room = ImpulseResponse.load(path) else {
            Issue.record("the room did not load")
            return
        }
        #expect(room.sampleRate == source)
        #expect(room.channelCount == 2)
        #expect(room.frameCount == 2000)
        #expect(room.channels[0][100] == 1)
        #expect(abs(room.duration - 2000 / source) < 1e-9)

        let engine = ConvolutionReverb(Reverb(room), impulse: room, sampleRate: 48000)
        let expected = Int((2000 * 48000 / source).rounded())
        #expect(abs(engine.preparedFrameCount - expected) <= 2)

        let sides = room.prepared(at: 48000, preDelay: 0)
        let leftPeak = sides[0].indices.max { abs(sides[0][$0]) < abs(sides[0][$1]) }!
        let rightPeak = sides[1].indices.max { abs(sides[1][$0]) < abs(sides[1][$1]) }!
        #expect(abs(leftPeak - Int(100 * 48000 / source)) <= 2, "left click landed at \(leftPeak)")
        #expect(abs(rightPeak - Int(300 * 48000 / source)) <= 2, "right click landed at \(rightPeak)")

        #expect(ImpulseResponse.load("/nowhere/at/all.wav") == nil)
    }

    /// A room of noise is the same room every run for one seed, another
    /// room for another, wide (its two sides differ), and it fades.
    @Test func aRoomOfNoiseIsRepeatableAndFades() {
        let one = ImpulseResponse.decay(seconds: 1, sampleRate: 48000, seed: 3)
        let again = ImpulseResponse.decay(seconds: 1, sampleRate: 48000, seed: 3)
        let other = ImpulseResponse.decay(seconds: 1, sampleRate: 48000, seed: 4)
        #expect(one == again)
        #expect(one != other)
        #expect(one.channelCount == 2)
        #expect(one.channels[0] != one.channels[1])
        #expect(one.frameCount == 48000)
        #expect(one.sampleRate == 48000)

        let side = one.channels[0]
        let head = energy(side[..<4800]), tail = energy(side[43200...])
        #expect(tail < head * 0.01, "the room did not fade: \(head) then \(tail)")
        // Sixty decibels over the length: the last tenth against the first
        // is about a thousandfold in amplitude squared, near the end.
        #expect(tail > 0)
    }

    /// Damping is the top end going first: by the end of a damped room the
    /// noise is smoother than at its start, and an undamped one stays as
    /// rough as it began.
    @Test func dampingDarkensTheTail() {
        /// How rough a stretch of samples is: the mean step between
        /// neighbors against the mean level, which a lowpass brings down.
        func roughness(_ samples: ArraySlice<Float>) -> Double {
            var steps = 0.0, level = 0.0
            var previous = samples.first ?? 0
            for sample in samples.dropFirst() {
                steps += Double(abs(sample - previous))
                level += Double(abs(sample))
                previous = sample
            }
            return level > 0 ? steps / level : 0
        }
        let damped = ImpulseResponse.decay(seconds: 1, damping: 1, sampleRate: 48000, seed: 5).channels[0]
        let bright = ImpulseResponse.decay(seconds: 1, damping: 0, sampleRate: 48000, seed: 5).channels[0]
        let dampedStart = roughness(damped[..<4800]), dampedEnd = roughness(damped[43200...])
        let brightStart = roughness(bright[..<4800]), brightEnd = roughness(bright[43200...])
        #expect(dampedEnd < dampedStart * 0.5, "damped: \(dampedStart) then \(dampedEnd)")
        #expect(abs(brightEnd - brightStart) < brightStart * 0.15, "bright: \(brightStart) then \(brightEnd)")
    }

    /// A drawn room is exactly the rule, sample by sample, and the noise it
    /// is handed differs between the sides.
    @Test func aDrawnRoomIsTheRule() {
        let ramp = ImpulseResponse(seconds: 0.01, sampleRate: 1000) { time, _ in time }
        #expect(ramp.frameCount == 10)
        #expect(ramp.channels[0] == (0..<10).map { Float($0) / 1000 })
        #expect(ramp.channels[0] == ramp.channels[1])

        let noisy = ImpulseResponse(seconds: 0.1, sampleRate: 1000, seed: 2) { _, noise in noise }
        #expect(noisy.channels[0] != noisy.channels[1])
        #expect(noisy.channels[0].allSatisfy { $0 >= -1 && $0 <= 1 })
        let same = ImpulseResponse(seconds: 0.1, sampleRate: 1000, seed: 2) { _, noise in noise }
        #expect(same == noisy)

        // Bounded at both ends: nothing shorter than a sample, nothing
        // longer than the longest room.
        #expect(ImpulseResponse(seconds: 0, sampleRate: 1000) { _, _ in 0 }.frameCount == 1)
        #expect(ImpulseResponse(seconds: 100, sampleRate: 1000) { _, _ in 0 }.duration == ImpulseResponse.maxSeconds)
    }

    @Test func reversedRunsTheRoomBackward() {
        let room = ImpulseResponse(left: [1, 2, 3], right: [4, 5, 6], sampleRate: 100)
        let back = room.reversed()
        #expect(back.channels == [[3, 2, 1], [6, 5, 4]])
        #expect(back.sampleRate == 100)
        #expect(back.reversed() == room)
    }

    // MARK: - The chain

    /// A reverb with a room is its own kind, because it runs on its own unit;
    /// the `reverb` view still reaches it, and it writes down and reads back
    /// with the room in it.
    @MainActor
    @Test func aReverbWithARoomIsItsOwnKind() throws {
        let room = ImpulseResponse.decay(seconds: 0.2, sampleRate: 48000, seed: 1)
        #expect(Effect.reverb(Reverb(.hall)).kind == .reverb)
        #expect(Effect.reverb(Reverb(room)).kind == .convolution)
        #expect(Effect.Kind.allCases.count == 6)

        let synth = Synth(.pluck)
        synth.reverb = Reverb(room, mix: 0.4)
        #expect(synth.effects.map(\.kind) == [.convolution])
        #expect(synth.reverb?.impulse == room)
        synth.reverb = Reverb(.plate)
        #expect(synth.effects.map(\.kind) == [.reverb])
        #expect(synth.reverb?.impulse == nil)

        // A chain with a room in it wires like any other, in any position.
        synth.effects = [.delay(Delay(time: 0.1)), .reverb(Reverb(room)), .custom("nothing") { _ in }]
        #expect(synth.effects.count == 3)
        synth.effects = synth.effects.reversed()
        #expect(synth.effects.map(\.kind) == [.custom, .convolution, .delay])

        let chain: [Effect] = [.reverb(Reverb(room, mix: 0.5, preDelay: 0.02))]
        let decoded = try JSONDecoder().decode([Effect].self, from: JSONEncoder().encode(chain))
        #expect(decoded == chain)

        // A reverb written down before rooms existed still reads.
        let old = Data(#"{"space":"cathedral","mix":0.6}"#.utf8)
        let older = try JSONDecoder().decode(Reverb.self, from: old)
        #expect(older == Reverb(.cathedral, mix: 0.6))
    }

    /// The room reaches an export, and reaches it exactly: the file is the
    /// dry sound convolved with the prepared room, sample for sample.
    @MainActor
    @Test func theRoomReachesTheExportAsTheConvolution() {
        func exported(with effects: [Effect]) -> [Float] {
            let synth = Synth(.bell)
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            var elapsed = 0.0
            while elapsed < 1.0 {
                if elapsed == 0 { synth.play(72, velocity: 0.9, for: 0.3) }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: 1.0, sampleRate: 44100)
        }

        // A short room, so the sum it stands for is cheap to check.
        let room = ImpulseResponse.decay(seconds: 0.03, sampleRate: 44100, seed: 21)
        let dry = exported(with: [])
        let wet = exported(with: [.reverb(Reverb(room, mix: 1))])
        #expect(dry.contains { abs($0) > 0.005 })
        #expect(wet.count == dry.count)
        #expect(wet != dry, "the room did not reach the export")

        let prepared = room.prepared(at: 44100, preDelay: 0)
        let frames = dry.count / 2
        for side in 0..<2 {
            let input = (0..<frames).map { dry[$0 * 2 + side] }
            let output = (0..<frames).map { wet[$0 * 2 + side] }
            // The reference through the system's own correlation routine,
            // run backward over the response, which is a convolution.
            let response = prepared[side]
            var padded = [Float](repeating: 0, count: response.count - 1) + input
            var reference = [Float](repeating: 0, count: frames)
            padded.withUnsafeMutableBufferPointer { signal in
                response.withUnsafeBufferPointer { filter in
                    reference.withUnsafeMutableBufferPointer { result in
                        vDSP_conv(signal.baseAddress!, 1, filter.baseAddress! + response.count - 1, -1,
                                  result.baseAddress!, 1, vDSP_Length(frames), vDSP_Length(response.count))
                    }
                }
            }
            #expect(maxDifference(output, reference) < 1e-4, "side \(side)")
        }
    }

    /// A long room takes a long time to fade in the export, which is the
    /// effect doing its work rather than merely being different.
    @MainActor
    @Test func aLongRoomKeepsSoundingInTheExport() {
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
        func tail(_ s: [Float]) -> Double {
            let from = Int(1.2 * 44100) * 2, to = min(s.count, Int(1.9 * 44100) * 2)
            guard to > from else { return 0 }
            return (energy(s[from..<to]) / Double(to - from)).squareRoot()
        }
        let dry = exported(with: [])
        let wet = exported(with: [.reverb(Reverb(.decay(seconds: 2.5, seed: 8), mix: 0.9))])
        #expect(tail(wet) > 3 * tail(dry), "dry \(tail(dry)), wet \(tail(wet))")
    }

    /// The longest room allowed runs in a small fraction of real time.
    @Test func aLongRoomIsCheap() {
        let room = ImpulseResponse.decay(seconds: ImpulseResponse.maxSeconds, damping: 0.5,
                                         sampleRate: 48000, seed: 30)
        let engine = ConvolutionReverb(Reverb(room, mix: 0.5), impulse: room, sampleRate: 48000)
        #expect(engine.preparedFrameCount == Int(ImpulseResponse.maxSeconds * 48000))
        let input = randomSamples(48000, seed: 31)
        let started = Date()
        _ = run(engine, left: input, right: input, blocks: [512])
        let seconds = Date().timeIntervalSince(started)
        #expect(seconds < 5, "a second of audio through the longest room took \(seconds) s")
    }
}
