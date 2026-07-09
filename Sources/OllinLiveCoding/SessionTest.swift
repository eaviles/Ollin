import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLiveCoding --sessiontest`: headless checks of the shared
/// `SketchSession` semantics both live hosts depend on (no window; the swaps
/// exercised here stop at the first mount, which is exactly where the
/// param-carry and supersede logic live):
///
/// - A recorded (user-dragged) param value is re-applied to the next
///   evaluation's sketch, while an *untouched* param takes the buffer's edited
///   default.
/// - A navigated variation seed carries the same way, so an edit doesn't
///   reshuffle the composition the user was working on.
/// - Two back-to-back evaluations resolve to the newer one (supersede), never
///   the stale one.
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

        func source(radiusDefault: Double, speedDefault: Double) -> String {
            """
            import Ollin
            final class SessionSketch: Sketch {
                @Param(10...400) var radius = \(radiusDefault)
                @Param(0...9) var speed = \(speedDefault)
                override func draw() { background(.white) }
            }
            """
        }

        let session = SketchSession(keepClock: true)

        print("OllinLiveCoding sessiontest: first evaluation …")
        session.evaluate(loader, input: .source(source(radiusDefault: 100, speedDefault: 1)))
        await settle(session)
        guard case .idle = session.phase, session.sketch != nil else {
            fail("first evaluation didn't land: \(session.phase)")
        }
        guard session.reloadCount == 0, session.lastBuildSeconds == nil else {
            fail("first mount miscounted as a reload")
        }
        guard value(of: "radius", session) == 100, value(of: "speed", session) == 1 else {
            fail("first evaluation's params read wrong")
        }

        print("OllinLiveCoding sessiontest: param carry across an evaluation …")
        session.recordParam("radius", .number(42))   // the user dragged this knob
        session.evaluate(loader, input: .source(source(radiusDefault: 300, speedDefault: 2)))
        await settle(session)
        guard value(of: "radius", session) == 42 else {
            fail("the dragged knob snapped back to \(value(of: "radius", session) ?? .nan)")
        }
        guard value(of: "speed", session) == 2 else {
            fail("the untouched param kept a stale default instead of the edited one")
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
        // Grace for the superseded compile to finish and be refused.
        try? await Task.sleep(for: .seconds(4))
        guard value(of: "speed", session) == 7 else {
            fail("a superseded evaluation landed last (speed = \(value(of: "speed", session) ?? .nan))")
        }

        print("OllinLiveCoding sessiontest passed: param carry, variation carry, edited defaults, and supersede hold.")
        exit(0)
    }

    /// Wait for the in-flight evaluation to resolve.
    @MainActor
    private static func settle(_ session: SketchSession) async {
        for _ in 0..<600 {   // compile is seconds; cap at a minute
            if session.phase != .compiling { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        fail("evaluation never settled")
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
