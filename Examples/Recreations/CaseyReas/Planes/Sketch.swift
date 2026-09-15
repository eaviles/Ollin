//  Recreation after Casey Reas - the "Process" works (2004-2010), where a short
//  text names a kind of element, gives it behaviors, and the picture is what a
//  surface full of them does to each other. A homage, not a reproduction, and
//  not affiliated with or endorsed by the artist.
//  https://reas.com/process
//
//  An original Ollin interpretation. Nothing was ported, and the instruction
//  below is our own, written in the form Reas writes his in. The vocabulary
//  it is written with, an element being a form plus a list of behaviors, is
//  his.

import Ollin

/// **The instruction.**
///
/// > *Element 2.* A line that moves in a straight line, comes back in at the
/// > opposite edge after it leaves the surface, turns toward the direction of
/// > an element it is touching, and deviates a little from its own direction
/// > as it goes.
/// >
/// > *The process.* A rectangular surface filled with instances of Element 2.
/// > While two elements touch, draw the quadrilateral through their four
/// > endpoints. Raise its opacity while they go on touching and lower it
/// > after they part. Draw the elements over it.
///
/// The sibling sketch in this folder keeps every mark it ever made, so the
/// surface there is a record of the past. This one keeps nothing. Every
/// quadrilateral on it is a pair of elements touching now, or a pair that
/// parted recently enough to still be fading, so the picture is the present
/// tense of the same kind of instruction. Watching it is watching a thing
/// happen rather than reading what happened.
///
/// Two behaviors do most of the work, and they are written to disagree.
/// Turning toward what you touch gathers the lines into flocks that travel
/// together and hold a shape long enough for the planes between them to go
/// solid. Deviating breaks the flocks up again. Without the second one the
/// piece has nothing left to do once everything agrees, so it runs between
/// the two, tessellating and coming apart, and never arrives.
///
/// A quadrilateral through four points is underspecified, which is the sort
/// of gap a written instruction leaves and a reading has to fill. Four points
/// admit three quadrilaterals, and while they stand in convex position two of
/// those cross themselves. This reading takes the one that does not, by
/// walking the four points in the order they stand around their own center.
///
/// Try it: `elements` is how many lines are on the surface and `length` how
/// long each is. `speed` is how fast they cross, `reach` how near two of them
/// have to be to count as touching, `align` how hard a touch turns them
/// toward each other, and `drift` how much they wander on their own, which is
/// the pair to hold against each other. `rise` and `fall` are how many
/// seconds a plane takes to come up and to go away. `ink` is how dark a plane
/// gets at full opacity. `--export-svg` gives back the whole picture, since
/// nothing here is accumulated: one four-point polygon per pair that is
/// touching or fading, and the elements over them.
@main
final class Planes: Sketch {
    @Param(4 ... 260, icon: "line.diagonal") var elements = 160
    @Param(20 ... 400, icon: "ruler") var length = 130.0
    @Param(2 ... 160, icon: "speedometer") var speed = 34.0
    @Param(0 ... 90, icon: "arrow.left.and.right") var reach = 40.0
    @Param(0 ... 3, icon: "arrow.triangle.merge") var align = 0.7
    @Param(0 ... 3, icon: "wind") var drift = 1.0
    @Param(0.1 ... 6, icon: "arrow.up.right") var rise = 1.1
    @Param(0.1 ... 6, icon: "arrow.down.right") var fall = 2.2
    @Param(0.02 ... 0.6, icon: "drop") var ink = 0.09
    @Param(1 ... 999, icon: "dice") var seed = 7

    private var made = ""
    private var position: [Vector2] = []
    private var heading: [Double] = []
    private var endA: [Vector2] = []
    private var endB: [Vector2] = []
    /// How opaque the plane between a pair is, keyed by the pair. A pair that
    /// has faded all the way out is dropped, so the table holds only what is
    /// on the surface.
    private var opacity: [Int: Double] = [:]

    override func draw() {
        let recipe = "\(elements) \(length) \(seed)"
        if recipe != made {
            made = recipe
            place()
        }
        let dt = min(deltaTime, 1.0 / 30)
        move(by: dt)
        weigh(by: dt)

        background(Color(hex: 0xF7F6F3))
        drawPlanes()
        drawElements()
    }

    private func place() {
        randomSeed(seed)
        noiseSeed(seed)
        position = []
        heading = []
        opacity = [:]
        for _ in 0 ..< elements {
            position.append(Vector2(random(width), random(height)))
            heading.append(random(.tau))
        }
        refreshEnds()
    }

