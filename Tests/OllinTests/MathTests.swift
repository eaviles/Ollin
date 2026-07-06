import Testing
@testable import Ollin

/// Pure-math checks on the bare shaping scalars and the looping-progress
/// helpers. No GPU, so these run everywhere (including CI). Main-actor because
/// the loop helpers read the sketch clock.
@MainActor
@Suite
struct MathTests {

    // MARK: Shaping scalars

    @Test func clampHoldsTheRange() {
        #expect(clamp(-1, 0, 1) == 0)
        #expect(clamp(0.25, 0, 1) == 0.25)
        #expect(clamp(2, 0, 1) == 1)
    }

    @Test func fractKeepsTheFractionalPart() {
        #expect(fract(2.75) == 0.75)
        #expect(fract(3.0) == 0)
        #expect(abs(fract(-0.25) - 0.75) < 1e-12, "floor-based, continuous through negatives")
    }

    @Test func stepSwitchesAtTheEdge() {
        #expect(step(0.5, 0.49) == 0)
        #expect(step(0.5, 0.5) == 1)
        #expect(step(0.5, 0.51) == 1)
    }

    @Test func smoothstepPinsEdgesAndMidpoint() {
        #expect(smoothstep(0, 1, -0.5) == 0)
        #expect(smoothstep(0, 1, 0) == 0)
        #expect(smoothstep(0, 1, 0.5) == 0.5)
        #expect(smoothstep(0, 1, 1) == 1)
        #expect(smoothstep(0, 1, 1.5) == 1)
    }

    @Test func smoothstepHonorsArbitraryEdges() {
        // The two-edge form is the clamped map + Hermite S in one call.
        #expect(smoothstep(0.2, 0.8, 0.2) == 0)
        #expect(abs(smoothstep(0.2, 0.8, 0.5) - 0.5) < 1e-12)
        #expect(smoothstep(0.2, 0.8, 0.8) == 1)
        // Reversed edges fade the other way.
        #expect(smoothstep(1, 0, 0) == 1)
        #expect(smoothstep(1, 0, 1) == 0)
    }

    @Test(arguments: Array(stride(from: 0.0, through: 1.0, by: 0.1)))
    func smoothstepUnitFormMatchesTheEasing(_ t: Double) {
        #expect(smoothstep(0, 1, t) == Easing.smoothstep(t))
    }

    // MARK: Looping progress

    @Test func loopProgressWrapsEveryDuration() {
        let sketch = Sketch()
        sketch.time = 0
        #expect(sketch.loopProgress(over: 3) == 0)
        sketch.time = 1.5
        #expect(abs(sketch.loopProgress(over: 3) - 0.5) < 1e-12)
        sketch.time = 3
        #expect(sketch.loopProgress(over: 3) == 0, "wraps back to 0 at each lap")
        sketch.time = 7.5
        #expect(abs(sketch.loopProgress(over: 3) - 0.5) < 1e-12)
    }

    @Test func loopProgressPhaseShiftsForward() {
        let sketch = Sketch()
        sketch.time = 0
        #expect(abs(sketch.loopProgress(over: 4, phase: 0.25) - 0.25) < 1e-12)
        sketch.time = 3
        #expect(sketch.loopProgress(over: 4, phase: 0.25) == 0, "a quarter head start wraps a quarter early")
    }

    @Test func loopProgressZeroDurationIsSafe() {
        let sketch = Sketch()
        sketch.time = 2
        #expect(sketch.loopProgress(over: 0) == 0)
        #expect(sketch.pingPong(over: 0) == 0)
    }

    @Test func pingPongFoldsOutAndBack() {
        let sketch = Sketch()
        sketch.time = 0
        #expect(sketch.pingPong(over: 4) == 0)
        sketch.time = 1
        #expect(abs(sketch.pingPong(over: 4) - 0.5) < 1e-12, "halfway out")
        sketch.time = 2
        #expect(abs(sketch.pingPong(over: 4) - 1) < 1e-12, "the far end at half the duration")
        sketch.time = 3
        #expect(abs(sketch.pingPong(over: 4) - 0.5) < 1e-12, "halfway back")
        sketch.time = 4
        #expect(sketch.pingPong(over: 4) == 0, "home again, one full trip per duration")
    }
}
