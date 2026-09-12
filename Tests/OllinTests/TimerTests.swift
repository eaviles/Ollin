@testable import Ollin
import Foundation
import Testing

/// Pure-clock checks on `every`, `after`, and `everyFrames`. No GPU, so these
/// run everywhere. The load-bearing property is that all three read the clock
/// and nothing else, which is what makes a beat land on the same second at any
/// frame rate and replay the same way twice.
@Suite
@MainActor
struct TimerTests {

    /// Run a fresh sketch for `seconds` at `fps` and report the clock reading of
    /// every frame on which `fires` answered true.
    private func beats(seconds: Double, fps: Double,
                       _ fires: (Sketch) -> Bool) -> [Double] {
        let sketch = Sketch()
        var hits: [Double] = []
        let frames = Int((seconds * fps).rounded())
        for k in 0..<frames {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            if fires(sketch) { hits.append(sketch.time) }
        }
        return hits
    }

    // MARK: every

    /// The count is a closed form. A run of ten seconds reads the clock over
    /// `0 ..< 10`, so a two-second beat crosses at 0, 2, 4, 6 and 8: five
    /// times, whatever the frame rate. Frame rate must not appear in that
    /// answer, which is the whole point of reading the clock rather than
    /// counting frames.
    ///
    /// This is the guard on the one arithmetic that can break it. Working the
    /// previous frame out as `time - deltaTime` puts it a rounding error away
    /// from where that frame really was. A crossing a frame lands on exactly
    /// then falls inside two windows and counts twice, which three of these six
    /// rates report as six beats where five are due.
    @Test(arguments: [15.0, 24.0, 30.0, 60.0, 120.0, 144.0])
    func theBeatCountIsTheSameAtEveryFrameRate(_ fps: Double) {
        let hits = beats(seconds: 10, fps: fps) { $0.every(2) }
        #expect(hits.count == 5, "at \(fps) fps: \(hits)")
    }

    /// And each beat lands on its own second, within the one frame it takes to
    /// notice the crossing.
    @Test(arguments: [15.0, 60.0, 144.0])
    func eachBeatLandsOnItsSecond(_ fps: Double) {
        let hits = beats(seconds: 10, fps: fps) { $0.every(2) }
        for (k, t) in hits.enumerated() {
            let due = Double(k) * 2
            #expect(t >= due && t - due < 1 / fps, "beat \(k) at \(t), due \(due)")
        }
    }

    /// The clock starts at zero and zero is a multiple of everything, so the
    /// first frame answers true. A sketch that fills a grid on the beat wants
    /// its first row without waiting a whole period for it.
    @Test func theFirstFrameIsABeat() {
        let hits = beats(seconds: 1, fps: 60) { $0.every(5) }
        #expect(hits == [0])
    }

    /// The live window's first frame has no previous frame to measure against,
    /// so it hands `deltaTime` of zero where every export driver hands `1 / fps`.
    /// That difference used to decide whether the beat at zero happened at all:
    /// the window missed it and an export of the same sketch fired it, which is
    /// exactly the disagreement the clock is supposed to rule out.
    @Test func theFirstFrameIsABeatEvenWithNoDeltaTimeYet() {
        let sketch = Sketch()
        sketch.advance(time: 0, deltaTime: 0, frameRate: 60)
        #expect(sketch.every(5), "the window's own first frame is a beat too")
        #expect(sketch.after(0), "and a one-shot at zero fires there")
    }

    /// `phase` shifts the beat by a fraction of its own length, matching what
    /// the same argument does to a lap in `loopProgress(over:phase:)`. Half a
    /// phase on a two-second beat puts it on the odd seconds.
    @Test func phaseShiftsTheBeatByAFractionOfItsLength() {
        let hits = beats(seconds: 6, fps: 60) { $0.every(2, phase: 0.5) }
        #expect(hits.count == 3, "1s, 3s, 5s, and the start of the clock is not one of them")
        for (k, t) in hits.enumerated() {
            #expect(abs(t - (Double(k) * 2 + 1)) < 1.0 / 60, "beat \(k) at \(t)")
        }
    }

    /// Two rhythms of one period interleave rather than collide: on no frame do
    /// both answer true.
    @Test func twoPhasesOfOnePeriodNeverLandTogether() {
        let sketch = Sketch()
        var both = 0, either = 0
        for k in 0..<600 {
            sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            let a = sketch.every(2), b = sketch.every(2, phase: 0.5)
            if a && b { both += 1 }
            if a || b { either += 1 }
        }
        #expect(both == 0)
        #expect(either == 10, "five on the even seconds, five on the odd")
    }

    /// A `Bool` can say "now" once, so a frame long enough to cover two
    /// crossings reports one. That is the honest limit of the shape, and a
    /// sketch stepping a simulation on the beat must not read it as two.
    @Test func aFrameThatSpansTwoCrossingsBeatsOnce() {
        let sketch = Sketch()
        var hits = 0
        for k in 0..<3 {
            sketch.advance(time: Double(k) * 5, deltaTime: 5, frameRate: 0.2)
            if sketch.every(2) { hits += 1 }
        }
        #expect(hits == 3, "three frames, and the two beats inside each count as one")
    }

