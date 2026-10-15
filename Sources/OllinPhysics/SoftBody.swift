import Foundation
import Ollin

/// A squishy body made from any outline: a ring of particles round the edge of
/// a `Shape` that keeps its area, bends, bounces, and collides outline against
/// outline. Make one with `World.addSoftBody(from:)` and draw it from `shape`.
///
/// ```swift
/// let disc = Circle(center: Vector2(540, 300), radius: 120)
/// let blob = try world.addSoftBody(from: Shape(contours: [disc.contour]))
/// // each frame:
/// world.advance(by: deltaTime)
/// drawShape(blob.shape)
/// ```
///
/// Its particles are ordinary `Particle`s in the world, so gravity, `drag`,
/// `bounds`, `substeps`, and a sketch's own `push(_:)` or `applyForce(_:)` reach
/// them as they reach any other. What makes them a body is held here: each
/// particle stays near its neighbors (`stiffness`), each corner keeps its turn
/// (`bend`), each ring of the outline keeps its area (`pressure`), and the
/// whole outline may be pulled back toward its own shape (`shapeMemory`). Every
/// one of those is a compliant constraint (XPBD, Macklin, Müller and
/// Chentanez 2016), so a setting means the same body at any frame rate and any
/// `iterations`.
public final class SoftBody {

    /// Every particle on the outline, one ring after another in the order each
    /// goes round. They live in the world's `particles` too.
    public let particles: [Particle]

    /// The whole body's mass, split evenly between its particles.
    public let mass: Double

    /// How hard the outline resists being stretched, `0` slack … `1`
    /// inextensible. At `0.5` the outline gives about a tenth of its length
    /// when it holds its own weight.
    public var stiffness: Double {
        didSet { if !world.holds(stiffness, "softBody.stiffness") { stiffness = oldValue } }
    }

    /// How hard each corner resists being folded, `0` limp like a loop of
    /// string … `1` holding every corner's angle. A long straight side can
    /// still bow; `shapeMemory` is what holds it.
    public var bend: Double {
        didSet { if !world.holds(bend, "softBody.bend") { bend = oldValue } }
    }

    /// How firmly the body holds its area, in gravities: where nothing else
    /// holds the shape, its own weight presses out about `1 / pressure` of the
    /// area, so `50` holds it within two percent and `5` gives up about a
    /// seventh. `.infinity` (the default) keeps the area whatever presses on
    /// it, and `0` lets it go, which leaves a slack outline that crumples like
    /// a loose loop.
    public var pressure: Double {
        didSet {
            if !world.holds(pressure, "softBody.pressure", orUnbounded: true) { pressure = oldValue }
        }
    }

    /// How strongly the body is pulled back toward its own shape, turned and
    /// moved to where it is now: `0` not at all … `1` rigid. Dropped from its
    /// own height, a disc squashes by a third of its height at `0`, a tenth at
    /// `0.3`, and under four percent at `0.9`. This is what keeps a letter's
    /// counter in its place, and what brings a squashed star back to a star
    /// rather than a rounder thing of the same area.
    public var shapeMemory: Double {
        didSet { if !world.holds(shapeMemory, "softBody.shapeMemory") { shapeMemory = oldValue } }
    }

    /// The area the body holds, in square points: what it was made with,
    /// until it is set. Set it larger to inflate the body and smaller to let
    /// air out; each ring of the outline takes its share.
    public var restArea: Double {
        didSet {
            guard world.holds(restArea, "softBody.restArea") else { restArea = oldValue; return }
            restArea = Swift.max(0, restArea)
        }
    }

    /// Free-form tag so a sketch can hang its own data off a body (its color, a
    /// name) without a parallel array.
    public var userData: Any?

    /// The world the body lives in. Unowned: the world holds its bodies.
    unowned let world: World

    /// Where each ring's particles sit in `particles`.
    let rings: [Range<Int>]

    /// Each island's rings: its outer ring first, then its holes. The outer
    /// ring is wound so its signed area is positive and each hole so its own
    /// is negative, so an island's area is the plain sum.
    let islands: [[Int]]

