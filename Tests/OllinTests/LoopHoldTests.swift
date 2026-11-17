@testable import Ollin
import AppKit
import Foundation
import Metal
import MetalKit
import QuartzCore
import Testing

/// The reasons a live frame loop stands still, and the work that is owed a
/// frame through them.
///
/// A window's loop can be held by the sketch (`noLoop()`), by the timeline's
/// transport, by a replay's own pause, by a schedule that shuts the piece for
/// the night, by the Mac going to sleep, and by a host that stopped it. Each
/// is one member of a set (`LoopHold`), work that needs a frame meanwhile is
/// a frame owed (`LoopPass`), and one function decides whether the frame
/// timer runs (`SketchRunner.applyPause()`). The tables here hold every pair
/// of reasons, and every kind of owed frame against every reason, through the
/// same calls a host makes; the rule itself is checked over every set there
/// is; and the sources are read for anything else that stops or starts the
/// timer.
@Suite
@MainActor
struct LoopHoldTests {

    // MARK: A live runner on a view with no window, turned by hand

    /// What the sketches of one rig have done between them, so a count
    /// survives the swap a reload makes.
    final class Tally {
        var draws = 0, setups = 0, reloads = 0
        var times: [Double] = []
    }

    final class Probe: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        var tally = Tally()
        var stillFromSetup = false
        override func setup() {
            tally.setups += 1
            if stillFromSetup { noLoop() }
        }
        override func draw() {
            tally.draws += 1
            tally.times.append(time)
            background(.black)
        }
        override func reloaded() { tally.reloads += 1 }
    }

    @MainActor
    struct Rig {
        let tally: Tally
        let view: OllinMTKView
        let runner: SketchRunner
        var sketch: Sketch { runner.sketch }

        func probe(still: Bool = false) -> Probe {
            let probe = Probe()
            probe.tally = tally
            probe.stillFromSetup = still
            return probe
        }
    }

    /// A rig whose first frame is drawn. With `still` the sketch stops its
    /// loop in `setup()`; with `replaying` it plays a take of that many
    /// frames back.
    private func makeRig(still: Bool = false, replaying frames: Int? = nil) throws -> Rig {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let tally = Tally()
        let probe = Probe()
        probe.tally = tally
        probe.stillFromSetup = still
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: probe)
        view.drawableSize = CGSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: probe, view: view, device: device)
        view.delegate = runner
        if let frames {
            Take(version: Take.currentVersion, sketchType: "Probe", seed: 7,
                 canvas: [64, 64], initialParams: [:],
                 frames: (0..<frames).map {
                     Take.Frame(time: Double($0) / 60, deltaTime: 1.0 / 60, frameRate: 60)
                 },
                 events: [], changes: []).install(on: probe)
        }
        let rig = Rig(tally: tally, view: view, runner: runner)
        runner.draw(in: view)
        #expect(tally.draws == 1 && tally.setups == 1, "the first frame sets up and draws")
        return rig
    }

    /// Run the refreshes the display timer would run while the view is
    /// unpaused, up to `limit`, and say how many frames the sketch drew.
    @discardableResult
    private func turn(_ rig: Rig, limit: Int = 8) -> Int {
        let before = rig.tally.draws
        var refreshes = 0
        while !rig.view.isPaused, refreshes < limit {
            rig.runner.draw(in: rig.view)
            refreshes += 1
        }
        return rig.tally.draws - before
    }

    /// Wait until the frame ring has room. A refresh the ring has no room for
    /// is dropped whatever holds the loop, so a check that a frame was or was
    /// not drawn only means something with room in the ring. The GPU hands
    /// slots back on its own thread; the probe comes before the clock.
    private func waitForRoom(_ rig: Rig, _ location: SourceLocation = #_sourceLocation) {
        let deadline = CACurrentMediaTime() + 10
        while !rig.runner.canStartFrame {
            if CACurrentMediaTime() > deadline { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
        #expect(rig.runner.canStartFrame, "the frame ring never emptied", sourceLocation: location)
    }

    /// The loop is held: the timer is stopped, and letting it turn draws
    /// nothing.
    private func expectHeld(_ rig: Rig, _ why: String, _ location: SourceLocation = #_sourceLocation) {
        waitForRoom(rig, location)
        let drawn = turn(rig)
        #expect(drawn == 0, "\(why): \(drawn) frames were drawn", sourceLocation: location)
        #expect(rig.view.isPaused, "\(why): the frame timer is running", sourceLocation: location)
    }

    /// The loop runs: the timer is going and frames come out of it. A refresh
    /// the frame ring has no room for draws nothing, so the ask is repeated;
    /// the probe comes before the clock.
    private func expectRuns(_ rig: Rig, _ why: String, _ location: SourceLocation = #_sourceLocation) {
        #expect(!rig.view.isPaused, "\(why): the frame timer is stopped", sourceLocation: location)
        let before = rig.tally.draws
        let deadline = CACurrentMediaTime() + 5
        while rig.tally.draws < before + 2 {
            if rig.view.isPaused { break }
            turn(rig, limit: 4)
            if CACurrentMediaTime() > deadline { break }
        }
        #expect(rig.tally.draws >= before + 2, "\(why): no frames came", sourceLocation: location)
    }

    /// Owed work got its frames and the hold came back: at least one frame,
    /// no more than a camera takes to settle, and the timer stopped again.
    private func expectOnePass(_ rig: Rig, _ why: String, _ location: SourceLocation = #_sourceLocation) {
        waitForRoom(rig, location)
        let before = rig.tally.draws
        let deadline = CACurrentMediaTime() + 5
        while !rig.view.isPaused, rig.tally.draws < before + 6 {
            turn(rig, limit: 2)
            if CACurrentMediaTime() > deadline { break }
        }
        let drawn = rig.tally.draws - before
        #expect(drawn >= 1, "\(why): the frame it was owed never came", sourceLocation: location)
        #expect(drawn <= 4 && rig.view.isPaused,
                "\(why): the hold did not come back (\(drawn) frames, timer \(rig.view.isPaused ? "stopped" : "running"))",
                sourceLocation: location)
    }

    // MARK: The entry points

    /// A reason the loop stands still, held and released the way its owner
    /// does it.
    enum Reason: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case still, clock, replay, hidden, asleep, stopped
        var testDescription: String { rawValue }
    }

    private func hold(_ reason: Reason, _ rig: Rig) {
        switch reason {
        case .still: rig.sketch.noLoop()
        case .clock: rig.runner.setClockPaused(true)
        case .replay: rig.runner.handleTransportKey(character: " ", code: nil, shift: false)
        case .hidden: rig.runner.setShowing(false)
        case .asleep: rig.view.holdForSleep()
        case .stopped: rig.runner.holdLoop(.stopped)
        }
    }

    private func release(_ reason: Reason, _ rig: Rig) {
        switch reason {
        case .still: rig.sketch.loop()
        case .clock: rig.runner.setClockPaused(false)
        case .replay: rig.runner.handleTransportKey(character: " ", code: nil, shift: false)
        case .hidden: rig.runner.setShowing(true)
        case .asleep: rig.view.releaseSleepHold()
        case .stopped: rig.runner.releaseLoop(.stopped)
        }
    }

    /// Put the rig away the way a host does.
    private func close(_ rig: Rig) {
        rig.runner.holdLoop(.closed)
        rig.view.delegate = nil
    }

    // MARK: Every pair of reasons

    struct Pair: Sendable, CustomTestStringConvertible {
        let first: Reason, second: Reason
        var testDescription: String { "\(first.rawValue), then \(second.rawValue)" }
    }

    /// Every ordered pair that can stand together. A replay owns the whole
    /// transport, so the timeline's hold cannot stand beside its pause, and a
    /// replay draws every frame its take holds whatever the sketch's own
    /// stillness says, which has a test of its own.
    nonisolated static let pairs: [Pair] = Reason.allCases.flatMap { first in
        Reason.allCases.compactMap { second -> Pair? in
            guard first != second else { return nil }
            let both: Set<Reason> = [first, second]
            if both.contains(.replay), both.contains(.clock) || both.contains(.still) { return nil }
            return Pair(first: first, second: second)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: pairs)
    func aLoopHeldForTwoReasonsRunsOnlyWhenBothLetGo(pair: Pair) throws {
        let replaying = pair.first == .replay || pair.second == .replay
        let rig = try makeRig(replaying: replaying ? 4000 : nil)
        defer { close(rig) }
        expectRuns(rig, "nothing holds the loop yet")

        hold(pair.first, rig)
        expectHeld(rig, "held for \(pair.first)")
        hold(pair.second, rig)
        expectHeld(rig, "held for \(pair.first) and \(pair.second)")
        release(pair.first, rig)
        expectHeld(rig, "\(pair.first) let go, \(pair.second) still holds")
        release(pair.second, rig)
        expectRuns(rig, "both let go")
    }

    // MARK: Every kind of owed frame against every reason

    /// Work that asks for a frame while the loop may be standing still.
    enum Wake: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case redraw, freshReload, carriedReload, restart, setupRerun, cameraSnap, clockPass, shaderEdit
        var testDescription: String { rawValue }
    }

    struct Cell: Sendable, CustomTestStringConvertible {
        let wake: Wake, reason: Reason
        var testDescription: String { "\(wake.rawValue) while \(reason.rawValue)" }
    }

    nonisolated static let cells: [Cell] = Wake.allCases.flatMap { wake in
        [Reason.still, .clock, .hidden, .asleep, .stopped].map { Cell(wake: wake, reason: $0) }
    }

    /// The reasons a kind of work goes through. The sketch's own stillness and
    /// the timeline's hold give way to a frame that was asked for; a night
    /// off, the Mac's sleep, and a host that stopped the loop give way to
    /// nothing.
    nonisolated static func passes(_ wake: Wake, through reason: Reason) -> Bool {
        reason == .still || reason == .clock
    }

    private func perform(_ wake: Wake, _ rig: Rig, still: Bool) {
        switch wake {
        case .redraw: rig.sketch.redraw()
        case .freshReload: rig.runner.reload(to: rig.probe(still: still))
        case .carriedReload: rig.runner.reload(to: rig.probe(still: still), keepRun: true)
        case .restart: rig.runner.restart(variation: 3)
        case .setupRerun: rig.runner.rerunSetup()
        case .cameraSnap: rig.runner.requestCameraView(.front)
        case .clockPass: rig.runner.scrubClock(to: 1)
        case .shaderEdit: rig.runner.invalidateUserShaders()
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: cells)
    func owedWorkGetsItsFrameThroughTheHoldsItPassesAndNoOther(cell: Cell) throws {
        // `redraw()` is a still sketch's call, and a scrub only owes a frame
        // under the timeline's hold or to a still sketch: each stands on that
        // footing, with the reason under test on top of it.
        let still = cell.reason == .still || cell.wake == .redraw
        let rig = try makeRig(still: still)
        defer { close(rig) }
        if still { expectHeld(rig, "a still sketch holds after its first frame") }
        if cell.wake == .clockPass, cell.reason != .still, cell.reason != .clock {
            rig.runner.setClockPaused(true)
        }
        if cell.reason != .still { hold(cell.reason, rig) }
        expectHeld(rig, "held for \(cell.reason)")

        let setups = rig.tally.setups, reloads = rig.tally.reloads
        perform(cell.wake, rig, still: still)
        if Self.passes(cell.wake, through: cell.reason) {
            expectOnePass(rig, "\(cell.wake) while \(cell.reason)")
            expectHeld(rig, "\(cell.wake) had its frame, \(cell.reason) holds again")
        } else {
            expectHeld(rig, "\(cell.wake) does not go through \(cell.reason)")
            #expect(rig.tally.setups == setups && rig.tally.reloads == reloads,
                    "nothing of the sketch runs while the loop is held for \(cell.reason)")
            // The work is late, not lost: it has its frame when the reason
            // lets go.
            release(cell.reason, rig)
            waitForRoom(rig)
            let before = rig.tally.draws
            turn(rig, limit: 6)
            #expect(rig.tally.draws > before, "\(cell.wake) is drawn once \(cell.reason) lets go")
        }
        switch cell.wake {
        case .freshReload, .restart, .setupRerun:
            #expect(rig.tally.setups == setups + 1, "\(cell.wake) runs setup() once")
        case .carriedReload:
            #expect(rig.tally.setups == setups, "a carried run does not set up again")
        default: break
        }
        if cell.wake == .freshReload || cell.wake == .carriedReload {
            #expect(rig.tally.reloads == reloads + 1, "the fresh instance hears it was swapped in")
        }
    }

    // MARK: A tick already queued when a hold lands

    /// The frame timer can have one more tick queued by the time a hold stops
    /// it. Under the timeline's hold, a replay's pause, a night off, and the
    /// Mac's sleep that tick draws nothing and moves no clock.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [Reason.clock, .replay, .hidden, .asleep])
    func aTickQueuedWhenAHoldLandsDrawsNothing(reason: Reason) throws {
        let rig = try makeRig(replaying: reason == .replay ? 4000 : nil)
        defer { close(rig) }
        turn(rig, limit: 3)
        hold(reason, rig)
        let draws = rig.tally.draws, time = rig.sketch.time, frame = rig.sketch.frameCount
        for _ in 0..<3 {
            // With room in the ring, so it is the hold that refuses the tick.
            waitForRoom(rig)
            rig.runner.draw(in: rig.view)
        }
        #expect(rig.tally.draws == draws, "a queued tick drew a frame under \(reason)")
        #expect(rig.sketch.time == time && rig.sketch.frameCount == frame,
                "a queued tick moved the clock under \(reason)")
    }

    /// The sketch's own stillness and a host's stop leave the frame to whoever
    /// asks for it by hand, which is how a still piece is put on a display
    /// that arrives late and how a host with no timer of its own turns a run.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [Reason.still, .stopped])
    func aFrameAskedForByHandIsDrawnUnderStillnessAndAHostsStop(reason: Reason) throws {
        let rig = try makeRig()
        defer { close(rig) }
        hold(reason, rig)
        waitForRoom(rig)
        let draws = rig.tally.draws
        rig.runner.draw(in: rig.view)
        #expect(rig.tally.draws == draws + 1)
        #expect(rig.view.isPaused, "and the loop is as held as it was")
    }

    // MARK: The rule, over every set

    private static let everyReason: [LoopHold] = [.still, .clock, .replay, .hidden, .asleep, .stopped, .closed]
    private static let everyKind: [LoopPass] = [.setup, .reload, .setupRerun, .cameraSnap, .settling,
                                                .oneFrame, .clockPass, .scrub]

    /// The rule written out one reason and one kind of owed frame at a time,
    /// apart from the code that decides.
    private static func goes(_ kind: LoopPass, through reason: LoopHold) -> Bool {
        switch reason {
        case .still: return true                       // every owed frame is drawn for a still sketch
        case .clock: return kind != .settling && kind != .scrub
        case .replay: return kind == .scrub
        default: return false                          // a night off, sleep, a host's stop, a canvas put away
        }
    }

    @Test func theLoopRunsExactlyWhenEveryStandingReasonIsPassed() {
        #expect(Self.everyReason.reduce(into: LoopHold()) { $0.formUnion($1) } == LoopHold.all)
        #expect(Self.everyKind.reduce(into: LoopPass()) { $0.formUnion($1) } == LoopPass.all)
        let refusing: [LoopHold] = [.clock, .replay, .hidden, .asleep, .closed]
        var wrong: [String] = []
        for holdBits in 0..<(1 << Self.everyReason.count) {
            for owedBits in 0..<(1 << Self.everyKind.count) {
                let holds = LoopHold(rawValue: UInt8(holdBits)), owed = LoopPass(rawValue: UInt8(owedBits))
                var stands = false, refuses = false
                for reason in Self.everyReason where holds.contains(reason) {
                    let passed = Self.everyKind.contains { owed.contains($0) && Self.goes($0, through: reason) }
                    if !passed {
                        stands = true
                        if refusing.contains(reason) { refuses = true }
                    }
                }
                if holds.holdsLoop(owing: owed) != stands || holds.refusesFrame(owing: owed) != refuses {
                    wrong.append("holds \(holdBits) owing \(owedBits)")
                }
            }
        }
        #expect(wrong.isEmpty, "the decision disagrees with the rule for \(wrong.count) sets, first \(wrong.prefix(3))")
    }

    @Test func nothingOwedStartsALoopHeldForTheNightTheSleepTheHostOrTheEnd() {
        for reason in [LoopHold.hidden, .asleep, .stopped, .closed] {
            #expect(reason.holdsLoop(owing: .all), "every kind of owed frame at once went through \(reason.rawValue)")
        }
        #expect(!LoopHold().holdsLoop(owing: []), "a loop nothing holds runs")
        #expect(!LoopHold().refusesFrame(owing: []))
    }

    // MARK: The sources

    /// The lines under `Sources/` that write an `isPaused`, outside comments.
    private static func pauseWrites() throws -> [(file: String, line: Int, text: String, function: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let write = try NSRegularExpression(pattern: #"\bisPaused\b\s*(=(?!=)|\.toggle\(\))"#)
        var found: [(String, Int, String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            var function = ""
            for (index, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var code = String(raw)
                if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
                if let name = code.range(of: #"func \w+"#, options: .regularExpression) {
                    function = String(code[name]).replacingOccurrences(of: "func ", with: "")
                }
                let range = NSRange(code.startIndex..., in: code)
                guard write.firstMatch(in: code, range: range) != nil else { continue }
                let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
                found.append((path, index + 1, code.trimmingCharacters(in: .whitespaces), function))
            }
        }
        return found
    }

    /// The writes that are not a frame timer being stopped or started by
    /// something other than the runner, each with why. A new one joins this
    /// list with its reason, or goes through `holdLoop` and `releaseLoop`.
    static let otherWrites: [String: String] = [
        "Sources/Ollin/Live/TimelineModel.swift":
            "the timeline panel's own copy of whether the clock is held, which is not a view's timer",
        "Sources/OllinLiveCoding/HeadlessStage.swift":
            "a headless check's stage, stopped before any runner has it so the check turns it by hand",
    ]

    /// Nothing but `SketchRunner.applyPause()` stops or starts a frame timer.
    /// A second writer is how a reason to hold the loop gets undone by
    /// something that never heard of it.
    @Test func onlyApplyPauseWritesTheFrameTimer() throws {
        let writes = try Self.pauseWrites()
        let inside = writes.filter { $0.file == "Sources/Ollin/Core/SketchView.swift" && $0.function == "applyPause" }
        #expect(!inside.isEmpty, "applyPause() writes no isPaused: the reader lost its place")
        var excused: Set<String> = []
        for write in writes where !(write.file == "Sources/Ollin/Core/SketchView.swift" && write.function == "applyPause") {
            if Self.otherWrites[write.file] != nil {
                excused.insert(write.file)
            } else {
                Issue.record("\(write.file):\(write.line) writes isPaused outside applyPause() (\(write.text)): hold the loop for a reason through the runner instead")
            }
        }
        for (file, reason) in Self.otherWrites where !excused.contains(file) {
            Issue.record("\(file) is excused (\(reason)) and writes no isPaused: drop it from the list")
        }
    }

    // MARK: Who speaks for the window

    /// The instance a swap replaced may still call `noLoop()` or `loop()`
    /// from a timer or a callback of its own. It no longer speaks for the
    /// window: the stillness that holds the loop is the drawing instance's.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aReplacedInstanceNeitherHoldsTheLoopNorStartsIt() throws {
        let rig = try makeRig()
        defer { close(rig) }
        let replaced = rig.sketch
        rig.runner.reload(to: rig.probe())
        turn(rig, limit: 2)

        replaced.noLoop()
        expectRuns(rig, "the replaced instance stopped its own loop")

        rig.sketch.noLoop()
        expectHeld(rig, "the drawing instance stopped its loop")
        replaced.loop()
        expectHeld(rig, "the replaced instance started its own loop")
    }

    /// A sketch can have stopped its loop before a runner has it (an instance
    /// handed from one host to another, a `noLoop()` in an initializer). Its
    /// first frame is still owed, and after it the loop holds.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSketchAlreadyStillDrawsItsFirstFrameAndHolds() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let probe = Probe()
        probe.noLoop()
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: probe)
        view.drawableSize = CGSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: probe, view: view, device: device)
        view.delegate = runner
        let rig = Rig(tally: probe.tally, view: view, runner: runner)
        defer { close(rig) }

        #expect(!view.isPaused, "the first frame is owed through the sketch's stillness")
        let drawn = turn(rig)
        #expect(drawn == 1 && probe.tally.setups == 1, "one frame, with setup() run for it (\(drawn) drawn)")
        #expect(view.isPaused, "and then the loop holds")
    }

    /// Work owed a frame through a hold runs at the top of a refresh, and the
    /// refresh can still be dropped before anything is drawn (the frame ring
    /// full). The frame stays owed until one is drawn, or a setup rerun under
    /// the timeline's hold would run and never show.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFrameOwedThroughAHoldOutlivesARefreshTheRingDrops() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = FrameRingProbes.HeavyProbe()
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 2160, height: 2160), device: device)
        view.drawableSize = CGSize(width: 2160, height: 2160)
        sketch.setCanvasSize(width: 2160, height: 2160)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        defer { runner.holdLoop(.closed) }

        // Fill the ring, reading it after every draw (a starved machine can
        // finish the first frame before the fourth is asked for).
        var filled = false
        for _ in 0..<24 where !filled {
            runner.draw(in: view)
            filled = !runner.canStartFrame
        }
        runner.setClockPaused(true)
        runner.rerunSetup()
        let draws = sketch.draws
        let full = !runner.canStartFrame
        runner.draw(in: view)
        if full, sketch.draws == draws {
            // The refresh ran the setup and was dropped at the ring.
            #expect(!runner.isLoopHeld, "the rerun's frame went with the dropped refresh, and none is coming")
        }
        // The GPU hands slots back on its own thread; the probe comes before
        // the clock.
        let deadline = CACurrentMediaTime() + 30
        while sketch.draws == draws {
            runner.draw(in: view)
            if sketch.draws > draws || CACurrentMediaTime() > deadline { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        #expect(sketch.draws == draws + 1, "the frame the rerun was owed is drawn once there is room")
        runner.draw(in: view)
        #expect(sketch.draws == draws + 1 && runner.isLoopHeld, "and the timeline holds again")
    }

    // MARK: The combinations filed as defects

    /// A swap that carries the run, made while the timeline holds the clock:
    /// the frame that shows the edit is drawn once, at the held time, and the
    /// fresh instance hears `reloaded()`.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCarriedReloadShowsUnderTheTimelineHold() throws {
        let rig = try makeRig()
        defer { close(rig) }
        turn(rig, limit: 3)
        rig.runner.setClockPaused(true)
        expectHeld(rig, "the timeline holds the clock")
        let held = rig.sketch.time
        let draws = rig.tally.draws

        let fresh = rig.probe()
        rig.runner.reload(to: fresh, keepRun: true)
        expectOnePass(rig, "the frame that shows the edit")
        #expect(rig.tally.draws == draws + 1, "one frame, not a run of them")
        #expect(rig.tally.reloads == 1, "the fresh instance hears reloaded()")
        #expect(rig.tally.setups == 1, "and setup() did not run again")
        #expect(fresh.time == held && fresh.deltaTime == 0, "time stands still through it")
        #expect(rig.runner.isClockPaused)
    }

    /// A replay draws every frame its take holds. A sketch that stopped its
    /// own loop was recorded one asked-for frame at a time, and the asks are
    /// in the take, so the replay cannot wait for them.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillSketchsTakeReplaysToItsEnd() throws {
        let rig = try makeRig(still: true, replaying: 12)
        defer { close(rig) }
        let deadline = CACurrentMediaTime() + 5
        while !rig.view.isPaused, rig.tally.draws < 40 {
            turn(rig, limit: 4)
            if CACurrentMediaTime() > deadline { break }
        }
        #expect(rig.tally.draws == 12, "the replay walks the whole take and stops at its end")
        #expect(rig.view.isPaused, "and holds there")
    }
}
