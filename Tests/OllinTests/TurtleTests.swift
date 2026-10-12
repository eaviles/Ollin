import Testing
import Foundation
import Ollin

/// The turtle driven from code, pinned by what a walk must do: a square comes
/// home, the pen's runs break and close where the pen says, a remembered pose
/// comes back exactly, and the classic walks match the figures already in the
/// framework.
@Suite struct TurtleTests {

    static func near(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool {
        a.distance(to: b) <= tolerance
    }

    @Test func aSquareCloses() {
        var turtle = Turtle(at: Vector2(100, 100))
        for _ in 0 ..< 4 {
            turtle.forward(200)
            turtle.right(90)
        }
        #expect(Self.near(turtle.position, Vector2(100, 100)))
        #expect(Self.near(turtle.direction, Vector2(0, -1)))
        let runs = turtle.contours
        #expect(runs.count == 1)
        #expect(runs[0].points.count == 5)
        #expect(!runs[0].isClosed)
        // Facing up, the first step goes up the screen and the first right
        // turn goes toward the right.
        #expect(Self.near(runs[0].points[1], Vector2(100, -100)))
        #expect(Self.near(runs[0].points[2], Vector2(300, -100)))
        // The spirolateral walker in the framework is the same walk.
        var walker = Turtle(at: .zero, heading: 0)
        for _ in 0 ..< 4 {
            for step in 1 ... 7 {
                walker.forward(Double(step) * 26)
                walker.right(90)
            }
        }
        let figure = spirolateral(order: 7, step: 26)
        let walked = walker.contours[0].points
        #expect(walked.count == figure.points.count + 1)
        for (mine, theirs) in zip(walked, figure.points) {
            #expect(Self.near(mine, theirs, 1e-9))
        }
        #expect(Self.near(walked.last!, figure.points[0]))
    }

    @Test func thePenBreaksAndClosesTheRuns() {
        var turtle = Turtle(at: .zero, heading: 0)
        turtle.forward(100)
        turtle.penUp()
        turtle.forward(50)
        #expect(turtle.contours.count == 1)
        turtle.penDown()
        turtle.forward(100)
        let runs = turtle.contours
        #expect(runs.count == 2)
        #expect(runs[0].points == [Vector2(0, 0), Vector2(100, 0)])
        #expect(runs[1].points == [Vector2(150, 0), Vector2(250, 0)])
        // A run of one point is nothing.
        var still = Turtle(at: .zero)
        still.penUp()
        still.penDown()
        still.right(90)
        #expect(still.contours.isEmpty)
        // Closing a triangle drops the repeated start and makes it fillable.
        var tri = Turtle(at: Vector2(10, 10), heading: 0)
        for _ in 0 ..< 3 {
            tri.forward(100)
            tri.right(120)
        }
        tri.close()
        let outline = tri.contours
        #expect(outline.count == 1)
        #expect(outline[0].isClosed)
        #expect(outline[0].points.count == 3)
        let corners = outline[0].points
        var twiceArea = 0.0
        for i in corners.indices { twiceArea += corners[i].cross(corners[(i + 1) % corners.count]) }
        #expect(abs(abs(twiceArea) / 2 - 100 * 100 * 3.0.squareRoot() / 4) < 1e-6)
        // After a close, the next step starts a new run from where it stands.
        tri.forward(40)
        #expect(tri.contours.count == 2)
        #expect(tri.contours[1].points.count == 2)
    }

    @Test func aRememberedPoseComesBackExactly() {
        var turtle = Turtle(at: Vector2(500, 900))
        turtle.forward(200)
        turtle.pushState()
        turtle.left(30)
        turtle.forward(120)
        turtle.penUp()
        turtle.popState()
        #expect(Self.near(turtle.position, Vector2(500, 700)))
        #expect(abs(turtle.heading - -90) < 1e-12)
        #expect(turtle.isPenDown)
        turtle.right(30)
        turtle.forward(120)
        let runs = turtle.contours
        #expect(runs.count == 2)
        #expect(runs[0].points.count == 3)
        #expect(runs[1].points.count == 2)
        #expect(Self.near(runs[1].points[0], Vector2(500, 700)))
        // Nested pushes come back in order, and one too many changes nothing.
        turtle.pushState()
        turtle.forward(10)
        turtle.pushState()
        turtle.forward(10)
        turtle.popState()
        turtle.popState()
        let settled = turtle.position
        turtle.popState()
        #expect(turtle.position == settled)
    }

    @Test func backLeftHomeAndMoveToBehave() {
        var turtle = Turtle(at: Vector2(100, 100), heading: 0)
        turtle.forward(100)
        turtle.back(100)
        #expect(Self.near(turtle.position, Vector2(100, 100)))
        turtle.right(45)
        turtle.left(45)
        #expect(abs(turtle.heading) < 1e-12)
        turtle.heading = 90
        #expect(Self.near(turtle.direction, Vector2(0, 1)))
        turtle.forward(100)
        turtle.move(to: Vector2(300, 200))
        #expect(abs(turtle.heading - 90) < 1e-12)
        turtle.home()
        #expect(Self.near(turtle.position, Vector2(100, 100)))
        #expect(abs(turtle.heading) < 1e-12)
        let run = turtle.contours[0]
        #expect(run.points.count == 6)
        #expect(Self.near(run.points.last!, Vector2(100, 100)))
        #expect(Self.near(run.points[4], Vector2(300, 200)))
    }
}
