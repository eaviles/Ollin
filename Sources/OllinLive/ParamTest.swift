import Foundation
import Ollin

/// `swift run OllinLive --paramtest`: a headless check of the `@Param` model.
/// Reflection-based discovery, auto-derived vs explicit labels, declaration
/// order, ranges, value clamping and step snapping, the typed control family
/// (slider / stepper / toggle / menu / color well), group + icon metadata, and
/// the stored-value round-trip the hosts persist across reloads. Needs no window.
enum ParamTest {
    enum Style: String, CaseIterable, ParamOption { case dots, rings, meshLines }

    final class Subject: Sketch {
        @Param(0...200) var radius = 120.0                        // auto label "Radius"
        @Param(0...10) var noiseScale = 3.0                       // auto label "Noise Scale"
        @Param("Tempo", 0.1...4) var speed = 1.0                  // explicit label "Tempo"
        @Param(0...1, step: 0.25) var quantized = 0.6             // snaps to 0.25s
        @Param(1...12, icon: "circle.grid.2x2", group: "Layout") var rings = 5
        @Param("Visible", group: "Layout") var visible = true
        @Param var tint: Color = .purple
        @Param var style: Style = .dots
        @Param(x: 0...1080, y: 0...400) var anchor = Vector2(540, 200)
        @Param(x: -1...1, y: -1...1, z: 0...10) var eye = Vector3(0, 0, 5)
        @Param(0...100_000, style: .field) var iterations = 2000.0
    }

    @MainActor
    static func run() -> Never {
        let subject = Subject()
        let params = subject.parameters()

        check(params.count == 11, "expected 11 params, got \(params.count)")
        check(params.map(\.name) == ["radius", "noiseScale", "speed", "quantized",
                                     "rings", "visible", "tint", "style", "anchor",
                                     "eye", "iterations"],
              "names/order wrong: \(params.map(\.name))")
        check(params.map(\.label) == ["Radius", "Noise Scale", "Tempo", "Quantized",
                                      "Rings", "Visible", "Tint", "Style", "Anchor",
                                      "Eye", "Iterations"],
              "labels wrong: \(params.map(\.label))")
        check(params[4].icon == "circle.grid.2x2", "icon metadata lost")
        check(params[4].group == "Layout" && params[5].group == "Layout" && params[0].group == nil,
              "group metadata wrong")

        // Clamping: out-of-range writes are clamped to the range.
        subject.radius = 999
        check(subject.radius == 200, "high clamp failed: \(subject.radius)")
        subject.radius = -50
        check(subject.radius == 0, "low clamp failed: \(subject.radius)")

        // A step snaps every write to the nearest multiple from the lower bound.
        subject.quantized = 0.6
        check(subject.quantized == 0.5, "step snap failed: \(subject.quantized)")

        // The typed controls: kind follows from the property's type, and setting
        // through the discovered handle is seen by the sketch property (same
        // backing instance); this is how the inspector drives the sketch.
        guard case .slider(let slider) = params[2].control else { fatal("speed isn't a slider") }
        check(slider.range == 0.1...4, "slider range wrong")
        slider.set(2.5)
        check(subject.speed == 2.5, "handle write not reflected: \(subject.speed)")

        guard case .stepper(let stepper) = params[4].control else { fatal("rings isn't a stepper") }
        check(stepper.range == 1...12, "stepper range wrong")
        stepper.set(99)
        check(subject.rings == 12, "Int clamp failed: \(subject.rings)")

        guard case .toggle(let toggle) = params[5].control else { fatal("visible isn't a toggle") }
        toggle.set(false)
        check(subject.visible == false, "toggle write not reflected")

        guard case .colorWell(let well) = params[6].control else { fatal("tint isn't a color well") }
        well.set(.orange)
        check(subject.tint == .orange, "color write not reflected")

        guard case .vector(let vector) = params[8].control else { fatal("anchor isn't a vector") }
        vector.set(Vector2(2000, -10))
        check(subject.anchor == Vector2(1080, 0), "per-axis clamp failed: \(subject.anchor)")

        guard case .vector3(let xyz) = params[9].control else { fatal("eye isn't a vector3") }
        xyz.set(Vector3(9, -9, -1))
        check(subject.eye == Vector3(1, -1, 0), "vector3 per-axis clamp failed: \(subject.eye)")

        guard case .slider(let field) = params[10].control else { fatal("iterations isn't a slider kind") }
        check(field.style == .field, "field style lost")

        guard case .menu(let menu) = params[7].control else { fatal("style isn't a menu") }
        check(menu.options == ["Dots", "Rings", "Mesh Lines"], "menu labels wrong: \(menu.options)")
        menu.set(2)
        check(subject.style == .meshLines, "menu write not reflected")
        check(menu.get() == 2, "menu selection readback wrong")

        // The stored round-trip the hosts persist across reloads.
        let fresh = Subject()
        for handle in fresh.parameters() {
            let match = params.first { $0.name == handle.name }!
            handle.param.restore(match.param.stored)
        }
        check(fresh.speed == 2.5 && fresh.rings == 12 && fresh.visible == false
                && fresh.tint == .orange && fresh.style == .meshLines
                && fresh.anchor == Vector2(1080, 0),
              "stored round-trip lost a value")
        // A payload of the wrong kind is ignored, keeping the current value
        // (the clamp checks above left radius at 0, carried by the round-trip).
        fresh.parameters()[0].param.restore(.boolean(true))
        check(fresh.radius == 0, "mismatched restore should be ignored")

        print("ParamTest: PASS. \(params.count) params discovered; labels, groups, "
            + "clamping, steps, typed controls, and stored round-trips correct.")
        exit(0)
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            FileHandle.standardError.write(Data("ParamTest: FAIL: \(message())\n".utf8))
            exit(1)
        }
    }

    private static func fatal(_ message: String) -> Never {
        FileHandle.standardError.write(Data("ParamTest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
