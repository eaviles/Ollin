import Foundation
import Ollin

/// `swift run OllinLive --paramtest` — a headless check of the `@Param` model:
/// reflection-based discovery, auto-derived vs explicit labels, declaration
/// order, ranges, and value clamping. Needs no window.
enum ParamTest {
    final class Subject: Sketch {
        @Param(0...200) var radius = 120.0        // auto label "Radius"
        @Param(0...10) var noiseScale = 3.0       // auto label "Noise Scale"
        @Param("Tempo", 0.1...4) var speed = 1.0  // explicit label "Tempo"
    }

    @MainActor
    static func run() -> Never {
        let subject = Subject()
        let params = subject.parameters()

        check(params.count == 3, "expected 3 params, got \(params.count)")
        check(params.map(\.name) == ["radius", "noiseScale", "speed"],
              "names/order wrong: \(params.map(\.name))")
        check(params.map(\.label) == ["Radius", "Noise Scale", "Tempo"],
              "labels wrong: \(params.map(\.label))")
        check(params[0].param.range == 0...200, "radius range wrong")

        // Clamping: out-of-range writes are clamped to the range.
        subject.radius = 999
        check(subject.radius == 200, "high clamp failed: \(subject.radius)")
        subject.radius = -50
        check(subject.radius == 0, "low clamp failed: \(subject.radius)")

        // Setting through the discovered handle is seen by the sketch property
        // (same backing instance) — this is how the inspector drives the sketch.
        params[2].param.wrappedValue = 2.5
        check(subject.speed == 2.5, "handle write not reflected: \(subject.speed)")

        print("OllinLive paramtest: PASS — \(params.count) params discovered, "
            + "labels + clamping + handle writes correct.")
        exit(0)
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            FileHandle.standardError.write(Data("OllinLive paramtest: FAIL — \(message())\n".utf8))
            exit(1)
        }
    }
}
