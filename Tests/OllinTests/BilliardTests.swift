@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on billiards. A bouncing path looks plausible whatever it
/// is doing, so every check here is a theorem about the room rather than a
/// look at the picture.
///
/// Two carry the suite, and neither is derived from the code. In a circle the
/// distance from the middle to every chord is the same number, which is the
/// conserved quantity of the whole system: `everyChordInACircleMissesTheSame`
/// measures it on the finished path. In an ellipse the product of the two
/// foci's distances to a chord is the same number, which is why an ellipse
/// draws two different pictures rather than one: `anEllipseKeepsTheProduct`
/// measures that. `aSquareClosesAfterFourBounces` is the third kind of check,
/// an arrangement whose answer can be written down before running anything.
@Suite
struct BilliardTests {

    private let middle = Vector2(500, 500)

    /// How far a line through two points passes from a third.
    private func distance(from point: Vector2, toLineThrough a: Vector2, _ b: Vector2) -> Double {
        let along = (b - a).normalized
        return abs((point - a).cross(along))
    }

    // MARK: - A circle

    /// The load-bearing law. A bounce turns the path about the radius, which
    /// leaves untouched how far the chord passes from the middle. So every
    /// chord of the path misses the middle by the same distance, and the whole
    /// rosette wraps one smaller circle it never enters.
    @Test func everyChordInACircleMissesTheSame() {
        let room = Billiard(.circle(Circle(center: middle, radius: 380)))
        for heading in [0.3, 1.1, 2.7, -0.9] {
            let path = room.path(from: middle + Vector2(0, -300), heading: heading, bounces: 120)
            guard path.count == 121 else { Issue.record("the path left the room"); continue }
            let first = distance(from: middle, toLineThrough: path[0], path[1])
            for i in 1 ..< path.count - 1 {
                #expect(abs(distance(from: middle, toLineThrough: path[i], path[i + 1]) - first) < 1e-6)
            }
            // And nothing ever crosses that inner circle.
            for point in path { #expect(point.distance(to: middle) >= first - 1e-6) }
        }
    }

    /// The same fact read a second way. Every chord of a circle at the same
    /// distance from the middle is the same length, so a path in a circle takes
    /// equal steps forever.
    @Test func everyChordInACircleIsTheSameLength() {
        let room = Billiard(.circle(Circle(center: middle, radius: 380)))
        // From the first bounce on: the opening run starts inside the room, so
        // it is a piece of a chord rather than a whole one.
        let path = room.path(from: middle + Vector2(300, 0), heading: 2.2, bounces: 60)
        guard path.count == 61 else { Issue.record("the path left the room"); return }
        let first = path[1].distance(to: path[2])
        #expect(first > 1)
        #expect(path[0].distance(to: path[1]) < first)
        for i in 2 ..< path.count - 1 {
            #expect(abs(path[i].distance(to: path[i + 1]) - first) < 1e-6)
        }
    }

    /// Each bounce moves the ball around the rim by the same angle, so a path
    /// whose turn is a whole fraction of a circle closes exactly. Sent off to
    /// advance two fifths of the way round, it draws a five-pointed star and
    /// comes home.
    @Test func aRationalTurnClosesTheStar() {
        let radius = 380.0
        let room = Billiard(.circle(Circle(center: middle, radius: radius)))
        let start = middle + Vector2(radius, 0)

        // The chord that advances by `advance` runs from the rim at angle 0 to
        // the rim at that angle, so its direction is the difference of the two.
        let advance = 2 * Double.pi * 2 / 5
        let inward = atan2(sin(advance), cos(advance) - 1)
        let path = room.path(from: start, heading: inward, bounces: 5)
        guard path.count == 6 else { Issue.record("the path left the room"); return }
        #expect(path[5].distance(to: start) < 1e-6)             // home again
        for i in 0 ..< 5 {
            let a = (path[i] - middle).angle, b = (path[i + 1] - middle).angle
            var turn = b - a
            while turn < 0 { turn += .tau }
            #expect(abs(turn - advance) < 1e-9)
        }
    }

    // MARK: - An ellipse

    /// Why an ellipse draws two pictures instead of one. The product of the
    /// distances from the two foci to a chord is the same for every chord of a
    /// path, so a path that passes between the foci keeps passing between them
    /// and one that misses keeps missing.
    @Test func anEllipseKeepsTheProduct() {
        let room = Billiard(.ellipse(center: middle, radii: Vector2(400, 250)))
        let foci = room.foci
        #expect(foci.count == 2)
        #expect(abs(foci[0].distance(to: foci[1]) - 2 * (400.0 * 400 - 250 * 250).squareRoot()) < 1e-9)

        for heading in [0.4, 1.9, -1.2] {
            let path = room.path(from: middle + Vector2(0, -200), heading: heading, bounces: 90)
            guard path.count == 91 else { Issue.record("the path left the room"); continue }
            func product(_ i: Int) -> Double {
                distance(from: foci[0], toLineThrough: path[i], path[i + 1])
                    * distance(from: foci[1], toLineThrough: path[i], path[i + 1])
            }
            let first = product(0)
            for i in 1 ..< path.count - 1 {
                #expect(abs(product(i) - first) < 1e-4)
            }
        }
    }

    /// The two pictures themselves. A path sent through the gap between the
    /// foci crosses between them every time; one sent outside never does.
    @Test func anEllipseSortsPathsIntoTwoKinds() {
        let room = Billiard(.ellipse(center: middle, radii: Vector2(400, 250)))
        let foci = room.foci
        let gap = (foci[1] - foci[0]).normalized

        func crossings(of path: [Vector2]) -> Int {
            var count = 0
            for i in 0 ..< path.count - 1 {
                let a = path[i] - middle, b = path[i + 1] - middle
                guard (a.y < 0) != (b.y < 0) else { continue }   // crosses the long axis
                let t = a.y / (a.y - b.y)
                let x = (a + (b - a) * t).dot(gap)
                if abs(x) < (foci[1] - middle).length { count += 1 }
            }
            return count
        }

        // Straight through the middle, so it goes between the foci.
        let through = room.path(from: middle + Vector2(0, -200), heading: .pi / 2 + 0.15, bounces: 40)
        #expect(crossings(of: through) > 15)

        // A shallow start from the end of the long axis, which stays outside.
        let around = room.path(from: middle + Vector2(-380, 0), heading: 0.25, bounces: 40)
        #expect(crossings(of: around) == 0)
    }

    // MARK: - Straight walls

    /// An arrangement whose answer can be written down. Let a ball go from the
    /// middle of one wall of a square at 45 degrees and it traces the diamond
    /// through the four wall middles, home after four bounces.
    @Test func aSquareClosesAfterFourBounces() {
        let square = Contour([Vector2(100, 100), Vector2(900, 100),
                              Vector2(900, 900), Vector2(100, 900)], closed: true)
        let room = Billiard(.polygon(square))
        let start = Vector2(500, 100)
        let path = room.path(from: start, heading: .pi / 4, bounces: 4)
        guard path.count == 5 else { Issue.record("the path left the room"); return }
        #expect(path[1].distance(to: Vector2(900, 500)) < 1e-6)
        #expect(path[2].distance(to: Vector2(500, 900)) < 1e-6)
        #expect(path[3].distance(to: Vector2(100, 500)) < 1e-6)
        #expect(path[4].distance(to: start) < 1e-6)
    }

    /// The rule itself, measured at every wall of every room: the ball leaves
    /// at the angle it arrived at, about the wall it met.
    @Test func everyBounceLeavesAtTheAngleItArrived() {
        let rooms: [Billiard] = [
            Billiard(.circle(Circle(center: middle, radius: 380))),
            Billiard(.ellipse(center: middle, radii: Vector2(400, 250))),
            Billiard(.polygon(Contour([Vector2(120, 140), Vector2(880, 100),
                                       Vector2(820, 860), Vector2(160, 900)], closed: true))),
            Billiard(.stadium(center: middle, straight: 380, radius: 240)),
            Billiard(.polygon(Contour([Vector2(100, 100), Vector2(900, 100),
                                       Vector2(900, 900), Vector2(100, 900)], closed: true)),
                     obstacles: [Circle(center: middle, radius: 160)]),
        ]
        for room in rooms {
            let path = room.path(from: Vector2(430, 300), heading: 0.7, bounces: 50)
            guard path.count > 20 else { Issue.record("the path left the room"); continue }
            for i in 1 ..< path.count - 1 {
                let incoming = (path[i] - path[i - 1]).normalized
                let outgoing = (path[i + 1] - path[i]).normalized
                guard let normal = normalAt(path[i], of: room) else { continue }
                // The part along the wall is kept, the part into it is turned.
                let along = Vector2(-normal.y, normal.x)
                #expect(abs(incoming.dot(along) - outgoing.dot(along)) < 1e-5)
                #expect(abs(incoming.dot(normal) + outgoing.dot(normal)) < 1e-5)
            }
        }
    }

    /// The wall's own direction at a point, worked out from the room rather
    /// than from the path, so the reflection check has an outside opinion.
    private func normalAt(_ point: Vector2, of room: Billiard) -> Vector2? {
        for obstacle in room.obstacles where abs(point.distance(to: obstacle.center) - obstacle.radius) < 1e-6 {
            return (point - obstacle.center).normalized
        }
        switch room.table {
        case let .circle(circle):
            return (point - circle.center).normalized
        case let .ellipse(center, radii):
            let d = point - center
            return Vector2(d.x / (radii.x * radii.x), d.y / (radii.y * radii.y)).normalized
        case let .polygon(outline):
            let points = outline.points
            for i in 0 ..< points.count {
                let a = points[i], b = points[(i + 1) % points.count]
                let edge = (b - a).normalized
                guard abs((point - a).cross(edge)) < 1e-6 else { continue }
                return Vector2(-edge.y, edge.x).normalized
            }
            return nil
        case let .stadium(center, straight, radius):
            let half = straight / 2
            if abs(point.x - center.x) <= half + 1e-9 { return Vector2(0, point.y > center.y ? 1 : -1) }
            let capCenter = Vector2(center.x + (point.x > center.x ? half : -half), center.y)
            _ = radius
            return (point - capCenter).normalized
        }
    }

    // MARK: - Orderly and disorderly rooms

    /// The point of the stadium. In a circle two balls let go a hair apart stay
    /// a hair apart forever, because each keeps its own chord distance. Pull the
    /// circle in half and slide the halves apart, and the same pair of balls
    /// ends up nowhere near each other.
    @Test func aStadiumSeparatesWhatACircleKeepsTogether() {
        let nudge = 1e-6
        let start = Vector2(500, 320)

        let circle = Billiard(.circle(Circle(center: middle, radius: 380)))
        let circleA = circle.path(from: start, heading: 0.7, bounces: 60)
        let circleB = circle.path(from: start, heading: 0.7 + nudge, bounces: 60)
        guard circleA.count == 61, circleB.count == 61 else {
            Issue.record("a path in a circle must never end early"); return
        }
        let circleApart = circleA[circleA.count - 1].distance(to: circleB[circleB.count - 1])

        let stadium = Billiard(.stadium(center: middle, straight: 380, radius: 240))
        let stadiumA = stadium.path(from: start, heading: 0.7, bounces: 60)
        let stadiumB = stadium.path(from: start, heading: 0.7 + nudge, bounces: 60)
        guard stadiumA.count == 61, stadiumB.count == 61 else {
            Issue.record("a path in a stadium must never end early"); return
        }
        let stadiumApart = stadiumA[stadiumA.count - 1].distance(to: stadiumB[stadiumB.count - 1])

        #expect(circleApart < 0.05)                 // still together
        #expect(stadiumApart > 20)                  // long gone
        #expect(stadiumApart > circleApart * 1000)
    }

    /// Something standing in the room is a wall like any other. Aimed straight
    /// at the middle of a round one, the ball comes straight back the way it
    /// came, since the wall it meets is square to it.
    @Test func aBallAimedAtAPostComesStraightBack() {
        let square = Contour([Vector2(100, 100), Vector2(900, 100),
                              Vector2(900, 900), Vector2(100, 900)], closed: true)
        let post = Circle(center: middle, radius: 120)
        let room = Billiard(.polygon(square), obstacles: [post])

        let start = Vector2(200, 500)
        let path = room.path(from: start, heading: 0, bounces: 3)
        guard path.count == 4 else { Issue.record("the path left the room"); return }
        #expect(path[1].distance(to: Vector2(380, 500)) < 1e-6)   // the near face of the post
        #expect(path[2].distance(to: Vector2(100, 500)) < 1e-6)   // straight back to the wall
        #expect(path[3].distance(to: Vector2(380, 500)) < 1e-6)   // and back again, forever

        // With nothing standing there it crosses the room instead.
        let empty = Billiard(.polygon(square))
        #expect(empty.path(from: start, heading: 0, bounces: 1)[1].distance(to: Vector2(900, 500)) < 1e-6)
    }

    /// A post in the middle is the other classic way to turn an orderly room
    /// disorderly. A square keeps two nearly identical balls together for a
    /// long time; put one round thing in the middle and it does not.
    @Test func aPostInTheMiddleSeparatesWhatASquareKeepsTogether() {
        let square = Contour([Vector2(100, 100), Vector2(900, 100),
                              Vector2(900, 900), Vector2(100, 900)], closed: true)
        let start = Vector2(300, 260)
        let nudge = 1e-6

        let plain = Billiard(.polygon(square))
        let plainApart = plain.path(from: start, heading: 0.7, bounces: 40).last!
            .distance(to: plain.path(from: start, heading: 0.7 + nudge, bounces: 40).last!)

        let sinai = Billiard(.polygon(square), obstacles: [Circle(center: middle, radius: 150)])
        let sinaiApart = sinai.path(from: start, heading: 0.7, bounces: 40).last!
            .distance(to: sinai.path(from: start, heading: 0.7 + nudge, bounces: 40).last!)

        #expect(plainApart < 0.1)
        #expect(sinaiApart > 10)
        #expect(sinaiApart > plainApart * 1000)
    }

    /// A path stays in the room it was let go in, whatever the room is, and
    /// every point it turns at is on a wall rather than in the air.
    @Test func aPathStaysInTheRoom() {
        let rooms: [Billiard] = [
            Billiard(.circle(Circle(center: middle, radius: 380))),
            Billiard(.ellipse(center: middle, radii: Vector2(400, 250))),
            Billiard(.stadium(center: middle, straight: 380, radius: 240)),
            Billiard(.polygon(Contour([Vector2(100, 100), Vector2(900, 100),
                                       Vector2(900, 900), Vector2(100, 900)], closed: true)),
                     obstacles: [Circle(center: middle, radius: 160)]),
        ]
        for room in rooms {
            let path = room.path(from: Vector2(430, 300), heading: 1.3, bounces: 80)
            for i in 1 ..< path.count {
                // On a wall: just inside the room by every measure but its own.
                #expect(!room.contains(path[i] + (path[i] - path[i - 1]).normalized * 1e-3))
            }
            // And nothing is ever inside an obstacle.
            for point in path {
                for obstacle in room.obstacles {
                    #expect(point.distance(to: obstacle.center) >= obstacle.radius - 1e-6)
                }
            }
        }
    }

    /// A ball let go outside the room, or with nowhere to go, answers with the
    /// start alone rather than a wrong path.
    @Test func anImpossibleStartAnswersWithNothing() {
        let room = Billiard(.circle(Circle(center: middle, radius: 380)))
        #expect(room.path(from: middle, heading: 0.5, bounces: 0) == [middle])
        #expect(room.path(from: middle, direction: .zero, bounces: 10) == [middle])

        // Outside the circle and aimed away: no wall to meet.
        let away = room.path(from: middle + Vector2(0, -900), heading: -.pi / 2, bounces: 10)
        #expect(away.count == 1)

        // A room with no shape has no walls either.
        let flat = Billiard(.polygon(Contour([Vector2(0, 0), Vector2(10, 0)], closed: true)))
        #expect(flat.path(from: Vector2(5, 1), heading: 0.3, bounces: 5).count == 1)
    }
}
