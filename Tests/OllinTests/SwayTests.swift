@testable import Ollin
import Foundation
import Testing

/// The sway value source: `sway(over:in:shape:phase:)` and its five shapes.
///
/// Two properties carry the whole thing. Every shape closes its lap exactly, so
/// a swaying sketch can still declare a `loopDuration`, and the answer is a pure
/// function of the clock, so it is the same at any frame rate.
@Suite
@MainActor
struct SwayTests {

    /// Read a fresh sketch's sway at a set of clock readings.
    private func samples(_ times: [Double], seed: Int = 7,
                         _ read: (Sketch) -> Double) -> [Double] {
        let sketch = Sketch()
        sketch.noiseSeed(seed)
        var out: [Double] = []
        var previous = 0.0
        for t in times {
            sketch.advance(time: t, deltaTime: Swift.max(t - previous, 1e-6), frameRate: 60)
            out.append(read(sketch))
            previous = t
        }
        return out
    }

    /// One lap sampled evenly, ending one step short of closing it.
    private func lap(_ shape: SwayShape, duration: Double = 4, steps: Int = 240,
                     range: ClosedRange<Double> = 0...1, phase: Double = 0) -> [Double] {
        let times = (0..<steps).map { Double($0) / Double(steps) * duration }
        return samples(times) { $0.sway(over: duration, in: range, shape: shape, phase: phase) }
    }

    // MARK: Where a lap starts and ends

    /// The four worked-out shapes begin at the low end, so a sketch can change
    /// its mind about the path without the value jumping somewhere else.
    @Test(arguments: [SwayShape.sine, .triangle, .saw, .square])
    func aLapStartsAtTheLowEnd(_ shape: SwayShape) {
        let first = samples([0]) { $0.sway(over: 4, in: 100...300, shape: shape) }[0]
        #expect(abs(first - 100) < 1e-9, "\(shape) started at \(first)")
    }

