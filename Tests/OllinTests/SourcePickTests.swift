@testable import Ollin
import Testing
import simd

/// Finding the shape under a pointer, and the line of the file that drew it.
///
/// Each sketch below records its own `#line` beside the call it makes, so the
/// checks stay right when this file is edited above them.
@Suite
@MainActor
struct SourcePickTests {

    /// Two shapes, the second drawn over the first.
    private final class TwoShapes: Sketch {
        var circleLine = 0
        var rectLine = 0
        override func draw() {
            fill(.black)
            drawCircle(200, 200, 60); circleLine = #line
            drawRect(150, 150, 200, 200); rectLine = #line
        }
    }

    /// One circle drawn inside a moved and scaled frame.
    private final class UnderATransform: Sketch {
        var line = 0
        override func draw() {
            fill(.black)
            withState {
                translate(400, 100)
                scale(2)
                drawCircle(0, 0, 30); line = #line
            }
        }
    }

    private func run<S: Sketch>(_ sketch: S, tracking: Bool = true) -> S {
        sketch.setCanvasSize(width: 800, height: 800)
        sketch.tracksSourceSites = tracking
        sketch.setup()
        sketch.advance(time: 0, deltaTime: 1 / 60, frameRate: 60)
        sketch.performDraw()
        return sketch
    }

    @Test func aClickFindsTheLineThatDrewTheShape() {
        let sketch = run(TwoShapes())
        // Left of the rectangle's edge, so only the circle is there.
        let pick = sketch.sourcePick(at: Vector2(145, 200))
        #expect(pick?.site.line == sketch.circleLine)
        #expect(pick?.site.move == .xy)
        #expect(pick?.site.fileName == "SourcePickTests.swift")
    }

    @Test func theTopmostShapeWins() {
        let sketch = run(TwoShapes())
        // Inside both; the rectangle was drawn second, so it is the one seen.
        #expect(sketch.sourcePick(at: Vector2(200, 200))?.site.line == sketch.rectLine)
    }

    @Test func emptyCanvasPicksNothing() {
        let sketch = run(TwoShapes())
        #expect(sketch.sourcePick(at: Vector2(700, 700)) == nil)
    }

    /// A circle is picked by its own round edge, not by the box around it: a
    /// click just outside the curve but inside the corner of its box misses.
    @Test func aCircleIsPickedByItsEdge() {
        let sketch = run(TwoShapes())
        #expect(sketch.sourcePick(at: Vector2(146, 146)) == nil)
        #expect(sketch.sourcePick(at: Vector2(200, 145)) != nil)
    }

    @Test func nothingIsRecordedWhileNobodyIsEditing() {
        let sketch = run(TwoShapes(), tracking: false)
        #expect(sketch.sourcePick(at: Vector2(200, 200)) == nil)
    }

    /// The pick is in canvas points, so a shape drawn inside `translate` is
    /// found where it appears, not where its numbers say.
    @Test func aMovedFrameIsPickedWhereItAppears() {
        let sketch = run(UnderATransform())
        #expect(sketch.sourcePick(at: Vector2(0, 0)) == nil)
        #expect(sketch.sourcePick(at: Vector2(400, 100))?.site.line == sketch.line)
        // Radius 30 at scale 2 covers 60 points on the canvas.
        #expect(sketch.sourcePick(at: Vector2(455, 100)) != nil)
        #expect(sketch.sourcePick(at: Vector2(465, 100)) == nil)
    }

    /// The numbers in the file are in the frame the call drew in, so a drag of
    /// 100 canvas points on a shape drawn at twice the scale is 50 in the file.
    @Test func aDragIsMeasuredInTheNumbersOwnFrame() throws {
        let sketch = run(UnderATransform())
        let pick = try #require(sketch.sourcePick(at: Vector2(400, 100)))
        let delta = pick.numbersDelta(forCanvasDelta: Vector2(100, -40))
        #expect(abs(delta.x - 50) < 1e-6)
        #expect(abs(delta.y + 20) < 1e-6)
    }

    @Test func theOutlineIsTheShapeOnTheCanvas() throws {
        let sketch = run(UnderATransform())
        let pick = try #require(sketch.sourcePick(at: Vector2(400, 100)))
        let xs = pick.outline.map(\.x), ys = pick.outline.map(\.y)
        #expect(abs(xs.min()! - 340) < 1e-4)
        #expect(abs(xs.max()! - 460) < 1e-4)
        #expect(abs(ys.min()! - 40) < 1e-4)
        #expect(abs(ys.max()! - 160) < 1e-4)
    }

    /// A labeled call says so, so the host knows to look inside a `Vector2`
    /// rather than at two bare numbers.
    @Test func aLabeledCallReportsItsPointArgument() {
        final class Labeled: Sketch {
            override func draw() {
                fill(.black)
                drawCircle(center: Vector2(100, 100), radius: 40)
            }
        }
        let sketch = run(Labeled())
        #expect(sketch.sourcePick(at: Vector2(100, 100))?.site.move == .point)
    }

    /// A line is a thin thing to hit, so its region is a few points wider than
    /// the ink either side of it.
    @Test func aThinLineIsStillHittable() {
        final class OneLine: Sketch {
            override func draw() {
                stroke(.black)
                strokeWeight(1)
                drawLine(100, 100, 300, 100)
            }
        }
        let sketch = run(OneLine())
        #expect(sketch.sourcePick(at: Vector2(200, 102))?.site.move == .scalars([0, 1, 2, 3]))
        #expect(sketch.sourcePick(at: Vector2(200, 130)) == nil)
    }
}
