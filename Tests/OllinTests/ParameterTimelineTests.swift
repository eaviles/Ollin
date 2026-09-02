@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import MetalKit
import Testing

/// The parameter timeline: the clock transport the panel drives (a held clock
/// draws nothing and keeps its time; a scrub draws one frame exactly there; a
/// step moves exactly one frame; the loop region wraps the running clock) and
/// the timeline model's edits (a key placed at the playhead holds the parameter's
/// value, tracks stay sorted, edits round-trip to the file, and a track worked
/// out from a formula is left alone).
@Suite
@MainActor
struct ParameterTimelineTests {

    /// Writes down every frame it draws: the clock and the step it arrived on.
    private final class ClockProbe: Sketch {
        var times: [Double] = []
        var deltas: [Double] = []

        override func draw() {
            times.append(time)
            deltas.append(deltaTime)
        }
    }

    /// Two parameters of different kinds, for the edit laws.
    private final class ParameterProbe: Sketch {
        @Param(0...300) var radius = 120.0
        @Param var filled = true

        override func draw() {}
    }

    /// A real runner over a small windowless view, pumped by hand.
    private func makeRunner(_ sketch: Sketch) throws -> (SketchRunner, MTKView) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        sketch.setCanvasSize(width: 200, height: 200)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        return (runner, view)
    }

    /// The model plus the runner it leans on. The model holds its runner
    /// weakly (a host session owns it), so a test must keep the harness
    /// alive for the model to reach the sketch.
    private struct ModelHarness {
        let model: TimelineModel
        let runner: SketchRunner
        let view: MTKView
    }

    private func makeModel(_ sketch: Sketch) throws -> ModelHarness {
        let (runner, view) = try makeRunner(sketch)
        runner.draw(in: view)         // first frame: setup, so parameters exist
        let model = TimelineModel()
        model.runner = runner
        return ModelHarness(model: model, runner: runner, view: view)
    }

    // MARK: The clock transport

    @Test func aHeldClockDrawsNothingAndKeepsItsTime() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        for _ in 0..<3 { runner.draw(in: view) }
        runner.setClockPaused(true)
        let framesBefore = probe.times.count
        let timeBefore = probe.time
        for _ in 0..<3 { runner.draw(in: view) }
        #expect(probe.times.count == framesBefore,
                "a held clock must not draw and throw away frames")
        #expect(probe.time == timeBefore, "the held clock must not move")
        #expect(runner.isClockPaused)
    }

    @Test func aScrubUnderAHoldDrawsOneFrameThere() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        runner.setClockPaused(true)
        runner.scrubClock(to: 2.5)
        runner.draw(in: view)
        #expect(probe.times.last == 2.5, "the scrubbed frame draws at the placed clock")
        #expect(probe.deltas.last == 0, "nothing elapsed across a scrub")
        let frames = probe.times.count
        runner.draw(in: view)
        #expect(probe.times.count == frames, "after the one pass the hold returns")
    }

    @Test func aStepMovesExactlyOneFrame() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        runner.setClockPaused(true)
        runner.scrubClock(to: 1)
        runner.draw(in: view)
        runner.stepClock(byFrames: 1)
        runner.draw(in: view)
        let step = 1.0 / SketchRunner.clockStepRate
        #expect(abs((probe.times.last ?? 0) - (1 + step)) < 1e-9,
                "a forward step lands one frame later")
        #expect(probe.deltas.last == step, "the stepped frame advances by the step")
        runner.stepClock(byFrames: -1)
        runner.draw(in: view)
        #expect(abs((probe.times.last ?? 0) - 1) < 1e-9,
                "a backward step lands one frame earlier")
        #expect(probe.deltas.last == 0, "a backward step hands the frame a zero step")
    }

    @Test func steppingWhilePlayingHoldsFirst() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        #expect(!runner.isClockPaused)
        runner.stepClock(byFrames: 1)
        #expect(runner.isClockPaused, "a frame step holds the clock the way an editor does")
    }

    @Test func theHoldDoesNotArriveAsOneStepOnResume() async throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        runner.draw(in: view)
        runner.setClockPaused(true)
        let held = probe.time
        try await Task.sleep(for: .milliseconds(120))
        runner.setClockPaused(false)
        runner.draw(in: view)
        let resumed = try #require(probe.times.last)
        #expect(resumed - held < 0.1,
                "the held stretch must not land on the clock as one step")
    }

    @Test func theLoopRegionWrapsTheRunningClock() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        // Two constraints on these numbers. The span must not divide
        // `SketchRunner.longestFrameStep` (0.25): a frame longer than the cap
        // steps by exactly the cap, so a span that divides it wraps back onto
        // the value it started from every frame, and the clock stands still
        // rather than coming around, which is what a loaded machine sees. And
        // the top end sits close to the scrub, because a full frame ring drops
        // most passes and little clock accumulates.
        runner.clockLoopRegion = 1.0...1.013
        runner.scrubClock(to: 1.0125)
        var wrapped = false
        for _ in 0..<2000 {
            runner.draw(in: view)
            guard let last = probe.times.last else { continue }
            #expect(last <= 1.0131, "the clock never plays past the region's top end")
            if last < 1.0125 && last >= 1.0 { wrapped = true; break }
        }
        #expect(wrapped, "the running clock comes around to the region's bottom end")
    }

    @Test func aTakeReleasesTheHold() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        runner.setClockPaused(true)
        runner.beginTake()
        #expect(!runner.isClockPaused, "a recording wants the live clock")
    }

    @Test func aReloadKeepsTheHoldAndShowsTheFreshSketch() throws {
        let probe = ClockProbe()
        let (runner, view) = try makeRunner(probe)
        runner.draw(in: view)
        runner.setClockPaused(true)
        let fresh = ClockProbe()
        runner.reload(to: fresh)
        runner.draw(in: view)
        #expect(fresh.times.count == 1, "a reload's first frame passes the hold once")
        #expect(fresh.deltas.last == 0, "and time stands still through it")
        runner.draw(in: view)
        #expect(fresh.times.count == 1, "then the hold returns")
        #expect(runner.isClockPaused)
    }

    // MARK: The model's edits

    @Test func aToggledKeyHoldsTheParametersValue() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.toggleKey(param: "radius")
        let track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys.count == 1)
        #expect(track.keys[0].value == .number(120))
        #expect(track.keys[0].time == 0)
        #expect(model.hasTrack(named: "radius"))
        model.toggleKey(param: "radius")
        #expect(probe.automation == nil,
                "the last key taken away takes the track, and an empty automation, with it")
    }

    @Test func keysStaySortedThroughPlaceMoveAndRemove() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 2, value: .number(200))
        model.placeKey(param: "radius", at: 1, value: .number(50))
        model.placeKey(param: "radius", at: 3, value: .number(90))
        var track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys.map(\.time) == [1, 2, 3])
        let landed = model.moveKey(track: "radius", at: 0, to: 2.5)
        #expect(landed == 1, "the moved key answers with where it sorted to")
        track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys.map(\.time) == [2, 2.5, 3])
        model.removeKey(track: "radius", at: 1)
        track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys.map(\.time) == [2, 3])
    }

    @Test func aPlacedKeyReplacesOneOnTheSameMoment() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 1, value: .number(50))
        model.placeKey(param: "radius", at: 1, value: .number(80))
        let track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys.count == 1)
        #expect(track.keys[0].value == .number(80))
    }

    @Test func aCurveSetOnAKeyReadsBack() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 0, value: .number(0))
        model.placeKey(param: "radius", at: 2, value: .number(100))
        model.setCurve(track: "radius", at: 0, .bezier(x1: 0.3, y1: 0.1, x2: 0.7, y2: 0.9))
        let track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys[0].curve == .bezier(x1: 0.3, y1: 0.1, x2: 0.7, y2: 0.9))
    }

    @Test func editsRoundTripThroughTheFile() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeline-test-\(UUID().uuidString).automation.json")
        defer { try? FileManager.default.removeItem(at: url) }
        model.setFile(url)
        model.placeKey(param: "radius", at: 1, value: .number(60))
        model.toggleKey(param: "filled")
        model.writeNow()
        #expect(model.saveState == .saved)
        let loaded = try Automation.load(from: url)
        #expect(loaded == probe.automation)
    }

    @Test func aWorkedOutTrackIsLeftAlone() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        probe.automate(Automation.Track(name: "radius", formula: try Formula("time * 10")))
        model.toggleKey(param: "radius")
        let track = try #require(probe.automation?.track(named: "radius"))
        #expect(track.keys.isEmpty, "a rule lane takes no keys")
        #expect(track.formula != nil, "and keeps its rule")
        model.setCurve(track: "radius", at: 0, .linear)
        #expect(probe.automation?.track(named: "radius")?.formula != nil)
    }

    @Test func removingATrackClearsItsSelection() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 1, value: .number(60))
        model.selection = .init(track: "radius", index: 0)
        model.removeTrack(named: "radius")
        #expect(model.selection == nil)
        #expect(!model.hasTrack(named: "radius"))
    }

    @Test func addableParametersLeaveOutTheTracked() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        #expect(model.addableParameters().map(\.name) == ["radius", "filled"])
        model.toggleKey(param: "radius")
        #expect(model.addableParameters().map(\.name) == ["filled"])
    }

    @Test func thePlayheadRidesALoopingAutomation() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 0, value: .number(0))
        model.placeKey(param: "radius", at: 2, value: .number(100))
        probe.automation?.loops = true
        harness.runner.scrubClock(to: 5)
        model.pause()
        #expect(abs(model.playhead - 1) < 1e-9,
                "the playhead shows where the looping pass stands, not the raw clock")
    }

    @Test func aScrubInvertsSpeedAndStart() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 0, value: .number(0))
        model.placeKey(param: "radius", at: 4, value: .number(100))
        probe.automation?.speed = 2
        probe.automation?.start = 1
        model.scrub(to: 3)
        #expect(abs(harness.runner.clockTime - 1) < 1e-9,
                "the scrub lands the clock that reads back as position 3")
        #expect(abs(model.playhead - 3) < 1e-9)
    }

    @Test func toEndUnderALoopLandsAFrameShort() throws {
        let probe = ParameterProbe()
        let harness = try makeModel(probe)
        let model = harness.model
        defer { withExtendedLifetime(harness) {} }
        model.placeKey(param: "radius", at: 0, value: .number(0))
        model.placeKey(param: "radius", at: 2, value: .number(100))
        probe.automation?.loops = true
        model.toEnd()
        #expect(abs(model.playhead - (2 - 1 / SketchRunner.clockStepRate)) < 1e-9,
                "the exact end of a loop wraps to zero, so the transport stops short of it")
    }

    // MARK: The panel's mappings

    @Test func theScaleMapsTimeAndPointsBothWays() {
        let scale = TimelineModel.Scale(contentDuration: 0)
        #expect(scale.span == 5, "an empty timeline still shows a span")
        let long = TimelineModel.Scale(contentDuration: 9.6)
        #expect(long.span == 11, "a breath past the last key, in whole seconds")
        let x = long.x(of: 5.5, width: 440)
        #expect(abs(long.time(at: x, width: 440) - 5.5) < 1e-9)
        #expect(long.time(at: -10, width: 440) == 0, "points before the ruler clamp")
        #expect(TimelineModel.Scale(contentDuration: 40).majorTick == 5)
    }

    @Test func aPlotNormalizesValuesAndKeys() throws {
        let track = Automation.Track(name: "radius", keys: [
            .init(at: 0, .number(0), curve: .linear),
            .init(at: 2, .number(100), curve: .linear),
        ])
        let plot = TimelineModel.plot(track, span: 2, samples: 5)
        let samples = try #require(plot?.samples)
        #expect(samples.first == 0)
        #expect(samples.last == 1)
        #expect(samples.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(plot?.keyHeights == [0, 1])
    }

    @Test func aFlatTrackPlotsOnTheCenterline() {
        let track = Automation.Track(name: "radius", keys: [
            .init(at: 0, .number(50), curve: .linear),
            .init(at: 2, .number(50), curve: .linear),
        ])
        let plot = TimelineModel.plot(track, span: 2, samples: 5)
        #expect(plot?.samples.allSatisfy { $0 == 0.5 } == true)
    }

    @Test func aColorTrackHasNoPlot() {
        let track = Automation.Track(name: "tint", keys: [
            .init(at: 0, .color(red: 1, green: 0, blue: 0, alpha: 1), curve: .linear),
        ])
        #expect(TimelineModel.plot(track, span: 2) == nil,
                "a color lane draws its band, not a curve")
    }
}