    /// The load-bearing one: every shape reads the same at the same point of any
    /// lap, `.wander` included. Without it a sketch that sways cannot declare a
    /// `loopDuration`, and `--export-loop` writes a visible jump.
    ///
    /// The fractions matter more than they look. Checking only the lap boundary
    /// cannot see a broken `.wander`, because Perlin noise is exactly zero at
    /// every whole number, so a wander driven straight off the clock reads the
    /// same at second 0, 4 and 8 whether it loops or not. A sabotage swapping
    /// the looping noise for a plain one passed that test and fails this one.
    @Test(arguments: SwayShape.allCases)
    func everyShapeReadsTheSameAtTheSamePointOfAnyLap(_ shape: SwayShape) {
        for fraction in [0.0, 0.13, 0.37, 0.61, 0.88] {
            let at = fraction * 4
            let laps = samples([at, at + 4, at + 8]) {
                $0.sway(over: 4, in: -30...70, shape: shape)
            }
            #expect(abs(laps[1] - laps[0]) < 1e-9,
                    "\(shape) at \(fraction) of a lap: \(laps[0]) then \(laps[1])")
            #expect(abs(laps[2] - laps[0]) < 1e-9,
                    "\(shape) at \(fraction) after two laps: \(laps[2])")
        }
    }

    // MARK: The range

    /// A sway stays between the ends it was given, whichever path it takes.
    @Test(arguments: SwayShape.allCases)
    func aSwayStaysInsideItsRange(_ shape: SwayShape) {
        let values = lap(shape, range: 100...300)
        #expect(values.min()! >= 100 - 1e-9, "\(shape) dipped to \(values.min()!)")
        #expect(values.max()! <= 300 + 1e-9, "\(shape) rose to \(values.max()!)")
    }

    /// And the four worked-out shapes reach both of them.
    @Test(arguments: [SwayShape.sine, .triangle, .saw, .square])
    func aWorkedOutShapeReachesBothEnds(_ shape: SwayShape) {
        let values = lap(shape, range: 100...300)
        #expect(values.min()! < 101, "\(shape) never reached the low end: \(values.min()!)")
        #expect(values.max()! > 299, "\(shape) never reached the high end: \(values.max()!)")
    }

    /// The sine turns around exactly halfway through the lap.
    @Test func theSineTurnsAtTheHalfLap() {
        let top = samples([2]) { $0.sway(over: 4, in: 100...300) }[0]
        #expect(abs(top - 300) < 1e-9, "half a lap read \(top)")
    }

    // MARK: Against what already shipped

    /// A second construction for two of the shapes: the triangle is `pingPong`
    /// mapped onto the range and the saw is `loopProgress` mapped onto it. Both
    /// helpers shipped long before this one, so agreeing with them is a real
    /// check rather than a restatement.
    @Test func theTriangleAndSawAgreeWithTheHelpersTheyAreNamedFor() {
        let sketch = Sketch()
        for k in 0..<200 {
            let t = Double(k) / 25
            sketch.advance(time: t, deltaTime: 0.04, frameRate: 25)
            let triangle = sketch.sway(over: 3, in: 20...80, shape: .triangle)
            let saw = sketch.sway(over: 3, in: 20...80, shape: .saw)
            #expect(abs(triangle - lerp(20, 80, sketch.pingPong(over: 3))) < 1e-12, "at \(t)")
            #expect(abs(saw - lerp(20, 80, sketch.loopProgress(over: 3))) < 1e-12, "at \(t)")
        }
    }

    /// The sine has no corners at the ends, where the triangle has two: over the
    /// first slice of a lap the smooth one has barely left the low end while the
    /// straight one is already travelling at its one speed.
    @Test func theSineLeavesTheEndSlowlyAndTheTriangleDoesNot() {
        let early = 4.0 * 0.04
        let sine = samples([early]) { $0.sway(over: 4, shape: .sine) }[0]
        let triangle = samples([early]) { $0.sway(over: 4, shape: .triangle) }[0]
        #expect(sine < triangle / 3, "sine \(sine) against triangle \(triangle)")
    }

    /// The square is only ever at one end or the other, and spends half the lap
    /// at each.
    @Test func theSquareIsOnlyEverAtOneEndOrTheOther() {
        let values = lap(.square, range: 10...20)
        #expect(values.allSatisfy { $0 == 10 || $0 == 20 })
        #expect(values.filter { $0 == 10 }.count == values.count / 2)
    }

    // MARK: Phase, seed, and the clock

    /// `phase` shifts the lap by a fraction of its own length, which is what
    /// staggers a row of neighbors into a traveling wave.
    @Test(arguments: SwayShape.allCases)
    func phaseShiftsTheLapByAFractionOfItsLength(_ shape: SwayShape) {
        let shifted = samples([0]) { $0.sway(over: 4, shape: shape, phase: 0.25) }[0]
        let later = samples([1]) { $0.sway(over: 4, shape: shape) }[0]
        #expect(abs(shifted - later) < 1e-9, "\(shape): \(shifted) against \(later)")
    }

    /// A wander is the sketch's own noise field, so one seed wanders one way and
    /// a run replays it. Nothing here is random in the sense of unrepeatable.
    @Test func aWanderFollowsTheSketchSeed() {
        let times = (0..<60).map { Double($0) / 15 }
        let a = samples(times, seed: 11) { $0.sway(over: 4, shape: .wander) }
        let again = samples(times, seed: 11) { $0.sway(over: 4, shape: .wander) }
        let other = samples(times, seed: 12) { $0.sway(over: 4, shape: .wander) }
        #expect(a == again, "the same seed should wander the same way")
        #expect(zip(a, other).contains { abs($0 - $1) > 1e-6 },
                "a different seed should wander differently")
    }

    /// A wander actually wanders: it does not sit still, and it does not simply
    /// run out and back the way the worked-out shapes do.
    @Test func aWanderMovesWithoutRepeatingTheSineShape() {
        let wander = lap(.wander, range: 0...1)
        let sine = lap(.sine, range: 0...1)
        let spread = wander.max()! - wander.min()!
        #expect(spread > 0.15, "the wander barely moved: \(spread)")
        #expect(zip(wander, sine).contains { abs($0 - $1) > 0.05 })
    }

    /// The answer reads the clock and nothing else. Two runs that reach the same
    /// second by different numbers of frames agree exactly, which is what makes
    /// an export match the window.
    @Test(arguments: SwayShape.allCases)
    func theFrameRateNeverReachesTheAnswer(_ shape: SwayShape) {
        let fast = Sketch(), slow = Sketch()
        fast.noiseSeed(3); slow.noiseSeed(3)
        for k in 1...240 { fast.advance(time: Double(k) / 120, deltaTime: 1.0 / 120, frameRate: 120) }
        for k in 1...24 { slow.advance(time: Double(k) / 12, deltaTime: 1.0 / 12, frameRate: 12) }
        #expect(abs(fast.time - slow.time) < 1e-12, "both should stand at two seconds")
        #expect(abs(fast.sway(over: 3, in: 5...9, shape: shape)
                    - slow.sway(over: 3, in: 5...9, shape: shape)) < 1e-12, "\(shape)")
    }

    /// A lap with no length in it holds at the low end rather than dividing by
    /// zero, the same answer `loopProgress` gives.
    @Test(arguments: SwayShape.allCases)
    func aLapWithNoLengthHoldsAtTheLowEnd(_ shape: SwayShape) {
        let held = samples([1.5]) { $0.sway(over: 0, in: 40...90, shape: shape) }[0]
        #expect(held == 40)
        let backwards = samples([1.5]) { $0.sway(over: -2, in: 40...90, shape: shape) }[0]
        #expect(backwards == 40)
    }
}
