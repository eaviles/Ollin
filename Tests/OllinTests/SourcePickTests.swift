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
        #expect(pick?.site.move == .xy(radius: 2))
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
        #expect(sketch.sourcePick(at: Vector2(100, 100))?.site.move == .point(radius: 1))
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

    // MARK: What can be taken hold of

    /// A corner handle stands outside the circle it belongs to, so on the way
    /// from the edge to the corner the pointer is over nothing. The pick keeps
    /// its hover across that gap, and drops it once the pointer is clear of
    /// the handles.
    @Test func theHoverSurvivesTheGapBetweenTheEdgeAndACorner() throws {
        let sketch = run(TwoShapes())
        let pick = try #require(sketch.sourcePick(at: Vector2(145, 200)))
        // Outside the circle (73 from its center, radius 60), inside its box.
        #expect(sketch.sourcePick(at: Vector2(148, 148)) == nil)
        #expect(pick.keepsHover(at: Vector2(148, 148), slack: 11))
        // Just past a corner, within the slack a handle is grabbed by.
        #expect(pick.keepsHover(at: Vector2(268, 268), slack: 11))
        // Clear of every handle.
        #expect(pick.keepsHover(at: Vector2(300, 300), slack: 11) == false)
    }

    /// A circle is placed by its middle and sized by one number, so every
    /// corner can scale it, and nothing on the line says which way it faces.
    @Test func aCircleOffersFourCornersAndNoTurnParameter() throws {
        let sketch = run(TwoShapes())
        let pick = try #require(sketch.sourcePick(at: Vector2(145, 200)))
        #expect(pick.handles.filter { $0.kind == .resize }.count == 4)
        #expect(pick.handles.contains { $0.kind == .turn } == false)
        // The corners are the outline's own corners, on the canvas.
        let corners = Set(pick.handles.map { Vector2(round($0.position.x), round($0.position.y)) })
        #expect(corners == Set([Vector2(140, 140), Vector2(260, 140),
                                Vector2(260, 260), Vector2(140, 260)]))
    }

    /// A rectangle placed by its top-left corner holds that corner still, so
    /// the handle standing on it has nothing to scale and is not offered.
    @Test func aCornerPlacedRectangleOffersThreeCorners() throws {
        let sketch = run(TwoShapes())
        let pick = try #require(sketch.sourcePick(at: Vector2(200, 200)))
        #expect(pick.site.line == sketch.rectLine)
        #expect(pick.handles.count == 3)
        #expect(pick.handles.contains { $0.position == Vector2(150, 150) } == false)
        #expect(pick.placedAt == Vector2(150, 150))
    }

    /// A line is sized by where its ends are, so it has no corner; it does have
    /// a middle to swing about, so it has the parameter.
    @Test func aLineOffersATurnParameterAndNoCorners() throws {
        final class OneLine: Sketch {
            var line = 0
            override func draw() {
                stroke(.black)
                strokeWeight(4)
                drawLine(100, 100, 300, 100); line = #line
            }
        }
        let sketch = run(OneLine())
        let pick = try #require(sketch.sourcePick(at: Vector2(200, 100)))
        #expect(pick.handles.count == 1)
        #expect(pick.handles.first?.kind == .turn)
        // It stands clear above the shape rather than on it.
        #expect(pick.handles.first!.position.y < pick.outline.map(\.y).min()!)
        #expect(pick.placedAt == nil)
    }

    /// An arc carries its own two angles, so it has both: corners for its radii
    /// and a parameter for where it points.
    @Test func anArcOffersCornersAndAParameter() throws {
        final class OneArc: Sketch {
            override func draw() {
                noFill()
                stroke(.black)
                strokeWeight(6)
                drawArc(300, 300, 100, 100, start: 0.6, stop: 2.5)
            }
        }
        let sketch = run(OneArc())
        let pick = try #require(sketch.sourcePick(at: Vector2(300, 300)))
        #expect(pick.site.move.angles == [4, 5])
        #expect(pick.handles.filter { $0.kind == .resize }.count == 4)
        #expect(pick.handles.contains { $0.kind == .turn })
    }

    /// A resize is a ratio, so the same drag on the same picture gives the same
    /// answer whatever scale the numbers are written at.
    @Test func theSizeFactorIsTheSameAtAnyScale() throws {
        let plain = run(TwoShapes())
        let circle = try #require(plain.sourcePick(at: Vector2(145, 200)))
        let corner = try #require(circle.handle(at: Vector2(260, 260), within: 2))
        let one = try #require(circle.sizeFactor(for: corner, canvasDelta: Vector2(60, 60)))

        let scaled = run(UnderATransform())
        let small = try #require(scaled.sourcePick(at: Vector2(400, 100)))
        let far = try #require(small.handle(at: Vector2(460, 160), within: 2))
        let two = try #require(small.sizeFactor(for: far, canvasDelta: Vector2(60, 60)))

        #expect(abs(one.x - 2) < 1e-6)
        #expect(abs(one.x - two.x) < 1e-6)
    }

    /// One drag cannot take a shape below a twentieth of what it was, so a
    /// corner pulled through the middle leaves something to grab again.
    @Test func aResizeStopsBeforeTheShapeDisappears() throws {
        let sketch = run(TwoShapes())
        let pick = try #require(sketch.sourcePick(at: Vector2(145, 200)))
        let corner = try #require(pick.handle(at: Vector2(260, 260), within: 2))
        let factor = try #require(pick.sizeFactor(for: corner, canvasDelta: Vector2(-400, -400)))
        #expect(factor.x > 0)
        #expect(abs(factor.x - 0.05) < 1e-9)
    }

    /// The angle is measured in the frame the call drew in, so a shape inside a
    /// turned frame reads the turn the pointer made, not one shifted by the frame.
    @Test func aTurnIsMeasuredInTheCallsOwnFrame() throws {
        final class InsideATurnedFrame: Sketch {
            override func draw() {
                stroke(.black)
                strokeWeight(4)
                withState {
                    translate(300, 300)
                    rotate(.pi / 2)
                    drawLine(-50, 0, 50, 0)
                }
            }
        }
        let sketch = run(InsideATurnedFrame())
        let pick = try #require(sketch.sourcePick(at: Vector2(300, 300)))
        // A quarter turn of the pointer about the middle of the shape.
        let angle = pick.turnAngle(from: Vector2(300, 250), to: Vector2(350, 300))
        #expect(abs(angle - .pi / 2) < 1e-5)
    }
}
