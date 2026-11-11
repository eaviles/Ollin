import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The echo: a line of Ollin's own with one loop around it. The tests here
/// are the ones that make it an echo that can be trusted with a phrase: a
/// repeat lands on the sample its time names at any length up to the longest,
/// each repeat is the last times the feedback, the damping takes the top end
/// and leaves the bottom, a time turned in flight neither clicks nor drops
/// what is already in the line, and a short echo does not hold a long line.
@Suite(.serialized) struct DelayTests {

    private let rate = 44100.0

    // MARK: - Helpers

    /// Runs an echo over a stereo signal the way the chain would, in blocks
    /// of 512, and returns both sides. `swap` may hand back another line to
    /// carry on with, as the unit does when a time outgrows the standing one.
    private func run(_ first: DelayEffect, left: [Float], right: [Float]? = nil,
                     swap: (Int, DelayEffect) -> DelayEffect? = { _, _ in nil })
    -> (left: [Float], right: [Float]) {
        var echo = first
        let format = AVAudioFormat(standardFormatWithSampleRate: echo.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        var outLeft = [Float](), outRight = [Float]()
        outLeft.reserveCapacity(left.count)
        outRight.reserveCapacity(left.count)
        var position = 0
        while position < left.count {
            if let next = swap(position, echo) { echo = next }
            let count = min(512, left.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for index in 0..<count {
                data[0][index] = left[position + index]
                data[1][index] = right?[position + index] ?? left[position + index]
            }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            echo.process(AudioBlock(list: list, frameCount: count, sampleRate: echo.sampleRate,
                                    time: Double(position) / echo.sampleRate))
            outLeft += UnsafeBufferPointer(start: data[0], count: count)
            outRight += UnsafeBufferPointer(start: data[1], count: count)
            position += count
        }
        return (outLeft, outRight)
    }

    /// One sample of 1 at time zero, then nothing, for `seconds`.
    private func click(seconds: Double) -> [Float] {
        var signal = [Float](repeating: 0, count: Int(seconds * rate))
        signal[0] = 1
        return signal
    }

    // MARK: - Where a repeat lands

    /// A repeat lands on the sample its time names, and the line is silent
    /// until then: at a quarter of a second, at the two seconds the echo
    /// used to stop at, at five, and at the full minute.
    @Test(arguments: [0.25, 2.0, 5.0, 60.0])
    func aRepeatLandsOnItsSample(time: Double) {
        let delay = Delay(time: time, feedback: 0, mix: 1, damping: 20000)
        #expect(delay.time == time)
        let echo = DelayEffect(delay, sampleRate: rate)
        let out = run(echo, left: click(seconds: time + 0.1)).left
        let wanted = Int((time * rate).rounded())
        let first = out.firstIndex { $0 != 0 }
        #expect(first == wanted, "the repeat of a \(time) s echo landed on sample \(String(describing: first)), not \(wanted)")
        #expect(out[wanted] == 1)
        #expect(out[(wanted + 1)...].allSatisfy { $0 == 0 })
    }

    /// A time past the longest is held at the longest, and reads back as it.
    @Test func aTimePastTheLongestIsHeldThere() {
        #expect(Delay.maxTime == 60)
        #expect(Delay(time: 90).time == Delay.maxTime)
        #expect(Delay(time: -1).time == 0)
        // A time set past it after the fact is held at the same place.
        var late = Delay(time: 1)
        late.time = 500
        #expect(DelayEffect.distance(for: late, at: rate) == Int(Delay.maxTime * rate))
    }

    // MARK: - The loop

    /// Each repeat is the one before times the feedback, and nothing else
    /// happens to it while the damping is open.
    @Test func eachRepeatIsTheLastTimesTheFeedback() {
        let echo = DelayEffect(Delay(time: 0.1, feedback: 0.5, mix: 1, damping: 20000), sampleRate: rate)
        let out = run(echo, left: click(seconds: 0.55)).left
        let step = Int(0.1 * rate)
        for (repeatIndex, expected) in [1.0, 0.5, 0.25, 0.125, 0.0625].enumerated() {
            let at = step * (repeatIndex + 1)
            #expect(abs(Double(out[at]) - expected) < 1e-6, "repeat \(repeatIndex + 1) is \(out[at]), not \(expected)")
            #expect(out[at - 1] == 0 && out[at + 1] == 0)
        }
    }

    /// The feedback is held under 1 whatever is asked, so a loop always
    /// fades: a steady full-scale input never passes the sum of its fading
    /// repeats.
    @Test func theLoopAlwaysFades() {
        #expect(Delay(feedback: 3).feedback == 0.95)
        var hot = Delay(time: 0.01, feedback: 0.5, mix: 1, damping: 20000)
        hot.feedback = 40
        let echo = DelayEffect(hot, sampleRate: rate)
        let out = run(echo, left: [Float](repeating: 1, count: Int(4 * rate))).left
        let most = out.max() ?? 0
        #expect(most <= 20.001, "a loop asked for a feedback of 40 reached \(most)")
        #expect(most > 15)
    }

    /// The damping takes the top end of each repeat and leaves the bottom:
    /// a repeat's samples still sum to the feedback's share of the click
    /// (nothing is lost at the lowest frequency), while its peak falls
    /// further than the feedback alone would take it, and the repeat after
    /// has been through the loss once more.
    @Test func theDampingDullsEachRepeatMoreThanTheLast() {
        let echo = DelayEffect(Delay(time: 0.1, feedback: 0.5, mix: 1, damping: 2000), sampleRate: rate)
        let out = run(echo, left: click(seconds: 0.45)).left
        let step = Int(0.1 * rate)
        func repeatSum(_ k: Int) -> Double {
            out[(step * k)..<(step * k + 2000)].reduce(0.0) { $0 + Double($1) }
        }
        func repeatPeak(_ k: Int) -> Double {
            Double(out[(step * k)..<(step * k + 2000)].map { abs($0) }.max() ?? 0)
        }
        #expect(abs(repeatSum(1) - 1) < 1e-3)
        #expect(abs(repeatSum(2) - 0.5) < 1e-3)
        #expect(abs(repeatSum(3) - 0.25) < 1e-3)
        #expect(repeatPeak(1) < 0.5, "a repeat through a 2 kHz damping kept a peak of \(repeatPeak(1))")
        #expect(repeatPeak(2) < 0.5 * repeatPeak(1) * 0.9)
        #expect(repeatPeak(3) < 0.5 * repeatPeak(2) * 0.95)
    }

    /// The damping is one pole at the frequency it names: a repeat's first
    /// sample is `1 - exp(-2 pi f / rate)` of the click and each sample
    /// after falls by the rest.
    @Test func theDampingIsOnePoleAtItsFrequency() {
        let echo = DelayEffect(Delay(time: 0.1, feedback: 0, mix: 1, damping: 6000), sampleRate: rate)
        let out = run(echo, left: click(seconds: 0.2)).left
        let at = Int(0.1 * rate)
        let keeps = 1 - exp(-2 * Double.pi * 6000 / rate)
        #expect(abs(Double(out[at]) - keeps) < 1e-5)
        #expect(abs(Double(out[at + 1]) - keeps * (1 - keeps)) < 1e-5)
        #expect(abs(Double(out[at + 2]) - keeps * (1 - keeps) * (1 - keeps)) < 1e-5)
    }

    /// At a mix of 0 the sound passes untouched, to the sample, and at a mix
    /// under 1 the sound itself is still there under the repeats.
    @Test func theMixSetsHowMuchIsTheEcho() {
        var state: UInt64 = 3
        let noise = (0..<8000).map { _ -> Float in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53) * 2 - 1)
        }
        let dry = run(DelayEffect(Delay(time: 0.05, feedback: 0.6, mix: 0), sampleRate: rate), left: noise).left
        #expect(dry == noise)

        let part = run(DelayEffect(Delay(time: 0.1, feedback: 0, mix: 0.25, damping: 20000), sampleRate: rate),
                       left: click(seconds: 0.2)).left
        #expect(part[0] == 0.75)
        #expect(part[Int(0.1 * rate)] == 0.25)
    }

