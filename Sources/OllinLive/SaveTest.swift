import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLive --savetest`: the whole knob-write-back loop, headless.
///
/// It writes a sketch, compiles and loads it, turns knobs the way the inspector
/// does, writes those values into the `@Param` lines they came from, and then
/// compiles the file again and reads the knobs of a *fresh* sketch, with
/// nothing restored into it. That last step is the part no unit test can prove:
/// the text the rewriter produced has to compile, and the values have to arrive
/// as the sketch's own defaults.
///
/// No window and no render: nothing here draws.
enum SaveTest {
    @MainActor
    static func run() -> Never {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("OllinLive-savetest")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = (dir as NSString).appendingPathComponent("Sketch.swift")

        let source = """
        import Ollin

        /// A value the sketch works out for itself, which no knob may overwrite.
        let houseRadius = 90.0

        enum Style: String, CaseIterable, ParamOption { case dots, rings, meshLines }

        final class SaveTestSketch: Sketch {
            @Param(0...200) var radius = 120.0            // tuned by eye
            @Param(1...12) var rings = 5
            @Param var filled = true
            @Param var tint: Color = .purple
            @Param var style: Style = .dots
            @Param(x: 0...600, y: 0...600) var anchor = Vector2(300, 300)
            @Param(0...100) var margins = Insets.all(20)
            @Param(in: 0...50) var sizes = 5.0...20.0
            @Param var caption = "hello"
            @Param(count: 1...6) var inks = Palette(.red, .white)
            @Param(0...200) var borrowed = houseRadius
            @Param(0...600) var half = 600.0 / 2

            override var canvasSize: CanvasSize { .square(600) }

            override func draw() {
                background(.white)
                fill(tint)
                drawCircle(anchor.x, anchor.y, radius)
            }
        }
        """
        try! source.write(toFile: file, atomically: true, encoding: .utf8)

        func load() -> Sketch {
            switch SketchLoader(sketchPath: file).load() {
            case .success(let sketch): return sketch
            case .failure(let error): fail("the sketch would not compile: \(error)")
            }
        }

        print("OllinLive savetest: compile the sketch and turn its knobs …")
        let running = load()
        var handles: [String: ParamHandle] = [:]
        for handle in running.parameters() { handles[handle.name] = handle }
        check(handles.count == 12, "expected 12 knobs, got \(handles.count)")

        /// Turn one knob through its typed control, which is what an inspector
        /// row does, and hand back what the host would have recorded.
        func turn(_ name: String, _ change: (ParamControl) -> Void) -> (name: String, stored: ParamStored) {
            guard let handle = handles[name] else { fail("no knob named \(name)") }
            change(handle.control)
            return (name, handle.param.stored)
        }

        var tuned: [(name: String, stored: ParamStored)] = []
        tuned.append(turn("radius") { if case .slider(let c) = $0 { c.set(86.5) } })
        tuned.append(turn("rings") { if case .stepper(let c) = $0 { c.set(9) } })
        tuned.append(turn("filled") { if case .toggle(let c) = $0 { c.set(false) } })
        tuned.append(turn("tint") { if case .colorWell(let c) = $0 { c.set(Color(red: 0.2, green: 0.4, blue: 0.6)) } })
        tuned.append(turn("style") { if case .menu(let c) = $0 { c.set(2) } })
        tuned.append(turn("anchor") { if case .vector(let c) = $0 { c.set(Vector2(120, 480.5)) } })
        tuned.append(turn("margins") { if case .insets(let c) = $0 { c.set(Insets(top: 4, right: 8, bottom: 12, left: 16)) } })
        tuned.append(turn("sizes") { if case .range(let c) = $0 { c.set(12...34) } })
        tuned.append(turn("inks") { if case .swatches(let c) = $0 {
            c.set([.init(position: 0, color: .black), .init(position: 1, color: .orange)])
        } })
        // The two that cannot be written: one names a value the sketch works
        // out, the other is arithmetic.
        tuned.append(turn("borrowed") { if case .slider(let c) = $0 { c.set(150) } })
        tuned.append(turn("half") { if case .slider(let c) = $0 { c.set(200) } })

        print("OllinLive savetest: write them into the @Param lines …")
        let text = try! String(contentsOfFile: file, encoding: .utf8)
        let result = ParamWrite.writing(text, values: tuned)
        check(result.written.count == 9,
              "expected 9 knobs written, got \(result.written): \(result.refused)")
        check(result.refused.map(\.name).sorted() == ["borrowed", "half"],
              "the refusals should be borrowed and half, not \(result.refused.map(\.name))")
        check(result.refused.contains { $0.reason == .computed("houseRadius") },
              "the refusal should name what stands there: \(result.refused)")
        check(result.text.contains("// tuned by eye"), "the author's comment did not survive")
        check(result.text.contains("@Param(0...200) var borrowed = houseRadius"),
              "a refused knob's line must be left exactly as it was")
        check(result.text.contains(#"var caption = "hello""#),
              "a knob nobody turned must be left alone")
        try! result.text.write(toFile: file, atomically: true, encoding: .utf8)

        print("OllinLive savetest: compile it again and read a fresh sketch's knobs …")
        // Nothing is restored into this one: every value below is what the text
        // now declares.
        var fresh: [String: ParamHandle] = [:]
        for handle in load().parameters() { fresh[handle.name] = handle }

        func stored(_ name: String) -> ParamStored {
            guard let handle = fresh[name] else { fail("no knob named \(name) after the reload") }
            return handle.param.stored
        }
        check(stored("radius") == .number(86.5), "radius came back as \(stored("radius"))")
        check(stored("rings") == .number(9), "rings came back as \(stored("rings"))")
        check(stored("filled") == .boolean(false), "filled came back as \(stored("filled"))")
        check(stored("style") == .option("meshLines"), "style came back as \(stored("style"))")
        check(stored("anchor") == .vector(x: 120, y: 480.5), "anchor came back as \(stored("anchor"))")
        check(stored("margins") == .insets(top: 4, right: 8, bottom: 12, left: 16),
              "margins came back as \(stored("margins"))")
        check(stored("sizes") == .range(lower: 12, upper: 34), "sizes came back as \(stored("sizes"))")
        check(stored("caption") == .text("hello"), "an untouched knob changed: \(stored("caption"))")
        // A color is written to four decimals, finer than one channel step.
        guard case .color(let red, let green, let blue, _) = stored("tint") else {
            fail("tint is not a color any more")
        }
        check(abs(red - 0.2) < 0.001 && abs(green - 0.4) < 0.001 && abs(blue - 0.6) < 0.001,
              "tint came back as \(red), \(green), \(blue)")
        guard case .colors(let stops, _) = stored("inks") else { fail("inks is not a strip any more") }
        check(stops.count == 2 && stops[0].red == 0 && stops[1].green > 0.5,
              "the strip came back as \(stops)")
        // The two refusals stand exactly where the author left them.
        check(stored("borrowed") == .number(90), "a refused knob moved: \(stored("borrowed"))")
        check(stored("half") == .number(300), "a refused knob moved: \(stored("half"))")

        print("OllinLive savetest: PASS: 9 knobs were written into the file, the file still "
            + "compiles, a fresh sketch carries them as its own defaults, and the two that "
            + "are worked out were named rather than overwritten.")
        exit(0)
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive savetest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
