import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinLive --dragtest`: the whole shape-drag loop, headless.
///
/// It writes a sketch, compiles and loads it, draws a frame, picks the shape at
/// a known place, moves it by editing the file the way a released drag does,
/// then compiles and draws again and finds the shape at its new place. That is
/// the part no unit test can prove on its own: the site a running sketch
/// reports has to match the numbers standing in the file it was built from.
///
/// No window and no render: a frame is recorded, not drawn to a screen.
enum DragTest {
    @MainActor
    static func run() -> Never {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("OllinLive-dragtest")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = (dir as NSString).appendingPathComponent("Sketch.swift")
        let name = "Sketch.swift"

        let source = """
        import Ollin

        final class DragTestSketch: Sketch {
            override var canvasSize: CanvasSize { .square(600) }
            override func draw() {
                background(.white)
                fill(.black)
                drawCircle(200, 200, 60)          // the one that moves
                drawRect(400, 400, 120, 80)
                drawCircle(width / 2, 500, 30)    // no numbers to move
            }
        }
        """
        try! source.write(toFile: file, atomically: true, encoding: .utf8)
        // Where the moving circle stands in the text above.
        let circleLine = 8

        /// Compile the file, draw one frame with tracking on, and hand back the
        /// sketch to ask about. The frame is the real one an export renders, so
        /// what the pick answers is what a window would have shown.
        func drawOnce() -> Sketch {
            switch SketchLoader(sketchPath: file).load() {
            case .success(let sketch):
                sketch.tracksSourceSites = true
                guard OllinApp.image(of: sketch, frame: 0) != nil else {
                    fail("the frame did not render")
                }
                return sketch
            case .failure(let error):
                fail("the sketch would not compile: \(error)")
            }
        }

        print("OllinLive dragtest: compile, draw, and find the shape under the pointer …")
        let first = drawOnce()
        guard let pick = first.sourcePick(at: Vector2(200, 200)) else {
            fail("nothing was found where the circle was drawn")
        }
        check(pick.site.fileName == name, "the shape says it comes from \(pick.site.fileName)")
        check(pick.site.line == circleLine,
              "the circle is on line \(circleLine), not \(pick.site.line)")
        check(pick.site.move == .xy, "the circle should be placed by two bare numbers")

        // A drag of 100 by 50 canvas points, with no transform in the way.
        let delta = pick.numbersDelta(forCanvasDelta: Vector2(100, 50))
        check(abs(delta.x - 100) < 1e-9 && abs(delta.y - 50) < 1e-9,
              "an untransformed drag should move the numbers by the same amount")

        print("OllinLive dragtest: write the new numbers into the file …")
        let text = try! String(contentsOfFile: file, encoding: .utf8)
        guard let edited = try? SourceEdit.moving(text, line: pick.site.line,
                                                  column: pick.site.column,
                                                  move: pick.site.move, by: delta) else {
            fail("the edit was refused")
        }
        check(edited.contains("drawCircle(300, 250, 60)"),
              "the circle's numbers did not become 300, 250")
        check(edited.contains("// the one that moves"), "the author's comment did not survive")
        check(edited.contains("drawRect(400, 400, 120, 80)"), "another call was touched")
        try! edited.write(toFile: file, atomically: true, encoding: .utf8)

        print("OllinLive dragtest: reload, and find the shape where the drag left it …")
        let second = drawOnce()
        check(second.sourcePick(at: Vector2(200, 200)) == nil, "the circle is still where it was")
        guard let moved = second.sourcePick(at: Vector2(300, 250)) else {
            fail("the circle is not where the drag left it")
        }
        check(moved.site.line == circleLine, "the moved circle should still be line \(circleLine)")

        // A shape placed by an expression has no number to change, and says so
        // by naming what stands there.
        print("OllinLive dragtest: a computed coordinate is refused by name …")
        guard let computed = second.sourcePick(at: Vector2(300, 500)) else {
            fail("the computed circle was not found")
        }
        do {
            let now = try! String(contentsOfFile: file, encoding: .utf8)
            _ = try SourceEdit.moving(now, line: computed.site.line, column: computed.site.column,
                                      move: computed.site.move, by: Vector2(10, 10))
            fail("moving a computed coordinate should have been refused")
        } catch let failure as SourceEdit.Failure {
            check(failure == .computed(argument: "width / 2"),
                  "the refusal should name width / 2, not \(failure)")
            let sentence = ShapeDragController.sentence(for: failure, at: computed.site.line,
                                                        in: name)
            check(sentence.contains("width / 2"), "the message should name what stands there")
        } catch {
            fail("unexpected error: \(error)")
        }

        // The controller the canvas drives, put through a whole gesture: the
        // modifier down, a press on the shape, a drag, and the release that
        // writes. This is the host half, with no window in the way.
        print("OllinLive dragtest: the same gesture, through the controller …")
        try! source.write(toFile: file, atomically: true, encoding: .utf8)
        let host = StubHost(sketch: drawOnce(), path: file)
        let controller = ShapeDragController(session: host)

        controller.modifierChanged(held: true, at: Vector2(200, 200))
        check(!controller.outline.isEmpty, "holding the modifier should outline the shape")
        check(controller.label == "\(name):\(circleLine)",
              "the outline should be labeled \(name):\(circleLine), not \(controller.label ?? "nothing")")

        check(!controller.dragBegan(at: Vector2(50, 50)),
              "a press on empty canvas belongs to the sketch")
        check(controller.dragBegan(at: Vector2(200, 200)), "the press on the circle was not taken")
        controller.dragMoved(to: Vector2(300, 250))
        check(controller.isDragging && controller.offset == Vector2(100, 50),
              "the drag did not carry its distance")
        controller.dragEnded()
        let after = try! String(contentsOfFile: file, encoding: .utf8)
        check(after.contains("drawCircle(300, 250, 60)"),
              "the released drag did not write the new numbers")
        check(controller.note == nil, "a drag that worked should say nothing")

        // And the drag that cannot be written says why, without touching the file.
        _ = controller.dragBegan(at: Vector2(300, 500))
        controller.dragMoved(to: Vector2(320, 500))
        controller.dragEnded()
        check(controller.note?.contains("width / 2") == true,
              "the refusal should name what stands there, not \(controller.note ?? "nothing")")
        check(try! String(contentsOfFile: file, encoding: .utf8) == after,
              "a refused drag must leave the file alone")

        print("OllinLive dragtest: PASS: the shape was found, moved by editing the file, "
            + "found again where the drag left it, and a whole gesture through the "
            + "controller wrote the same edit.")
        exit(0)
    }

    /// Stands in for the live session: the sketch that is running, and the file
    /// it came from.
    @MainActor
    private final class StubHost: ShapeDragHost {
        var currentSketch: Sketch?
        let sourcePath: String
        init(sketch: Sketch, path: String) {
            self.currentSketch = sketch
            self.sourcePath = path
        }
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive dragtest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