    /// Each side has a line of its own: a click on the left never comes out
    /// on the right.
    @Test func eachSideKeepsItsOwnLine() {
        let echo = DelayEffect(Delay(time: 0.05, feedback: 0.7, mix: 1, damping: 20000), sampleRate: rate)
        let silent = [Float](repeating: 0, count: Int(0.3 * rate))
        let out = run(echo, left: click(seconds: 0.3), right: silent)
        #expect(out.left.contains { $0 != 0 })
        #expect(out.right.allSatisfy { $0 == 0 })
    }

    // MARK: - A time turned in flight

    /// Turning the time while a tone runs through moves the read across a
    /// short fade, so no sample jumps further than the tone itself moves.
    /// (The system's echo jumped by the tone's whole height: 0.52 on a tone
    /// of 0.5, measured 2026-11-11.)
    @Test func aTimeTurnedInFlightDoesNotClick() {
        let tone = (0..<Int(2 * rate)).map { Float(0.5 * sin(2 * .pi * 441 * Double($0) / rate)) }
        let echo = DelayEffect(Delay(time: 0.30, feedback: 0, mix: 1, damping: 20000), sampleRate: rate)
        let turnAt = Int(1.0 * rate)
        let out = run(echo, left: tone) { position, echo in
            if position >= turnAt, position < turnAt + 512 {
                echo.update(Delay(time: 0.50, feedback: 0, mix: 1, damping: 20000))
            }
            return nil
        }.left
        func largestStep(_ range: Range<Int>) -> Float {
            var most: Float = 0
            for index in range { most = max(most, abs(out[index] - out[index - 1])) }
            return most
        }
        let before = largestStep(Int(0.6 * rate)..<Int(0.99 * rate))
        let across = largestStep(Int(0.99 * rate)..<Int(1.6 * rate))
        #expect(across < before * 1.6, "the largest step was \(before) before the turn and \(across) across it")
        // And once the fade is over the read is where the new time says.
        let settled = Int(1.7 * rate)
        #expect(abs(out[settled] - tone[settled - Int(0.5 * rate)]) < 1e-6)
    }