    /// Each ring's signed area as made: positive for an outer ring, negative
    /// for a hole. Each ring holds its own, which holds every island's and
    /// keeps a counter open where a hole free to shrink would let it
    /// collapse while its outer ring shrank to match.
    let ringAreas: [Double]

    /// The area the body was made with, which `restArea` is read against.
    let builtArea: Double

    /// The particle after and before each one round its ring.
    let next: [Int]
    let previous: [Int]

    /// The rest length of the edge from each particle to the next.
    let restLengths: [Double]

    /// The links that hold each corner's turn: from a particle to the one two
    /// and three along its ring, with their rest lengths.
    let bendLinks: [(a: Int, b: Int, length: Double)]

    /// The outline round its centroid, as made: the shape `shapeMemory` pulls
    /// toward.
    let restOffsets: [Vector2]

    /// The length the compliances are measured against: the diameter of a
    /// disc of the body's area.
    let size: Double

    /// The pull the compliances are measured against: the world's gravity
    /// when the body was made, or the default's when the world had none.
    let pull: Double

    // MARK: The step's multipliers

    /// The constraints' running multipliers (XPBD's lambda), cleared at the
    /// start of every step.
    private var stretchLambdas: [Double]
    private var bendLambdas: [Double]
    private var areaLambdas: [Double]
    private var shapeLambdas: [Double]

    /// The step's compliances, divided by the step squared, as `begin` read
    /// the dials. A negative value switches the constraint off.
    private var stretchScale = 0.0
    private var bendScale = -1.0
    private var areaScales: [Double] = []
    private var shapeScale = -1.0

    /// The box round each island's particles, refreshed before each pass of
    /// contacts.
    var boxes: [Box] = []

    init(world: World, rings ringPoints: [[Vector2]], islands: [[Int]], mass: Double,
         stiffness: Double, bend: Double, pressure: Double, shapeMemory: Double,
         pull: Double) {
        self.world = world
        self.pull = pull
        self.mass = mass
        self.stiffness = stiffness
        self.bend = bend
        self.pressure = pressure
        self.shapeMemory = shapeMemory
        self.islands = islands

        let count = ringPoints.reduce(0) { $0 + $1.count }
        let particleMass = mass / Double(count)
        var particles: [Particle] = []
        var rings: [Range<Int>] = []
        var next: [Int] = []
        var previous: [Int] = []
        for points in ringPoints {
            let start = particles.count
            for (k, point) in points.enumerated() {
                particles.append(Particle(position: point, mass: particleMass))
                next.append(start + (k + 1) % points.count)
                previous.append(start + (k + points.count - 1) % points.count)
            }
            rings.append(start ..< particles.count)
        }
        self.particles = particles
        self.rings = rings
        self.next = next
        self.previous = previous

        let rest = particles.map(\.position)
        restLengths = rest.indices.map { (rest[next[$0]] - rest[$0]).length }
        // Two and three along the ring: two neighboring triangles of links
        // fix a corner's turn and keep it from folding through to its
        // mirror image. A ring too short for a step has no link for it.
        var links: [(a: Int, b: Int, length: Double)] = []
        for ring in rings {
            for step in [2, 3] where ring.count > 2 * step {
                for i in ring {
                    let j = ring.lowerBound + (i - ring.lowerBound + step) % ring.count
                    links.append((i, j, (rest[j] - rest[i]).length))
                }
            }
        }
        bendLinks = links
        let centroid = rest.reduce(.zero, +) / Double(count)
        restOffsets = rest.map { $0 - centroid }

        ringAreas = ringPoints.map { SoftBody.signedArea(of: $0) }
        let total = ringAreas.reduce(0, +)
        builtArea = total
        restArea = total
        size = 2 * (Swift.max(total, 0) / .pi).squareRoot()

        stretchLambdas = [Double](repeating: 0, count: count)
        bendLambdas = [Double](repeating: 0, count: links.count)
        areaLambdas = [Double](repeating: 0, count: rings.count)
        shapeLambdas = [Double](repeating: 0, count: count)

        for particle in particles { particle.softBody = self }
    }

