import Testing
@testable import Ollin

/// Behavior of `@Param`'s optional smoothing: an un-smoothed param snaps, `.eased`
/// glides to the target over its duration, `.smoothed` denoises toward it, and
/// `set(_:)` jumps with no glide. The per-frame `advance(by:)` is what the sketch
/// runs each frame; here we drive it directly. No GPU, so it runs in CI.
@Suite
struct ParamTests {

    @Test func unsmoothedSnapsAndDoesNotDrift() {
        let p = Param(wrappedValue: 10, 0...100)
        p.wrappedValue = 80
        #expect(p.wrappedValue == 80)        // immediate
        p.advance(by: 1.0 / 60)
        #expect(p.wrappedValue == 80)        // advance is a no-op
    }

    @Test func valueClampsToRange() {
        let p = Param(wrappedValue: 0, 0...100)
        p.wrappedValue = 999
        #expect(p.wrappedValue == 100)
        p.wrappedValue = -50
        #expect(p.wrappedValue == 0)
    }

    @Test func easedGlidesOverDuration() {
        let p = Param(wrappedValue: 0, 0...100, smoothing: .eased(duration: 1, curve: .linear))
        p.wrappedValue = 100                 // retarget; doesn't jump
        #expect(p.wrappedValue == 0)
        p.advance(by: 0.5)
        #expect(abs(p.wrappedValue - 50) < 0.001)   // halfway, linear
        p.advance(by: 0.5)
        #expect(abs(p.wrappedValue - 100) < 0.001)  // arrived
        p.advance(by: 0.5)
        #expect(abs(p.wrappedValue - 100) < 0.001)  // stays put
    }

    @Test func smoothedConvergesTowardTarget() {
        let p = Param(wrappedValue: 0, 0...100, smoothing: .smoothed)
        p.wrappedValue = 100
        #expect(p.wrappedValue == 0)         // not yet advanced

        p.advance(by: 1.0 / 60)
        let afterOne = p.wrappedValue
        #expect(afterOne > 0 && afterOne < 100)   // moving, not jumped

        for _ in 0..<600 { p.advance(by: 1.0 / 60) }
        #expect(abs(p.wrappedValue - 100) < 1)    // settled near the target
    }

    @Test func setJumpsWithNoGlide() {
        let p = Param(wrappedValue: 0, 0...100, smoothing: .eased(duration: 1, curve: .linear))
        p.wrappedValue = 100
        p.advance(by: 0.5)                   // mid-glide
        #expect(p.wrappedValue > 0 && p.wrappedValue < 100)

        p.set(40)
        #expect(p.wrappedValue == 40)        // instant
        p.advance(by: 0.5)
        #expect(p.wrappedValue == 40)        // and at rest
    }
}
