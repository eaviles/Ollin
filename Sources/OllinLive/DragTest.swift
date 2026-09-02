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
/// The same loop then resizes a shape by a corner, turns a line by its parameter,
/// and drags one placed by a parameter's name, which sets the parameter instead.
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
            @Param(0 ... 600) var cx = 300.0
            override var canvasSize: CanvasSize { .square(600) }
            override func draw() {
                background(.white)
                fill(.black)
                drawCircle(200, 200, 60)          // the one that moves
                drawRect(400, 400, 120, 80)
                drawCircle(width / 2, 500, 30)    // no numbers to move
                drawCircle(cx, 100, 25)           // placed by a parameter
                stroke(.black)
                strokeWeight(6)
                drawLine(80, 400, 220, 400)
            }
        }
        """
        // Where each of them stands in the text above.
        let circleLine = 9, parameterLine = 12, lineLine = 15

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

        /// Put the sketch back the way it was written, for a phase that wants a
        /// file nothing has edited yet.
        func restore() -> Sketch {
            try! source.write(toFile: file, atomically: true, encoding: .utf8)
            return drawOnce()
        }

        func text() -> String { try! String(contentsOfFile: file, encoding: .utf8) }

        print("OllinLive dragtest: compile, draw, and find the shape under the pointer …")
        let first = restore()
        guard let pick = first.sourcePick(at: Vector2(200, 200)) else {
            fail("nothing was found where the circle was drawn")
        }
        check(pick.site.fileName == name, "the shape says it comes from \(pick.site.fileName)")
        check(pick.site.line == circleLine,
              "the circle is on line \(circleLine), not \(pick.site.line)")
        check(pick.site.move == .xy(radius: 2),
              "the circle should be placed by two bare numbers and sized by one")

        // A drag of 100 by 50 canvas points, with no transform in the way.
        let delta = pick.numbersDelta(forCanvasDelta: Vector2(100, 50))
        check(abs(delta.x - 100) < 1e-9 && abs(delta.y - 50) < 1e-9,
              "an untransformed drag should move the numbers by the same amount")

        print("OllinLive dragtest: write the new numbers into the file …")
        guard let edited = try? SourceEdit.moving(text(), line: pick.site.line,
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
            _ = try SourceEdit.moving(text(), line: computed.site.line, column: computed.site.column,
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

        // A corner handle scales the size numbers and leaves the position alone.
        print("OllinLive dragtest: a corner handle resizes the shape …")
        let third = restore()
        guard let circle = third.sourcePick(at: Vector2(200, 200)) else {
            fail("the circle was not found for the resize")
        }
        check(circle.handles.filter { $0.kind == .resize }.count == 4,
              "a circle placed by its middle should offer four corners")
        guard let corner = circle.handle(at: Vector2(260, 260), within: 4) else {
            fail("no corner handle stands at the bottom right of the circle")
        }
        check(corner.kind == .resize, "the corner should be a resize handle")
        guard let grown = circle.sizeFactor(for: corner, canvasDelta: Vector2(30, 30)) else {
            fail("the corner gave no factor")
        }
        check(abs(grown.x - 1.5) < 1e-9, "60 pulled out to 90 is one and a half, not \(grown.x)")
        let resized = try! SourceEdit.resizing(text(), line: circle.site.line,
                                               column: circle.site.column,
                                               move: circle.site.move, by: grown)
        check(resized.contains("drawCircle(200, 200, 90)"),
              "the resize should have written a radius of 90")
        // The shape a resize cannot touch says so rather than writing anything.
        guard let straight = third.sourcePick(at: Vector2(150, 400)) else {
            fail("the line was not found")
        }
        do {
            _ = try SourceEdit.resizing(text(), line: straight.site.line,
                                        column: straight.site.column,
                                        move: straight.site.move, by: Vector2(2, 2))
            fail("a line has no size argument, so a resize should have been refused")
        } catch let failure as SourceEdit.Failure {
            check(failure == .nothingToSize, "the refusal should be nothingToSize, not \(failure)")
        } catch {
            fail("unexpected error: \(error)")
        }

        // The knob above a two-ended shape swings it about its own middle.
        print("OllinLive dragtest: the turn knob swings a line about its middle …")
        check(straight.site.line == lineLine, "the line is on line \(lineLine), not \(straight.site.line)")
        guard let knob = straight.handles.first(where: { $0.kind == .turn }) else {
            fail("a line should offer a turn knob")
        }
        check(straight.handles.allSatisfy { $0.kind == .turn },
              "a line has no size on its line, so it should offer no corner")
        let quarter = straight.turnAngle(from: knob.position, to: Vector2(181, 400))
        check(abs(quarter - .pi / 2) < 1e-6,
              "a quarter turn should read as \(Double.pi / 2), not \(quarter)")
        let turned = try! SourceEdit.turning(text(), line: straight.site.line,
                                             column: straight.site.column,
                                             move: straight.site.move, by: quarter)
        check(turned.contains("drawLine(150, 330, 150, 470)"),
              "the turned line should stand upright about its middle")

        // A coordinate that is a parameter's name adjusts the parameter, and the file stays
        // as it was: there is no number on that line to write.
        print("OllinLive dragtest: a coordinate that is a parameter's name sets the parameter …")
        guard let byParameter = third.sourcePick(at: Vector2(300, 100)) else {
            fail("the circle placed by a parameter was not found")
        }
        check(byParameter.site.line == parameterLine, "the parameter circle is on line \(parameterLine)")
        let plan = try! SourceEdit.planningMove(text(), line: byParameter.site.line,
                                                column: byParameter.site.column,
                                                move: byParameter.site.move, by: Vector2(40, 15))
        check(plan.refused == nil, "a bare name is not a refusal")
        check(plan.names.count == 1 && plan.names[0].name == "cx" && plan.names[0].isAcross,
              "the plan should name cx as the x coordinate, not \(plan.names)")
        check(abs(plan.names[0].delta - 40) < 1e-9, "cx should be asked to move by 40")
        check(plan.text.contains("drawCircle(cx, 115, 25)"),
              "the y coordinate is a number, so it should have been written")

        // The controller the canvas drives, put through a whole gesture: the
        // modifier down, a press on the shape, a drag, and the release that
        // writes. This is the host half, with no window in the way.
        print("OllinLive dragtest: the same gesture, through the controller …")
        let host = StubHost(sketch: restore(), path: file)
        let controller = ShapeDragController(session: host)

        controller.modifierChanged(held: true, at: Vector2(200, 200))
        check(!controller.outline.isEmpty, "holding the modifier should outline the shape")
        check(controller.handles.count == 4, "the circle should show its four corners")
        check(controller.label == "\(name):\(circleLine)",
              "the outline should be labeled \(name):\(circleLine), not \(controller.label ?? "nothing")")

        check(!controller.dragBegan(at: Vector2(50, 50)),
              "a press on empty canvas belongs to the sketch")
        check(controller.dragBegan(at: Vector2(200, 200)), "the press on the circle was not taken")
        controller.dragMoved(to: Vector2(300, 250))
        check(controller.isDragging && controller.offset == Vector2(100, 50),
              "the drag did not carry its distance")
        controller.dragEnded()
        let after = text()
        check(after.contains("drawCircle(300, 250, 60)"),
              "the released drag did not write the new numbers")
        check(controller.note == nil, "a drag that worked should say nothing")

        // And the drag that cannot be written says why, without touching the file.
        _ = controller.dragBegan(at: Vector2(300, 500))
        controller.dragMoved(to: Vector2(320, 500))
        controller.dragEnded()
        check(controller.note?.contains("width / 2") == true,
              "the refusal should name what stands there, not \(controller.note ?? "nothing")")
        check(text() == after, "a refused drag must leave the file alone")

        // A corner grabbed through the controller, on the file as it now stands.
        print("OllinLive dragtest: a corner drag, through the controller …")
        host.currentSketch = restore()
        controller.modifierChanged(held: true, at: Vector2(200, 200))
        controller.pointerHovered(at: Vector2(260, 260))
        check(controller.handleUnderPointer?.kind == .resize,
              "the pointer on a corner should find its handle")
        check(controller.dragBegan(at: Vector2(260, 260)), "the press on the corner was not taken")
        controller.dragMoved(to: Vector2(290, 290))
        controller.dragEnded()
        check(text().contains("drawCircle(200, 200, 90)"),
              "the corner drag did not write the new radius")

        // And the parameter drag, which writes nothing and sets the parameter instead.
        print("OllinLive dragtest: a parameter drag, through the controller …")
        let parameterSketch = restore()
        host.currentSketch = parameterSketch
        controller.modifierChanged(held: true, at: Vector2(300, 100))
        check(controller.dragBegan(at: Vector2(300, 100)), "the press on the parameter circle was not taken")
        controller.dragMoved(to: Vector2(360, 100))
        controller.dragEnded()
        check(text() == source, "a drag that only sets a parameter must leave the file alone")
        check(host.recorded["cx"] != nil, "the changed parameter should have been recorded")
        guard let cx = parameterSketch.parameters().first(where: { $0.name == "cx" }),
              case .slider(let slider) = cx.control else {
            fail("the sketch lost its cx parameter")
        }
        check(abs(slider.read() - 360) < 1e-6, "cx should now hold 360, not \(slider.read())")

        print("OllinLive dragtest: PASS: the shape was found, moved by editing the file, "
            + "found again where the drag left it, resized by a corner, turned about its "
            + "middle, and a parameter's name set the parameter instead of the text.")
        exit(0)
    }

    /// Stands in for the live session: the sketch that is running, the file it
    /// came from, and the tuned parameters it would carry across a reload.
    @MainActor
    private final class StubHost: ShapeDragHost {
        var currentSketch: Sketch?
        let sourcePath: String
        var recorded: [String: ParamStored] = [:]
        init(sketch: Sketch, path: String) {
            self.currentSketch = sketch
            self.sourcePath = path
        }
        func recordParam(_ name: String, _ value: ParamStored) { recorded[name] = value }
    }

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive dragtest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