    /// A replay that starts over sends the clock backwards. It lands in another
    /// period, so it beats there: the rule is that a beat is a change of
    /// period, not a step forward over a line.
    @Test func aClockSentBackwardsBeatsInThePeriodItLandsIn() {
        let sketch = Sketch()
        for k in 0..<300 { sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60) }
        sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        #expect(sketch.every(2), "five seconds back to zero crosses two periods")
        sketch.advance(time: 0.1, deltaTime: 0.1, frameRate: 10)
        #expect(!sketch.every(2), "and the period it landed in is not a new one")
    }

    /// A period of zero or less has no beats to give, and answers false rather
    /// than dividing by zero.
    @Test func aPeriodThatCannotBeatIsSilent() {
        let sketch = Sketch()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        #expect(!sketch.every(0))
        #expect(!sketch.every(-2))
    }

    /// A clock that does not move does not beat. A host that draws a frame
    /// without advancing the clock, which is what a paused sketch does, must
    /// not repeat the beat it has already given.
    @Test func aStoppedClockDoesNotBeat() {
        let sketch = Sketch()
        sketch.advance(time: 4, deltaTime: 1.0 / 60, frameRate: 60)
        #expect(sketch.every(2), "the first frame is a beat")
        sketch.advance(time: 4, deltaTime: 0, frameRate: 60)
        #expect(!sketch.every(2))
        sketch.advance(time: 4, deltaTime: 0, frameRate: 60)
        #expect(!sketch.every(2))
    }

    /// The deciding law, built from a second construction: the frame `every(p)`
    /// calls a beat is exactly the frame on which `loopProgress(over: p)` has
    /// wrapped, and that helper shipped long before this one. Two independent
    /// readings of the same clock must name the same frames.
    @Test func aBeatIsTheFrameALapWrapsOn() {
        let sketch = Sketch()
        var previous = 0.0
        var byLap: [Int] = [], byBeat: [Int] = []
        for k in 0..<900 {
            sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            let lap = sketch.loopProgress(over: 2.5)
            if k == 0 || lap < previous { byLap.append(k) }
            if sketch.every(2.5) { byBeat.append(k) }
            previous = lap
        }
        #expect(byBeat == byLap, "beats \(byBeat) vs wraps \(byLap)")
        #expect(byBeat.count == 6)
    }

    // MARK: after

    /// A one-shot fires once over any run, at the frame that crosses its
    /// second, whatever the frame rate.
    @Test(arguments: [15.0, 30.0, 60.0, 144.0])
    func aOneShotFiresOnceAtItsSecond(_ fps: Double) {
        let hits = beats(seconds: 10, fps: fps) { $0.after(3) }
        #expect(hits.count == 1, "at \(fps) fps: \(hits)")
        if let t = hits.first {
            #expect(t >= 3 && t - 3 < 1 / fps, "fired at \(t)")
        }
    }

    /// Zero seconds in is the first frame, the same rule `every` follows.
    @Test func afterZeroIsTheFirstFrame() {
        let hits = beats(seconds: 2, fps: 60) { $0.after(0) }
        #expect(hits == [0])
    }

    /// A moment the run never reaches never arrives.
    @Test func aMomentBeyondTheRunNeverArrives() {
        let hits = beats(seconds: 2, fps: 60) { $0.after(30) }
        #expect(hits.isEmpty)
    }

    // MARK: everyFrames

    /// Counted in frames, the first frame is the first beat, so the beats sit
    /// on frames 1, n + 1, 2n + 1, and the count is what division says.
    @Test func framesAreCountedFromTheFirstOne() {
        let sketch = Sketch()
        var hits: [Int] = []
        for _ in 0..<100 {
            sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
            if sketch.everyFrames(30) { hits.append(sketch.frameCount) }
        }
        #expect(hits == [1, 31, 61, 91])
    }

    /// Every frame is a beat when the period is one, and no frame is when the
    /// period cannot count.
    @Test func theEndsOfTheFrameCount() {
        let sketch = Sketch()
        var all = 0, none = 0
        for _ in 0..<20 {
            sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
            if sketch.everyFrames(1) { all += 1 }
            if sketch.everyFrames(0) { none += 1 }
        }
        #expect(all == 20)
        #expect(none == 0)
    }

    /// A frame beat does not drift with the clock: it keeps its rate whether
    /// the window runs fast or slow, which is the reason to reach for it over a
    /// beat in seconds when the work owns the rhythm.
    @Test func aFrameBeatIgnoresTheClock() {
        let fast = Sketch(), slow = Sketch()
        var fastHits = 0, slowHits = 0
        for k in 0..<60 {
            fast.advance(time: Double(k) / 120, deltaTime: 1.0 / 120, frameRate: 120)
            slow.advance(time: Double(k) / 12, deltaTime: 1.0 / 12, frameRate: 12)
            if fast.everyFrames(10) { fastHits += 1 }
            if slow.everyFrames(10) { slowHits += 1 }
        }
        #expect(fastHits == slowHits)
        #expect(fastHits == 6)
    }
}
