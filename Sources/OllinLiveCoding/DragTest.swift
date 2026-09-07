import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLiveCoding --dragtest`: the shape drag on the stage, headless.
///
/// The live host's own drag test proves the loop from a frame to the file and
/// back. This one proves the half that is the performance host's: a released
/// drag lands in the *buffer* and nowhere else, the buffer is evaluated so the
/// shape is found where the drag left it, and a drag is refused while the
/// buffer is not the text the stage was built from, whether the code was
/// typed on and not evaluated or the last drag is still compiling, so a drag
/// can never add to numbers the stage has not shown. The bracket key goes the
/// same way, and a coordinate that is a parameter's name sets the parameter
/// without an evaluation at all.
///
/// No window and no render to a screen: a frame is recorded, not shown.
enum DragTest {
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
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("OllinLiveCoding-dragtest")
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = (dir as NSString).appendingPathComponent("Sketch.swift")
        let name = "Sketch.swift"

        let source = """
        import Ollin

        final class StageDragSketch: Sketch {
            @Param(0 ... 600) var cx = 300.0
            override var canvasSize: CanvasSize { .square(600) }
            override func draw() {
                background(.white)
                fill(.black)
                drawCircle(200, 200, 60)          // the one that moves
                drawRect(400, 400, 120, 80)
                drawCircle(cx, 100, 25)           // placed by a parameter
            }
        }
        """
        let circleLine = 9
        try! source.write(toFile: file, atomically: true, encoding: .utf8)

        // The crash net goes to a scratch folder, never the real support one.
        let session = PerformanceSession(
            fileURL: URL(fileURLWithPath: file),
            supportDirectory: URL(fileURLWithPath: (dir as NSString).appendingPathComponent("Support")))
        let controller = ShapeDragController(session: session, hostName: "OllinLiveCoding")

        func onDisk() -> String { try! String(contentsOfFile: file, encoding: .utf8) }

        /// The sketch on stage, with tracking on and one frame recorded, so
        /// the pick answers what the stage would have shown.
        func staged() -> Sketch {
            guard let sketch = session.core.currentSketch else { fail("nothing is on stage") }
            sketch.tracksSourceSites = true
            guard OllinApp.image(of: sketch, frame: 0) != nil else { fail("the frame did not render") }
            return sketch
        }

        print("OllinLiveCoding dragtest: open the file into the buffer and evaluate it …")
        session.start()
        await settle(session)
        guard case .idle = session.core.phase else { fail("the first evaluation failed: \(session.core.phase)") }
        _ = staged()

        print("OllinLiveCoding dragtest: a drag on the stage writes the buffer and evaluates it …")
        controller.modifierChanged(held: true, at: Vector2(200, 200))
        check(controller.isArmed, "holding the modifier should arm the drag")
        check(controller.label == "\(name):\(circleLine)",
              "the outline should be labeled \(name):\(circleLine), not \(controller.label ?? "nothing")")
        check(controller.dragBegan(at: Vector2(200, 200)), "the press on the circle was not taken")
        controller.dragMoved(to: Vector2(300, 250))
        controller.dragEnded()
        let dragged = session.editor.text()
        check(dragged.contains("drawCircle(300, 250, 60)"), "the released drag did not write the buffer")
        check(dragged.contains("// the one that moves"), "the author's comment did not survive")
        check(onDisk() == source, "a drag must never write the file; Command-S is the only thing that does")
        check(session.core.phase == .compiling, "the drag should have evaluated the buffer")
        check(controller.note == nil, "a drag that worked should say nothing, not \(controller.note ?? "")")

        print("OllinLiveCoding dragtest: a second drag while that one compiles is refused …")
        // The stage still draws the circle where it was, so the press is taken;
        // the release is where the refusal lands.
        check(controller.dragBegan(at: Vector2(200, 200)), "the press on the old circle was not taken")
        controller.dragMoved(to: Vector2(220, 200))
        controller.dragEnded()
        check(controller.note?.contains("still being built") == true,
              "the refusal should say the stage is still being built, not \(controller.note ?? "nothing")")
        check(session.editor.text() == dragged, "a refused drag must leave the buffer alone")

        print("OllinLiveCoding dragtest: the shape is found where the drag left it …")
        await settle(session)
        let moved = staged()
        check(moved.sourcePick(at: Vector2(200, 200)) == nil, "the circle is still where it was")
        guard let found = moved.sourcePick(at: Vector2(300, 250)) else {
            fail("the circle is not where the drag left it")
        }
        check(found.site.line == circleLine, "the moved circle should still be line \(circleLine)")

        print("OllinLiveCoding dragtest: a drag over code typed since the last evaluation is refused …")
        let typed = dragged + "// a line the stage has not seen\n"
        session.editor.replaceBuffer(with: typed)
        controller.modifierChanged(held: true, at: Vector2(300, 250))
        check(controller.dragBegan(at: Vector2(300, 250)), "the press on the moved circle was not taken")
        controller.dragMoved(to: Vector2(310, 250))
        controller.dragEnded()
        check(controller.note?.contains("Evaluate it") == true,
              "the refusal should ask for an evaluation, not \(controller.note ?? "nothing")")
        check(session.editor.text() == typed, "a refused drag must leave the typed buffer alone")
        check(session.core.phase != .compiling, "a refused drag must not evaluate")
        // Evaluated, the same drag goes through.
        session.evaluate()
        await settle(session)
        _ = staged()
        controller.modifierChanged(held: true, at: Vector2(300, 250))
        check(controller.dragBegan(at: Vector2(300, 250)), "the press was not taken after the evaluation")
        controller.dragMoved(to: Vector2(310, 250))
        controller.dragEnded()
        check(session.editor.text().contains("drawCircle(310, 250, 60)"),
              "once evaluated, the drag should write the buffer again")
        await settle(session)

        print("OllinLiveCoding dragtest: a coordinate that is a parameter's name sets the parameter …")
        let byParameter = staged()
        controller.modifierChanged(held: true, at: Vector2(300, 100))
        check(controller.dragBegan(at: Vector2(300, 100)), "the press on the parameter circle was not taken")
        controller.dragMoved(to: Vector2(360, 100))
        let bufferBefore = session.editor.text()
        controller.dragEnded()
        check(session.editor.text() == bufferBefore, "a drag that only sets a parameter must leave the buffer alone")
        check(session.core.phase != .compiling, "setting a parameter needs no evaluation")
        guard let tuned = session.core.tunedParams.first(where: { $0.name == "cx" }),
              case .number(let value) = tuned.stored else {
            fail("cx should be recorded as tuned")
        }
        check(abs(value - 360) < 1e-6, "cx should now hold 360, not \(value)")
        guard let cx = byParameter.parameters().first(where: { $0.name == "cx" }),
              case .slider(let slider) = cx.control else {
            fail("the sketch lost its cx parameter")
        }
        check(abs(slider.read() - 360) < 1e-6, "the running sketch should read 360, not \(slider.read())")

        print("OllinLiveCoding dragtest: the bracket key reorders through the buffer …")
        let overlapping = """
        import Ollin

        final class StageReorderSketch: Sketch {
            override var canvasSize: CanvasSize { .square(600) }
            override func draw() {
                background(.white)
                fill(.black)
                drawCircle(200, 300, 80)      // under
                fill(.red)
                drawCircle(260, 300, 80)      // over
                drawRect(500, 500, 40, 40)
            }
        }
        """
        let underLine = 8, overLine = 10
        session.editor.setText(overlapping)
        session.evaluate()
        await settle(session)
        let stacked = staged()
        check(stacked.sourcePick(at: Vector2(240, 300))?.site.line == overLine,
              "the later circle should be on top")
        controller.modifierChanged(held: true, at: Vector2(140, 300))
        check(controller.label == "\(name):\(underLine)",
              "the uncovered edge should outline the under circle, not \(controller.label ?? "nothing")")
        let noteBefore = controller.note   // an earlier refusal's note lingers a few seconds
        check(controller.reorderHovered(.forward), "the key should be taken while a shape is outlined")
        check(session.editor.text().contains("drawCircle(260, 300, 80)      // over\n        fill(.black)\n        drawCircle(200, 300, 80)      // under\n        fill(.red)\n        drawRect"),
              "the under circle should now follow the over one, carrying its fill:\n\(session.editor.text())")
        check(controller.note == noteBefore, "a move that worked should say nothing new")
        check(session.core.phase == .compiling, "the reorder should have evaluated the buffer")
        await settle(session)
        let swapped = staged()
        check(swapped.sourcePick(at: Vector2(240, 300))?.site.line == underLine + 2,
              "after the move the once-covered circle should be on top")
        controller.modifierChanged(held: true, at: Vector2(240, 300))
        check(controller.reorderHovered(.backward), "the key back should be taken")
        check(session.editor.text() == overlapping, "moving back should leave the buffer exactly as written")
        await settle(session)

        controller.modifierChanged(held: false, at: nil)
        check(!controller.isArmed, "letting go of the modifier should disarm the drag")
        check(onDisk() == source, "through all of it the file on disk must stay as it was written")

        print("OllinLiveCoding dragtest: PASS: the drag wrote the buffer and evaluated it, the file "
            + "on disk stayed put, the shape was found where the drag left it, a drag over "
            + "unevaluated code and a drag mid-compile were both refused by name, a parameter's "
            + "name set the parameter with no evaluation, and the bracket key reordered through "
            + "the buffer and back.")
        exit(0)
    }

    /// Wait for the in-flight evaluation to resolve.
    @MainActor
    private static func settle(_ session: PerformanceSession) async {
        for _ in 0..<600 {   // a compile is seconds; cap at a minute
            if session.core.phase != .compiling { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        fail("evaluation never settled")
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLiveCoding dragtest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