    /// A time turned past what the standing line holds starts a longer line,
    /// and what was already in flight still comes out when the new time says:
    /// a click half a second old in a one-second echo, turned to three
    /// seconds, lands three seconds after it went in.
    @Test func aLongerTimeKeepsWhatIsInFlight() {
        let short = DelayEffect(Delay(time: 1, feedback: 0, mix: 1, damping: 20000), sampleRate: rate)
        let longer = Delay(time: 3, feedback: 0, mix: 1, damping: 20000)
        #expect(!short.serves(longer, at: rate))
        let turnAt = Int(0.5 * rate) / 512 * 512
        let out = run(short, left: click(seconds: 3.2)) { position, echo in
            position == turnAt ? DelayEffect(longer, sampleRate: rate, replacing: echo) : nil
        }.left
        let landed = out.indices.filter { abs(out[$0]) > 0.5 }
        #expect(landed == [Int(3 * rate)], "the click came out on samples \(landed)")
    }

    /// The line a longer one took over from is let go once the longer one
    /// has been written all the way round, and not before.
    @Test func theShorterLineIsLetGoOnceItIsNoLongerRead() {
        weak var old: DelayEffect?
        let current: DelayEffect
        do {
            let short = DelayEffect(Delay(time: 0.5), sampleRate: rate)
            old = short
            current = DelayEffect(Delay(time: 3), sampleRate: rate, replacing: short)
        }
        #expect(old != nil)
        _ = run(current, left: [Float](repeating: 0, count: Int(1 * rate)))
        current.update(Delay(time: 3, mix: 0.4))
        #expect(old != nil, "the shorter line went while the longer one could still read it")
        _ = run(current, left: [Float](repeating: 0, count: Int(4 * rate)))
        current.update(Delay(time: 3, mix: 0.5))
        #expect(old == nil, "the shorter line outlived its use")
    }

    /// A short echo holds a short line: two seconds for anything up to two,
    /// and the next step up only when the time asks for it.
    @Test func aShortEchoHoldsAShortLine() {
        #expect(DelayEffect(Delay(time: 0.25), sampleRate: rate).capacity == Int(2 * rate))
        #expect(DelayEffect(Delay(time: 2), sampleRate: rate).capacity == Int(2 * rate))
        #expect(DelayEffect(Delay(time: 5), sampleRate: rate).capacity == Int(8 * rate))
        #expect(DelayEffect(Delay(time: 60), sampleRate: rate).capacity == Int(64 * rate))
        // A turn within the standing line keeps it; one past it does not.
        let echo = DelayEffect(Delay(time: 0.25), sampleRate: rate)
        #expect(echo.serves(Delay(time: 1.9), at: rate))
        #expect(!echo.serves(Delay(time: 2.5), at: rate))
        #expect(!echo.serves(Delay(time: 0.25), at: 48000))
    }

    // MARK: - On the unit, and in the export

    /// The unit keeps its echo across a turn of a setting and across a time
    /// that outgrows the line, which is what lets a sketch turn a looper's
    /// length while it plays.
    @MainActor
    @Test func theUnitKeepsItsEchoAcrossATurn() throws {
        let unit = try #require(Effect.makeUnit(for: .delay).auAudioUnit as? ClosureAudioUnit)
        unit.setDelay(Delay(time: 0.25), sampleRate: rate)
        let first = try #require(unit.echo)
        unit.setDelay(Delay(time: 0.4, feedback: 0.7), sampleRate: rate)
        #expect(unit.echo === first)
        #expect(first.current == Delay(time: 0.4, feedback: 0.7))
        unit.setDelay(Delay(time: 6), sampleRate: rate)
        #expect(unit.echo !== first)
        #expect(unit.echo?.capacity == Int(8 * rate))
    }
}
