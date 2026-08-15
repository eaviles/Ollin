import Foundation
import Testing
@testable import Ollin

/// Probes for a piece that runs by itself for days.
///
/// Two kinds of claim. The declaration is plain data, so what a sketch asks for
/// and what the command line overrules are checked directly. The clock is the
/// part that actually breaks a long run, so the arithmetic that defends it is
/// checked against the failure it exists to prevent: a 32-bit clock that stops
/// moving, and a frame step that arrives eight hours long.
@Suite
@MainActor
struct InstallationTests {

    // MARK: What the sketch declares

    private final class Plain: Sketch {}

    private final class OnTheWall: Sketch {
        override var installation: Installation { .on }
        override var loopDuration: Double? { 120 }
    }

    private final class Quiet: Sketch {
        override var installation: Installation { Installation(fillsScreen: false) }
    }

    @Test func offIsTheOnlyValueThatIsNotRunning() {
        #expect(!Installation.off.runsUnattended)
        #expect(Installation.on.runsUnattended)
        // Anything built by hand is one you meant to leave running, whatever
        // parts of it you turned off.
        #expect(Installation(fillsScreen: false, hidesPointer: false,
                             keepsDisplayAwake: false).runsUnattended)
    }

    @Test func theFlagPutsAnySketchOnAWall() {
        #expect(!Installation.resolved(for: Plain(), arguments: ["x"]).runsUnattended)
        #expect(Installation.resolved(for: Plain(), arguments: ["x", "--installation"]).runsUnattended)
    }

    @Test func theFlagAlsoGetsAPieceBackIntoAWindow() {
        #expect(Installation.resolved(for: OnTheWall(), arguments: ["x"]).runsUnattended)
        #expect(!Installation.resolved(for: OnTheWall(),
                                       arguments: ["x", "--no-installation"]).runsUnattended)
    }

    /// The flag turns a piece on; it never overwrites what a piece already
    /// declared. A sketch that asked to keep its pointer keeps it.
    @Test func theFlagLeavesADeclarationAlone() {
        let resolved = Installation.resolved(for: Quiet(), arguments: ["x", "--installation"])
        #expect(resolved.runsUnattended)
        #expect(!resolved.fillsScreen)
    }

    // MARK: The clock a shader reads

    /// The defect the restart exists for. A 32-bit float cannot hold a clock in
    /// seconds for a week: adding one frame at 60 a second to it changes
    /// nothing at all, so every motion driven inside a shader stops.
    @Test func aFloatClockStopsMovingAfterAWeek() {
        let week = 604_800.0, step = 1.0 / 60
        #expect(Float(week + step) == Float(week))
        // A day in it still moves, but a frame is already worth less than one
        // step of what the number can hold, so the motion is uneven.
        let day = 86_400.0
        #expect(Float(day + step) != Float(day))
        #expect(Double(Float(day).ulp) > step / 3)
        // Restarted on a whole lap, it is exact again: a frame step lands
        // within a thousandth of where it should.
        let wrapped = week.truncatingRemainder(dividingBy: 960)
        #expect(abs(Double(Float(wrapped + step) - Float(wrapped)) - step) < step / 1000)
    }

    @Test func anAutomaticClockRestartsOnAWholeLap() throws {
        let period = try #require(Installation.on.clockPeriod(loopDuration: 120))
        #expect(period.truncatingRemainder(dividingBy: 120) == 0)   // whole laps
        #expect(period <= 1000)                                     // small enough to stay exact
        #expect(period >= 120)                                      // never shorter than the loop
        // A loop longer than the window is one lap, not none.
        #expect(Installation.on.clockPeriod(loopDuration: 1800) == 1800)
    }

    @Test func aPieceThatDoesNotRepeatKeepsItsClockRunning() {
        #expect(Installation.on.clockPeriod(loopDuration: nil) == nil)
        #expect(Installation.off.clockPeriod(loopDuration: 120) == nil)
        var stated = Installation.on
        stated.clock = .continuous
        #expect(stated.clockPeriod(loopDuration: 120) == nil)
    }

    @Test func aStatedPeriodIsUsedAsGiven() {
        var stated = Installation.on
        stated.clock = .restarting(every: 45)
        #expect(stated.clockPeriod(loopDuration: 120) == 45)
        stated.clock = .restarting(every: 0)        // nothing to restart on
        #expect(stated.clockPeriod(loopDuration: 120) == nil)
    }

    /// The restart is invisible because it lands where the piece repeats: the
    /// phase a shader reads is the same before and after.
    @Test func theRestartLandsWhereThePieceRepeats() {
        let sketch = OnTheWall()
        let loop = 120.0
        sketch.advance(time: 4 * 3600 + 37.5, deltaTime: 1 / 60, frameRate: 60)
        #expect(sketch.shaderClock < 1000)
        let before = sin(.tau * sketch.time / loop)
        let after = sin(.tau * sketch.shaderClock / loop)
        #expect(abs(before - after) < 1e-9)
    }

    @Test func aSketchAtADeskHandsItsShadersTheClockUntouched() {
        let sketch = Plain()
        sketch.advance(time: 4 * 3600, deltaTime: 1 / 60, frameRate: 60)
        #expect(sketch.shaderClock == sketch.time)
    }

    // MARK: The step the clock takes

    /// The gap that ends a piece: the display sleeps overnight, and the first
    /// frame back measures eight hours. Handed to a sketch as `deltaTime`, that
    /// one step throws every integrator it has into the far distance.
    @Test func aGapInTheFramesIsAPauseRatherThanAJump() {
        #expect(SketchRunner.clockStep(measuring: 8 * 3600) == SketchRunner.longestFrameStep)
        #expect(SketchRunner.clockStep(measuring: 1 / 60) == 1.0 / 60)   // an ordinary frame passes through
        #expect(SketchRunner.clockStep(measuring: 0.2) == 0.2)           // so does a slow one
        #expect(SketchRunner.clockStep(measuring: -3) == 0)              // and the clock never runs backwards
    }

    /// The cap sits past any frame rate worth animating at, so a running sketch
    /// never meets it.
    @Test func theCapIsBeyondAnyRealFrameRate() {
        #expect(SketchRunner.longestFrameStep > 1 / 5.0)
    }
}
