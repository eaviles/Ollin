import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLiveCoding --sessiontest`: headless checks of the shared
/// `SketchSession` semantics both live hosts depend on (no window; the swaps
/// exercised here stop at the first mount, which is exactly where the
/// param-carry and supersede logic live). The session runs two-speed, the
/// performance host's default, so every invariant below holds across the
/// plain build landing first and the optimized one replacing it:
///
/// - A two-speed evaluation lands the plain build first, says the optimized
///   one is on its way, and then replaces it with the optimized build.
/// - A recorded (user-dragged) param value is re-applied to the next
///   evaluation's sketch, while an *untouched* param takes the buffer's edited
///   default.
/// - A navigated variation seed carries the same way, so an edit doesn't
///   reshuffle the composition the user was working on.
/// - Two back-to-back evaluations resolve to the newer one (supersede), never
///   the stale one, and an evaluation made while the older one's optimized
///   build is still compiling refuses that build too.
/// - A buffer that fails to compile fails the evaluation once, with nothing
///   optimizing behind it and the sketch on stage untouched.
/// - First-mount bookkeeping: `reloadCount` stays 0 and `lastBuildSeconds`
///   stays nil until a runner exists to reload into.
enum SessionTest {
    @MainActor
    static func run() -> Never {
        Task { @MainActor in
            await check()
        }
        RunLoop.main.run()   // pumped until a check calls exit()
        exit(1)
    }

    @MainActor
    private static func check() async {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinLiveCoding-sessiontest")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let loader = SketchLoader(
            sketchPath: (dir as NSString).appendingPathComponent("Sketch.swift"))

        // `build` says which compile the instance came from, read in `init`
        // because nothing here runs `setup()`: the plain build reads 1, the
        // optimized one 2.
        func source(radiusDefault: Double, speedDefault: Double) -> String {
            """
            import Ollin
            final class SessionSketch: Sketch {
                @Param(10...400) var radius = \(radiusDefault)
                @Param(0...9) var speed = \(speedDefault)
                @Param(0...2) var build = 0.0
                required init() {
                    super.init()
                    build = _isDebugAssertConfiguration() ? 1 : 2
                }
                override func draw() { background(.white) }
            }
            """
        }

        let session = SketchSession(keepClock: true, landsPlainBuildFirst: true)

        print("OllinLiveCoding sessiontest: first evaluation, in two speeds …")
        // The host hears about the first landing through `onSuccess`, once,
        // which is where the plain build is caught: on a sketch this small
        // the optimized one lands a few tens of milliseconds behind it.
        var landings = 0
        var plain: Sketch?
        var optimizingAtLanding = false
        session.evaluate(loader, input: .source(source(radiusDefault: 100, speedDefault: 1))) { sketch in
            landings += 1
            plain = sketch
            optimizingAtLanding = session.isOptimizing
        }
        await settle(session)
        guard case .idle = session.phase, let plain else {
            fail("first evaluation didn't land: \(session.phase)")
        }
        guard landings == 1, optimizingAtLanding, build(of: plain) == 1 else {
            fail("the first build to land was not the plain one, told once, with the optimized one behind it "
                + "(landings \(landings), optimizing \(optimizingAtLanding), build \(build(of: plain)))")
        }
        guard let optimized = session.sketch, optimized !== plain, value(of: "build", session) == 2 else {
            fail("the optimized build did not replace the plain one (build \(value(of: "build", session) ?? .nan))")
        }
        guard session.reloadCount == 0, session.lastBuildSeconds == nil else {
            fail("first mount miscounted as a reload")
        }
        guard value(of: "radius", session) == 100, value(of: "speed", session) == 1 else {
            fail("first evaluation's params read wrong")
        }

        print("OllinLiveCoding sessiontest: param carry across an evaluation …")
        session.recordParam("radius", .number(42))   // the user dragged this parameter
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 2)))
        await settle(session)
        guard value(of: "radius", session) == 42 else {
            fail("the dragged parameter snapped back to \(value(of: "radius", session) ?? .nan)")
        }
        guard value(of: "speed", session) == 2 else {
            fail("the untouched param kept a stale default instead of the edited one")
        }
        guard value(of: "build", session) == 2 else {
            fail("the carry was read off the plain build, not the optimized one that replaced it")
        }

        print("OllinLiveCoding sessiontest: variation carry across an evaluation …")
        session.recordSeed(777)                      // the user navigated the seed space
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 2)))
        await settle(session)
        guard session.sketch?.variation == 777 else {
            fail("the navigated variation reshuffled to \(session.sketch?.variation ?? -1)")
        }

        print("OllinLiveCoding sessiontest: supersede (two evaluations back to back) …")
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 5)))
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 7)))
        await settle(session)
        // Grace for the superseded compiles to finish and be refused.
        try? await Task.sleep(for: .seconds(4))
        guard value(of: "speed", session) == 7, value(of: "build", session) == 2, !session.isOptimizing else {
            fail("a superseded evaluation landed last (speed = \(value(of: "speed", session) ?? .nan), "
                + "build = \(value(of: "build", session) ?? .nan))")
        }

        print("OllinLiveCoding sessiontest: supersede against the optimized build of the older one …")
        // The older evaluation's plain build is on stage and its optimized
        // build still on its way when the newer one starts (from the older
        // one's own landing hook, the one moment that is sure to be inside
        // that window): that build must never land, or the stage would fall
        // back to older code.
        var olderBuild = Double.nan
        var newerStartedWhileOptimizing = false
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 3))) { sketch in
            olderBuild = build(of: sketch)
            newerStartedWhileOptimizing = session.isOptimizing
            session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 8)))
        }
        await settle(session)
        try? await Task.sleep(for: .seconds(4))
        guard olderBuild == 1, newerStartedWhileOptimizing else {
            fail("the older evaluation's plain build did not land first (build \(olderBuild), optimizing \(newerStartedWhileOptimizing))")
        }
        guard value(of: "speed", session) == 8, value(of: "build", session) == 2, !session.isOptimizing else {
            fail("the older evaluation's optimized build landed over the newer one (speed = \(value(of: "speed", session) ?? .nan), "
                + "build = \(value(of: "build", session) ?? .nan))")
        }

        print("OllinLiveCoding sessiontest: a broken buffer fails once and leaves the stage alone …")
        let onStage = session.sketch
        session.evaluate(loader, input: .source("import Ollin\nfinal class SessionSketch: Sketch {\n    override func draw() { wat() }\n}\n"))
        await settle(session)
        guard case .failed = session.phase, !session.isOptimizing, session.sketch === onStage else {
            fail("the broken buffer did not fail cleanly (phase \(session.phase), optimizing \(session.isOptimizing))")
        }
        try? await Task.sleep(for: .seconds(3))   // its optimized compile fails too; refused, not reported twice
        guard case .failed = session.phase, session.sketch === onStage else {
            fail("the broken buffer's second compile changed the outcome")
        }
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 8)))
        await settle(session)
        guard case .idle = session.phase, value(of: "build", session) == 2 else {
            fail("a good evaluation after the broken one did not land: \(session.phase)")
        }

        print("OllinLiveCoding sessiontest: cue carry across an evaluation …")
        let cuesPath = (dir as NSString).appendingPathComponent("Sketch.cues.json")
        try? FileManager.default.removeItem(atPath: cuesPath)
        do { try session.adoptCueFile(cuesPath) } catch { fail("could not adopt the cue file: \(error)") }
        func setRadius(_ v: Double) {
            session.params.first { $0.name == "radius" }?.param.restore(.number(v))
        }
        setRadius(250)
        session.saveCue("wide")
        guard session.cues.map(\.name) == ["wide"], FileManager.default.fileExists(atPath: cuesPath) else {
            fail("saving a cue did not list it and file it")
        }
        setRadius(50)
        session.callCue(.named("wide"), over: 0)
        guard value(of: "radius", session) == 250 else { fail("calling the cue did not bring the radius back") }
        session.evaluate(loader, input: .source(source(radiusDefault: 100, speedDefault: 1)))
        await settle(session)
        guard session.cues.map(\.name) == ["wide"], session.sketch?.cueSheet.cues.count == 1 else {
            fail("the cue did not carry across the evaluation")
        }
        session.callCue(.number(0), over: 0)
        guard value(of: "radius", session) == 250 else { fail("the carried cue did not apply to the new sketch") }
        session.deleteCue("wide")
        guard session.cues.isEmpty, (try? CueSheet.load(from: cuesPath))?.cues.isEmpty == true else {
            fail("deleting the cue did not empty the list and the file")
        }

        await checkSupersedeAcrossARunner(loader: loader)

        print("OllinLiveCoding sessiontest passed: the two-speed landing, param carry, variation carry, "
            + "edited defaults, supersede against both builds, the clean failure, the cue carry, and "
            + "supersede across a run being carried all hold.")
        exit(0)
    }

    /// Supersede with a runner under it, against both kinds of evaluation: one
    /// that carries the run and one that starts it over.
    ///
    /// The three things this pins that nothing without a runner can:
    ///
    /// - A newer evaluation wins whether or not either asked to carry the run,
    ///   so the older one's optimized build never swaps stale code onto a stage
    ///   that is mid-piece.
    /// - Both swaps of a two-speed evaluation carry it, so the silent second
    ///   one does not quietly restart the piece a fraction of a second after
    ///   the first one did not.
    /// - An evaluation that does not ask to carry the run still starts it over,
    ///   which is what every swap did before this and what a declaration edit
    ///   still does.
    @MainActor
    private static func checkSupersedeAcrossARunner(loader: SketchLoader) async {
        print("OllinLiveCoding sessiontest: supersede across a run being carried …")
        guard let view = HeadlessStage.view(side: 256), let device = view.device else {
            fail("no Metal device")
        }
        let session = SketchSession(keepClock: true, landsPlainBuildFirst: true)
        session.evaluate(loader, input: .source(HeadlessStage.pilingProbe(mark: 8)))
        await settle(session)
        guard let mounted = session.sketch else { fail("the probe did not mount") }
        let sink = FrameSink()
        mounted.extend(sink)
        let runner = SketchRunner(sketch: mounted, view: view, device: device)
        session.attach(runner)
        for _ in 0..<5 where !HeadlessStage.step(runner, view, mounted) {
            fail("the runner never drew a frame")
        }
        guard HeadlessStage.saved("frames", of: mounted) == 5 else {
            fail("the probe drew \(HeadlessStage.saved("frames", of: mounted) ?? -1) frames, expected five")
        }

        // Two carrying evaluations back to back. The newer one must be the one
        // on stage when the dust settles, through both of its builds.
        session.evaluate(loader, input: .source(HeadlessStage.pilingProbe(mark: 10)), keepRun: true)
        session.evaluate(loader, input: .source(HeadlessStage.pilingProbe(mark: 14)), keepRun: true)
        await settle(session)
        try? await Task.sleep(for: .seconds(4))   // let the superseded compiles finish and be refused
        guard let onStage = session.currentSketch else { fail("nothing on stage after the supersede") }
        onStage.extend(sink)
        guard mark(of: onStage) == 14 else {
            fail("a superseded evaluation landed last (the bar is \(mark(of: onStage) ?? .nan) wide)")
        }
        guard build(of: onStage) == 2 else {
            fail("the optimized build did not replace the plain one (build \(build(of: onStage)))")
        }
        // The run carried through both swaps: the state kept counting and the
        // pile is still on the canvas.
        guard HeadlessStage.saved("frames", of: onStage) == 5 else {
            fail("the run did not carry through both swaps (frame "
                + "\(HeadlessStage.saved("frames", of: onStage) ?? -1), expected the fifth)")
        }
        guard let frame = HeadlessStage.grab(sink, runner, view, onStage) else {
            fail("no frame came back after the supersede")
        }
        let carriedBars = HeadlessStage.bars(of: frame)
        guard carriedBars == 6 else {
            fail("the carried run shows \(carriedBars) bars after the supersede, expected six")
        }

        // And the other kind: an evaluation that does not ask to carry the run
        // starts it over, runner and all.
        session.evaluate(loader, input: .source(HeadlessStage.pilingProbe(mark: 18)))
        await settle(session)
        guard let restarted = session.currentSketch else { fail("nothing on stage after the restart") }
        restarted.extend(sink)
        guard let restartedFrame = HeadlessStage.grab(sink, runner, view, restarted) else {
            fail("no frame came back from the restarted run")
        }
        guard HeadlessStage.bars(of: restartedFrame) == 1,
              HeadlessStage.saved("frames", of: restarted) == 1 else {
            fail("an evaluation that did not ask to carry the run did not start it over "
                + "(\(HeadlessStage.bars(of: restartedFrame)) bars, frame "
                + "\(HeadlessStage.saved("frames", of: restarted) ?? -1))")
        }
    }

    /// The bar width the sketch on stage was compiled with, which is what tells
    /// two evaluations of the same probe apart.
    @MainActor
    private static func mark(of sketch: Sketch) -> Double? {
        guard let handle = sketch.parameters().first(where: { $0.name == "mark" }),
              case .number(let v) = handle.param.stored else { return nil }
        return v
    }

    /// Wait for the in-flight evaluation to resolve, its optimized build
    /// included.
    @MainActor
    private static func settle(_ session: SketchSession) async {
        await wait("the evaluation settling") { session.phase != .compiling && !session.isOptimizing }
    }

    @MainActor
    private static func wait(_ what: String, until done: @MainActor () -> Bool) async {
        for _ in 0..<6000 {   // a compile is seconds; cap at a minute
            if done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        fail("\(what) never happened")
    }

    /// The build level an instance reads in its `init`: 1 plain, 2 optimized.
    @MainActor
    private static func build(of sketch: Sketch) -> Double {
        guard let handle = sketch.parameters().first(where: { $0.name == "build" }),
              case .number(let v) = handle.param.stored else { return .nan }
        return v
    }

    @MainActor
    private static func value(of name: String, _ session: SketchSession) -> Double? {
        guard let handle = session.params.first(where: { $0.name == name }),
              case .number(let v) = handle.param.stored else { return nil }
        return v
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLiveCoding sessiontest FAILED: \(message)\n".utf8))
        exit(1)
    }
}