    /// The four behaviors, in the order the instruction names them. Every
    /// element moves and wraps first, and only then does anything look at
    /// what it is touching, so no element is turned by a neighbor that is
    /// half a step behind it.
    private func move(by dt: Double) {
        var returned: Set<Int> = []
        for i in position.indices {
            position[i] += Vector2(1, 0).rotated(by: heading[i]) * speed * dt
            let margin = length
            var here = position[i]
            if here.x < -margin { here = here.with(x: here.x + width + 2 * margin) }
            if here.x > width + margin { here = here.with(x: here.x - width - 2 * margin) }
            if here.y < -margin { here = here.with(y: here.y + height + 2 * margin) }
            if here.y > height + margin { here = here.with(y: here.y - height - 2 * margin) }
            if here != position[i] { returned.insert(i) }
            position[i] = here
        }
        refreshEnds()

        var turned = heading
        for i in position.indices {
            var agreement = 0.0
            var neighbors = 0
            for j in position.indices where j != i {
                guard touching(i, j) else { continue }
                // Toward the neighbor's direction by the short way around, so
                // a line never spins the long way to agree with one it is
                // already nearly parallel to.
                var difference = heading[j] - heading[i]
                while difference > .pi { difference -= .tau }
                while difference < -.pi { difference += .tau }
                agreement += difference
                neighbors += 1
            }
            // The behavior names one element, so what a crowd asks for is
            // the average of what each of them asks for. Adding them up
            // instead makes agreement grow with the size of the flock, and a
            // flock that has formed then holds tighter the more it gathers,
            // until every element on the surface is in one of three of them
            // and the rest of the surface is bare.
            if neighbors > 0 {
                turned[i] += (agreement / Double(neighbors)) * min(1, align * dt)
            }
            turned[i] += (noise(Double(i) * 17.3, time * 0.25) - 0.5) * drift * dt * .tau
        }
        heading = turned
        refreshEnds()

        // An element that came back in at the far edge is nowhere near what
        // it was touching a moment ago, so its planes go with it. Left to
        // fade on their own they stretch across the whole surface, which is
        // the picture disagreeing with the instruction: those two are not
        // touching and never were, at that distance.
        for i in returned {
            for j in position.indices where j != i {
                opacity[key(of: min(i, j), max(i, j))] = nil
            }
        }
    }

    /// The table's key for a pair, with `i` the smaller of the two.
    private func key(of i: Int, _ j: Int) -> Int { i * position.count + j }

    /// The two ends of every element, worked out once a frame. Touching is
    /// asked about every ordered pair twice over, so working them out where
    /// they are asked for costs tens of thousands of throwaway pairs a frame.
    private func refreshEnds() {
        endA = []
        endB = []
        endA.reserveCapacity(position.count)
        endB.reserveCapacity(position.count)
        for i in position.indices {
            let reachOut = Vector2(1, 0).rotated(by: heading[i]) * (length / 2)
            endA.append(position[i] - reachOut)
            endB.append(position[i] + reachOut)
        }
    }

    /// Raises the opacity of a plane while its pair touches and lowers it
    /// after, dropping the pair once nothing is left of it.
    private func weigh(by dt: Double) {
        for i in position.indices {
            for j in (i + 1) ..< position.count {
                let pair = key(of: i, j)
                let now = opacity[pair] ?? 0
                let next = touching(i, j) ? min(1, now + dt / rise) : now - dt / fall
                if next > 0 {
                    opacity[pair] = next
                } else {
                    opacity[pair] = nil
                }
            }
        }
    }

    private func drawPlanes() {
        noStroke()
        for (pair, weight) in opacity.sorted(by: { $0.key < $1.key }) {
            let i = pair / position.count
            let j = pair % position.count
            let corners = quadrilateral(through: [endA[i], endB[i], endA[j], endB[j]])
            fill(Color(white: 0.08, alpha: ink * weight))
            drawPolygon(corners)
        }
    }

    private func drawElements() {
        noFill()
        stroke(Color(white: 0.08, alpha: 0.85))
        strokeWeight(1.2)
        for i in position.indices {
            drawLine(endA[i], endB[i])
        }
    }

    /// Two elements touch when the nearest points of the two segments are
    /// within `reach` of each other, which covers crossing as the case where
    /// that distance is zero.
    private func touching(_ i: Int, _ j: Int) -> Bool {
        Self.distance(from: endA[i], endB[i], to: endA[j], endB[j]) <= reach
    }

    /// The one quadrilateral through four points that does not cross itself:
    /// the points in the order they stand around their own center.
    private func quadrilateral(through points: [Vector2]) -> [Vector2] {
        let middle = points.reduce(Vector2(0, 0), +) / Double(points.count)
        return points.sorted { ($0 - middle).angle < ($1 - middle).angle }
    }

    /// The distance between two line segments.
    private static func distance(from a0: Vector2, _ a1: Vector2,
                                 to b0: Vector2, _ b1: Vector2) -> Double {
        let a = a1 - a0
        let b = b1 - b0
        let cross = a.cross(b)
        if abs(cross) > 1e-9 {
            let start = b0 - a0
            let along = start.cross(b) / cross
            let across = start.cross(a) / cross
            if along >= 0, along <= 1, across >= 0, across <= 1 { return 0 }
        }
        return min(min(distance(from: a0, to: b0, b1), distance(from: a1, to: b0, b1)),
                   min(distance(from: b0, to: a0, a1), distance(from: b1, to: a0, a1)))
    }

    /// The distance from a point to a segment.
    private static func distance(from point: Vector2, to a: Vector2, _ b: Vector2) -> Double {
        let along = b - a
        let lengthSquared = along.lengthSquared
        guard lengthSquared > 0 else { return point.distance(to: a) }
        let t = max(0, min(1, (point - a).dot(along) / lengthSquared))
        return point.distance(to: a + along * t)
    }
}