    // MARK: Reading the body

    /// The body's outline as it is now: one closed contour a ring, holes
    /// included, ready for `drawShape`. Its edges are straight between
    /// particles; `Shape(curveThrough:closed:)` over a ring's points draws it
    /// smooth instead, at the cost of rounding its corners.
    public var shape: Shape {
        Shape(contours: rings.map { ring in Contour(ring.map { particles[$0].position }) })
    }

    /// The area the outline encloses now, holes taken out, in square points.
    public var area: Double {
        rings.indices.reduce(0) { $0 + ringArea($1) }
    }

    /// The average of the particles' positions: where the body is.
    public var center: Vector2 {
        particles.reduce(.zero) { $0 + $1.position } / Double(particles.count)
    }

    /// The average of the particles' velocities, as a per-step displacement
    /// like `Particle.velocity`.
    public var velocity: Vector2 {
        particles.reduce(.zero) { $0 + $1.velocity } / Double(particles.count)
    }

    /// Whether `point` is inside the outline as it is now (a point in a hole
    /// is not).
    public func contains(_ point: Vector2) -> Bool {
        var inside = false
        for ring in rings {
            var j = ring.upperBound - 1
            for i in ring {
                let a = particles[i].position, b = particles[j].position
                if (a.y > point.y) != (b.y > point.y),
                   point.x < a.x + (b.x - a.x) * (point.y - a.y) / (b.y - a.y) {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }

    // MARK: Moving the body

    /// Add to every particle's velocity at once, a per-step displacement as
    /// `Particle.push(_:)` takes: a throw, or a kick.
    public func push(_ amount: Vector2) {
        guard world.holds(amount, "softBody.push") else { return }
        for particle in particles { particle.push(amount) }
    }

    /// Accumulate a force on the whole body for the next step, shared evenly
    /// between its particles, so the body as a whole accelerates by
    /// `force / mass`.
    public func applyForce(_ force: Vector2) {
        guard world.holds(force, "softBody.applyForce") else { return }
        let share = force / Double(particles.count)
        for particle in particles { particle.applyForce(share) }
    }

    /// Move the whole body by `offset`, keeping the motion it has: a jump
    /// rather than a throw.
    public func move(by offset: Vector2) {
        guard world.holds(offset, "softBody.move(by:)") else { return }
        for particle in particles {
            particle.position += offset
            particle.previous += offset
        }
    }

    // MARK: The constraints

    /// Read the dials into this step's compliances and clear the multipliers.
    /// `h` is the step.
    func begin(step h: Double) {
        for i in stretchLambdas.indices {
            stretchLambdas[i] = 0
            shapeLambdas[i] = 0
        }
        for i in bendLambdas.indices { bendLambdas[i] = 0 }
        for k in areaLambdas.indices { areaLambdas[k] = 0 }

        let weight = mass * pull
        let perStep = 1 / (h * h)
        // A compliance is the give per unit of load; each is measured against
        // the body's own weight so that a setting reads the same on a pebble
        // and a boulder (see `softness(for:)`).
        stretchScale = SoftBody.softness(for: stiffness) / weight * perStep
        bendScale = bend > 0 ? SoftBody.softness(for: bend) / weight * perStep : -1
        // Shape memory is read against a drop rather than a load: the pull
        // that holds a body's shape through landing from its own height is
        // about a hundred times the one that holds it up at rest, and the dial
        // is laid out over the range a sketch wants (see `shapeMemory`).
        shapeScale = shapeMemory > 0
            ? SoftBody.softness(for: shapeMemory) / 100 * size * Double(particles.count) / weight
                * perStep
            : -1
        let inflation = builtArea > 0 ? restArea / builtArea : 1
        areaScales = rings.indices.map { r in
            guard pressure > 0 else { return -1 }
            guard pressure.isFinite else { return 0 }
            // The pressure that holds the ring's share of the weight up across
            // its width, and the give at which that much presses out one
            // `pressure`-th of its area.
            let rest = Swift.max(abs(ringAreas[r]) * inflation, 1e-9)
            let width = 2 * (rest / .pi).squareRoot()
            let share = Double(rings[r].count) / Double(particles.count)
            let held = mass * share * pull / Swift.max(width, 1e-9)
            return rest / (pressure * Swift.max(held, 1e-12)) * perStep
        }
    }

    /// One pass over every constraint the body holds itself to.
    func solve() {
        solveStretch()
        if bendScale >= 0 { solveBend() }
        let inflation = builtArea > 0 ? restArea / builtArea : 1
        for r in rings.indices where areaScales[r] >= 0 {
            solveArea(ring: r, rest: ringAreas[r] * inflation)
        }
        if shapeScale >= 0 { solveShape() }
    }

    /// The inverse mass a constraint reads: none for a pinned particle.
    @inline(__always)
    private func weight(_ i: Int) -> Double {
        let p = particles[i]
        return p.isPinned ? 0 : p.inverseMass
    }

    /// Each edge back toward its rest length, with a give proportional to that
    /// length, so the outline as a whole gives the same however finely it was
    /// cut.
    func solveStretch() {
        for i in particles.indices {
            let j = next[i]
            let wi = weight(i), wj = weight(j)
            let delta = particles[j].position - particles[i].position
            let distance = delta.length
            guard distance > 1e-12 else { continue }
            let alpha = stretchScale * restLengths[i]
            let denominator = wi + wj + alpha
            guard denominator > 1e-18 else { continue }
            let c = distance - restLengths[i]
            let dLambda = (-c - alpha * stretchLambdas[i]) / denominator
            stretchLambdas[i] += dLambda
            let gradient = delta / distance
            particles[i].position -= gradient * (dLambda * wi)
            particles[j].position += gradient * (dLambda * wj)
        }
    }

    /// Each bend link back toward its rest length, with a give proportional
    /// to that length, as an edge's.
    func solveBend() {
        for (k, link) in bendLinks.enumerated() {
            let wa = weight(link.a), wb = weight(link.b)
            let delta = particles[link.b].position - particles[link.a].position
            let distance = delta.length
            guard distance > 1e-12 else { continue }
            let alpha = bendScale * link.length
            let denominator = wa + wb + alpha
            guard denominator > 1e-18 else { continue }
            let c = distance - link.length
            let dLambda = (-c - alpha * bendLambdas[k]) / denominator
            bendLambdas[k] += dLambda
            let gradient = delta / distance
            particles[link.a].position -= gradient * (dLambda * wa)
            particles[link.b].position += gradient * (dLambda * wb)
        }
    }

    /// Ring `r`'s signed area back toward `rest`: every particle on it moves
    /// along the ring's normal, weighted by how much moving it changes the
    /// area.
    func solveArea(ring r: Int, rest: Double) {
        let c = ringArea(r) - rest
        var denominator = areaScales[r]
        for i in rings[r] {
            denominator += weight(i) * areaGradient(i).lengthSquared
        }
        guard denominator > 1e-18 else { return }
        let dLambda = (-c - areaScales[r] * areaLambdas[r]) / denominator
        areaLambdas[r] += dLambda
        // Every gradient is read before anything moves, so each particle moves
        // by the gradient the multiplier was computed from.
        let moves = rings[r].map { areaGradient($0) * (dLambda * weight($0)) }
        for (i, move) in zip(rings[r], moves) { particles[i].position += move }
    }

    /// How the enclosed area changes as particle `i` moves: half the chord
    /// between its two neighbors, turned a quarter.
    @inline(__always)
    private func areaGradient(_ i: Int) -> Vector2 {
        let chord = particles[next[i]].position - particles[previous[i]].position
        return Vector2(chord.y, -chord.x) * 0.5
    }

    /// Each particle toward where the rest shape puts it once that shape is
    /// moved to the body's centroid and turned to fit it best (shape matching,
    /// Müller, Heidelberger, Teschner and Gross 2005; in the plane the best
    /// turn has a closed form).
    func solveShape() {
        let center = self.center
        var sumCos = 0.0, sumSin = 0.0
        for i in particles.indices {
            let p = particles[i].position - center
            let q = restOffsets[i]
            sumCos += p.dot(q)
            sumSin += q.cross(p)
        }
        let turn = atan2(sumSin, sumCos)
        let cosine = cos(turn), sine = sin(turn)
        let alpha = shapeScale
        for i in particles.indices {
            let w = weight(i)
            guard w > 0 else { continue }
            let q = restOffsets[i]
            let goal = center + Vector2(q.x * cosine - q.y * sine, q.x * sine + q.y * cosine)
            let delta = particles[i].position - goal
            let distance = delta.length
            guard distance > 1e-12 else { continue }
            let dLambda = (-distance - alpha * shapeLambdas[i]) / (w + alpha)
            shapeLambdas[i] += dLambda
            particles[i].position += delta / distance * (dLambda * w)
        }
    }

    // MARK: Geometry

    /// Ring `r`'s signed area now: positive for an outer ring, negative for
    /// a hole.
    func ringArea(_ r: Int) -> Double {
        var sum = 0.0
        for i in rings[r] {
            let a = particles[i].position, b = particles[next[i]].position
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Refresh each island's box from its particles.
    func refreshBoxes() {
        boxes = islands.map { island in
            var box = Box(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)
            for r in island {
                for i in rings[r] {
                    let p = particles[i].position
                    box.minX = Swift.min(box.minX, p.x); box.maxX = Swift.max(box.maxX, p.x)
                    box.minY = Swift.min(box.minY, p.y); box.maxY = Swift.max(box.maxY, p.y)
                }
            }
            return box
        }
    }

    /// Whether `point` is inside ring `r` on its own, by even-odd crossings.
    func ring(_ r: Int, contains point: Vector2) -> Bool {
        var inside = false
        for i in rings[r] {
            let a = particles[i].position, b = particles[next[i]].position
            if (a.y > point.y) != (b.y > point.y),
               point.x < a.x + (b.x - a.x) * (point.y - a.y) / (b.y - a.y) {
                inside.toggle()
            }
        }
        return inside
    }

    /// Whether `point` is in island `k`'s material: inside its outer ring and
    /// outside each of its holes.
    func island(_ k: Int, contains point: Vector2) -> Bool {
        var inside = false
        for r in islands[k] where ring(r, contains: point) { inside.toggle() }
        return inside
    }

    /// The point on `ringIndices`' edges nearest `point`: which edge (named by
    /// the particle it starts at), how far along it, the point itself, and the
    /// distance to it.
    func nearestEdge(to point: Vector2, on ringIndices: [Int])
        -> (edge: Int, t: Double, point: Vector2, distance: Double) {
        var best = (edge: -1, t: 0.0, point: point, distance: Double.infinity)
        var bestSquared = Double.infinity
        for r in ringIndices {
            for i in rings[r] {
                let a = particles[i].position, b = particles[next[i]].position
                let ab = b - a
                let lengthSquared = ab.lengthSquared
                let t = lengthSquared > 1e-18
                    ? Swift.min(1, Swift.max(0, (point - a).dot(ab) / lengthSquared)) : 0
                let closest = a + ab * t
                let squared = (point - closest).lengthSquared
                if squared < bestSquared {
                    bestSquared = squared
                    best = (i, t, closest, 0)
                }
            }
        }
        best.distance = bestSquared.squareRoot()
        return best
    }

    /// Push `particle` out of island `k` until it sits `radius` clear of it,
    /// sharing the correction with the two ends of the edge it meets in
    /// proportion to how much each can move. A contact has no give: it holds
    /// or it is not touching.
    func pushOut(_ particle: Particle, radius: Double, island k: Int) {
        let p = particle.position
        let inside = island(k, contains: p)
        guard inside || radius > 0 else { return }
        let near = nearestEdge(to: p, on: islands[k])
        guard near.edge >= 0, inside || near.distance < radius else { return }
        if inside {
            separate(particle, toward: near, depth: near.distance + radius)
        } else {
            separate(particle, awayFrom: near, depth: radius - near.distance)
        }
    }

    /// Keep each island's rings on the material's side of one another: a hole
    /// inside its outer ring and outside every other hole, the outer ring
    /// outside every hole. Without it a hole's ring, carried on by what it
    /// weighs when the outer ring stops against the floor, passes straight
    /// through it.
    func keepRingsApart() {
        for island in islands where island.count > 1 {
            let outer = island[0]
            for r in island {
                for other in island where other != r {
                    for i in rings[r] {
                        let p = particles[i].position
                        let inside = ring(other, contains: p)
                        guard other == outer ? !inside : inside else { continue }
                        let near = nearestEdge(to: p, on: [other])
                        guard near.edge >= 0 else { continue }
                        separate(particles[i], toward: near, depth: near.distance)
                    }
                }
            }
        }
    }

    /// Move `particle` onto `near` by `depth`, the edge's two ends taking
    /// their share the other way.
    private func separate(_ particle: Particle,
                          toward near: (edge: Int, t: Double, point: Vector2, distance: Double),
                          depth: Double) {
        let p = particle.position
        var normal: Vector2
        if near.distance > 1e-9 {
            normal = (near.point - p) / near.distance
        } else {
            // On the outline itself: out through the edge. An outer ring winds
            // with positive area, so its outside lies to the edge's right in
            // these axes; a hole winds the other way, which puts the outside
            // of the material on the same side.
            let a = particles[near.edge].position, b = particles[next[near.edge]].position
            let edge = b - a
            guard edge.lengthSquared > 1e-18 else { return }
            normal = Vector2(edge.y, -edge.x).normalized
        }
        apply(particle, along: normal, depth: depth, near: near)
    }

    /// Move `particle` away from `near` by `depth`, for a particle with a
    /// radius that sits outside the outline but too close to it.
    private func separate(_ particle: Particle,
                          awayFrom near: (edge: Int, t: Double, point: Vector2, distance: Double),
                          depth: Double) {
        guard near.distance > 1e-9 else { return }
        apply(particle, along: (particle.position - near.point) / near.distance,
              depth: depth, near: near)
    }

    /// The contact's correction: `particle` along `normal`, the edge's ends
    /// against it, by inverse mass and by how near each end the contact is.
    private func apply(_ particle: Particle, along normal: Vector2, depth: Double,
                       near: (edge: Int, t: Double, point: Vector2, distance: Double)) {
        let a = near.edge, b = next[near.edge], t = near.t
        let wp = particle.isPinned ? 0 : particle.inverseMass
        let wa = weight(a), wb = weight(b)
        let denominator = wp + (1 - t) * (1 - t) * wa + t * t * wb
        guard denominator > 1e-18 else { return }
        let lambda = depth / denominator
        particle.position += normal * (lambda * wp)
        particles[a].position -= normal * (lambda * wa * (1 - t))
        particles[b].position -= normal * (lambda * wb * t)
    }

    // MARK: Settings as numbers

    /// A 0…1 setting as a relative give: `0` at `1` (no give at all), about a
    /// tenth at `0.5`, and nearly ten times the length at `0.01`. A constraint
    /// with this softness, carrying the body's own weight, gives that share of
    /// what it holds; the same reading the 3D cloth's settings take.
    static func softness(for setting: Double) -> Double {
        guard setting < 1 else { return 0 }
        return (1 / Swift.max(setting, 1e-3) - 1) / 10
    }

    /// Twice the signed area of a closed polygon, halved.
    static func signedArea(of points: [Vector2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}

extension World {

    /// Turn `shape` into a soft body and return it: a ring of particles round
    /// each of its outlines that keeps its area, bends, bounces off the walls,
    /// and collides with every other soft body outline against outline.
    ///
    /// The particles go where the shape's points are, so build the shape where
    /// the body should start. Every closed contour becomes a ring, its fill
    /// read under the shape's own winding rule, so a letter's counter is a
    /// hole the body keeps and a shape of several islands is one body whose
    /// islands hold together through `shapeMemory`. To let each island go its
    /// own way, give each its own body:
    ///
    /// ```swift
    /// for letter in word.separated() {
    ///     try world.addSoftBody(from: letter)
    /// }
    /// ```
    ///
    /// Each outline is resampled to particles about `spacing` apart, keeping
    /// its corners (any turn sharper than 30 degrees) as particles of their
    /// own, so a star keeps its points. Particles with a positive radius, with
    /// `particlesCollide` on, are pushed out of every soft body too. Rigid
    /// `Body`s pass through soft ones, and a body never collides with itself.
    ///
    /// - Parameters:
    ///   - shape: the outline, where the body starts.
    ///   - mass: the whole body's weight, split evenly between its particles.
    ///   - spacing: the distance between neighboring particles along the
    ///     outline, in points. Finer holds a detailed outline closer at a cost
    ///     that grows with the count; the settings below mean the same body
    ///     at any spacing.
    ///   - stiffness: how hard the outline resists being stretched, `0` slack
    ///     … `1` inextensible.
    ///   - bend: how hard each corner resists being folded, `0` limp … `1`
    ///     holding every turn it was made with.
    ///   - pressure: how firmly the body holds its area, in gravities (its own
    ///     weight presses out `1 / pressure` of it); `.infinity` keeps it
    ///     exactly and `0` lets it go.
    ///   - shapeMemory: how strongly the body is pulled back toward its own
    ///     shape, `0` not at all … `1` rigid.
    /// - Throws: `PhysicsError.unbuildable` for a shape with no closed outline
    ///   that encloses any area, or a setting that is not a number.
    @discardableResult
    public func addSoftBody(from shape: Shape, mass: Double = 1, spacing: Double = 8,
                            stiffness: Double = 0.8, bend: Double = 0.2,
                            pressure: Double = .infinity,
                            shapeMemory: Double = 0.3) throws -> SoftBody {
        try check(mass, "addSoftBody's mass")
        try check(spacing, "addSoftBody's spacing")
        try check(stiffness, "addSoftBody's stiffness")
        try check(bend, "addSoftBody's bend")
        try check(pressure, "addSoftBody's pressure", orUnbounded: true)
        try check(shapeMemory, "addSoftBody's shapeMemory")
        for contour in shape.contours {
            for point in contour.points {
                if let complaint = SolverNumber.complaint(point) {
                    throw PhysicsError.unbuildable("addSoftBody's shape has a point that is \(complaint)")
                }
            }
        }
        guard mass > 0 else {
            throw PhysicsError.unbuildable("addSoftBody needs a mass above zero; nothing was added")
        }
        guard spacing > 0 else {
            throw PhysicsError.unbuildable("addSoftBody needs a spacing above zero; nothing was added")
        }

        // The fill as it draws: overlaps merged and holes found under the
        // shape's own rule, then each island with its holes.
        let closed = shape.contours.filter { $0.isClosed && $0.points.count >= 3 }
        let resolved = Shape(contours: closed, winding: shape.winding).union(Shape(contours: []))
        var rings: [[Vector2]] = []
        var islands: [[Int]] = []
        for island in resolved.separated() {
            var members: [Int] = []
            for (k, contour) in island.contours.enumerated() {
                var ring = World.ring(along: contour, spacing: spacing)
                let signed = SoftBody.signedArea(of: ring)
                guard ring.count >= 3, abs(signed) > 1e-9 else {
                    if k == 0 { break } else { continue }
                }
                // The outer ring winds with positive area and each hole with
                // negative, so an island's area is the plain sum.
                if (signed > 0) != (k == 0) { ring.reverse() }
                members.append(rings.count)
                rings.append(ring)
            }
            if !members.isEmpty { islands.append(members) }
        }
        guard !rings.isEmpty else {
            throw PhysicsError.unbuildable("addSoftBody needs a shape with a closed outline that "
                                           + "encloses some area; nothing was added")
        }

        let pull = gravity.length > 1e-6 ? gravity.length : 980
        let body = SoftBody(world: self, rings: rings, islands: islands, mass: mass,
                            stiffness: stiffness, bend: bend, pressure: Swift.max(0, pressure),
                            shapeMemory: shapeMemory, pull: pull)
        register(body)
        return body
    }

    /// The outline as a ring of points about `spacing` apart, its corners kept
    /// as points of their own and each run between two corners cut evenly.
    static func ring(along contour: Contour, spacing: Double) -> [Vector2] {
        let pieces = contour.split(atCornersOver: .pi / 6)
        if pieces.count == 1, pieces[0].isClosed {
            var loop = contour.points
            loop.append(loop[0])
            let count = Swift.max(8, Int((contour.length / spacing).rounded()))
            return evenly(along: loop, count: count)
        }
        var ring: [Vector2] = []
        for piece in pieces {
            let count = Swift.max(1, Int((piece.length / spacing).rounded()))
            ring += evenly(along: piece.points, count: count)
        }
        return ring
    }

    /// `count` points at even steps along the open run `points`, from its
    /// start up to but not including its end.
    static func evenly(along points: [Vector2], count: Int) -> [Vector2] {
        guard points.count >= 2 else { return points }
        var total = 0.0
        for i in 1 ..< points.count { total += points[i].distance(to: points[i - 1]) }
        guard total > 1e-12 else { return [points[0]] }
        var result: [Vector2] = []
        var segment = 1
        var walked = 0.0
        for k in 0 ..< count {
            let target = total * Double(k) / Double(count)
            while segment < points.count - 1,
                  walked + points[segment].distance(to: points[segment - 1]) < target {
                walked += points[segment].distance(to: points[segment - 1])
                segment += 1
            }
            let a = points[segment - 1], b = points[segment]
            let length = a.distance(to: b)
            let t = length > 1e-12 ? Swift.min(1, (target - walked) / length) : 0
            result.append(a + (b - a) * t)
        }
        return result
    }

    /// Push every particle out of every soft body it has entered: each
    /// island's particles out of every other island, in this body or another,
    /// each island's rings kept on the right side of one another, and, with
    /// `particlesCollide` on, every loose particle with a radius out of them
    /// all. Walked in the order the bodies and particles were added, so a
    /// seeded run settles the same way every time.
    func solveSoftContacts() {
        var pieces: [(body: SoftBody, island: Int)] = []
        for body in softBodies {
            body.refreshBoxes()
            for k in body.islands.indices { pieces.append((body, k)) }
        }
        for m in pieces.indices {
            let (a, j) = pieces[m]
            for n in pieces.indices where n > m {
                let (b, k) = pieces[n]
                let boxA = a.boxes[j], boxB = b.boxes[k]
                guard boxA.minX <= boxB.maxX, boxB.minX <= boxA.maxX,
                      boxA.minY <= boxB.maxY, boxB.minY <= boxA.maxY else { continue }
                for r in a.islands[j] {
                    for i in a.rings[r] where boxB.holds(a.particles[i].position, margin: 0) {
                        b.pushOut(a.particles[i], radius: 0, island: k)
                    }
                }
                for r in b.islands[k] {
                    for i in b.rings[r] where boxA.holds(b.particles[i].position, margin: 0) {
                        a.pushOut(b.particles[i], radius: 0, island: j)
                    }
                }
            }
        }
        for body in softBodies { body.keepRingsApart() }
        guard particlesCollide else { return }
        for particle in particles where particle.radius > 0 && particle.softBody == nil {
            for (body, k) in pieces
            where body.boxes[k].holds(particle.position, margin: particle.radius) {
                body.pushOut(particle, radius: particle.radius, island: k)
            }
        }
    }
}

extension SoftBody {
    /// An axis-aligned box by its edges, the broad phase's test.
    struct Box {
        var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0

        /// Whether `point` is within `margin` of the box.
        func holds(_ point: Vector2, margin: Double) -> Bool {
            point.x >= minX - margin && point.x <= maxX + margin
                && point.y >= minY - margin && point.y <= maxY + margin
        }
    }
}
