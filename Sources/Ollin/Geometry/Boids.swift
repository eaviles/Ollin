import Foundation

/// A flock of boids: many simple agents whose local rules produce lifelike
/// flocking. Each boid steers by three forces over the neighbors it can see,
/// and coherent flocks, swirls, and splits emerge with no leader (the classic
/// flocking model).
///
/// - **Separation** steers away from crowding neighbors.
/// - **Alignment** steers toward the average heading of nearby boids.
/// - **Cohesion** steers toward the average position of nearby boids.
///
/// It's a stateful simulation you hold and `step()` each frame. `positions`,
/// `velocities`, and `heading(_:)` are the flock's live state, which you draw
/// however you like (a triangle per boid pointing along its heading, a trail, a
/// dot). Seed it for a reproducible flock. Set a `field` to make the flock also
/// follow a `FlowField`.
///
/// ```swift
/// let flock = Boids(count: 400, in: bounds, seed: 7)
///
/// override func draw() {
///     flock.step()
///     background(.black); fill(.white)
///     drawBoids(flock, size: 10)
/// }
/// ```
public final class Boids {
    /// The boids' positions.
    public private(set) var positions: [Vector2]
    /// The boids' velocities (their length is the speed, direction the heading).
    public private(set) var velocities: [Vector2]
    /// The rectangle the flock stays inside.
    public let bounds: Rectangle

    /// Steer-away-from-crowding weight.
    public var separation: Double = 1.6
    /// Match-neighbors'-heading weight.
    public var alignment: Double = 1.0
    /// Steer-toward-neighbors'-center weight.
    public var cohesion: Double = 0.9
    /// The radius within which a boid sees others for alignment and cohesion.
    public var perceptionRadius: Double
    /// The (smaller) radius within which a boid is pushed away from others.
    public var separationRadius: Double
    /// The top speed a boid may travel.
    public var maxSpeed: Double
    /// The strongest steering a boid may apply per step.
    public var maxForce: Double
    /// How far from an edge a boid begins steering back inward.
    public var margin: Double
    /// An optional flow field the flock also follows.
    public var field: FlowField?
    /// How strongly the flock follows `field`.
    public var fieldStrength: Double = 0

    private var rng: SplitMix64

    /// A flock of `count` boids placed at random inside `bounds`.
    public init(count: Int, in bounds: Rectangle, seed: UInt64 = 0,
                maxSpeed: Double = 3, maxForce: Double = 0.12,
                perceptionRadius: Double = 50, separationRadius: Double = 22,
                margin: Double = 60) {
        self.bounds = bounds
        self.maxSpeed = maxSpeed
        self.maxForce = maxForce
        self.perceptionRadius = perceptionRadius
        self.separationRadius = separationRadius
        self.margin = margin
        var rng = SplitMix64(seed: seed)
        self.positions = (0 ..< Swift.max(count, 0)).map { _ in
            Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                    bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height)
        }
        self.velocities = (0 ..< Swift.max(count, 0)).map { _ in
            let a = Double.random(in: 0 ..< (2 * .pi), using: &rng)
            let s = maxSpeed * (0.5 + 0.5 * Double.random(in: 0 ..< 1, using: &rng))
            return Vector2(cos(a) * s, sin(a) * s)
        }
        self.rng = rng
    }

    /// The number of boids.
    public var count: Int { positions.count }

    /// The heading (radians) of boid `i`, from its velocity.
    public func heading(_ i: Int) -> Double { velocities[i].angle }

    /// Advance the flock one step: steer every boid by separation, alignment,
    /// cohesion (and the flow field, if set), keep it inside `bounds`, and move.
    public func step() {
        let n = positions.count
        guard n > 1 else { return }

        let cell = Swift.max(perceptionRadius, separationRadius, 1e-6)
        var grid: [BoidCell: [Int]] = [:]
        grid.reserveCapacity(n)
        for i in 0 ..< n {
            grid[BoidCell(positions[i], cell), default: []].append(i)
        }

        let perc2 = perceptionRadius * perceptionRadius
        let sep2 = separationRadius * separationRadius
        var newVelocities = velocities

        for i in 0 ..< n {
            let p = positions[i]
            var separationForce = Vector2.zero
            var headingSum = Vector2.zero
            var centerSum = Vector2.zero
            var separationCount = 0, neighborCount = 0

            let col = Int(floor((p.x - bounds.x) / cell)), row = Int(floor((p.y - bounds.y) / cell))
            for cc in (col - 1) ... (col + 1) {
                for rr in (row - 1) ... (row + 1) {
                    guard let bucket = grid[BoidCell(column: cc, row: rr)] else { continue }
                    for j in bucket where j != i {
                        let offset = p - positions[j]
                        let d2 = offset.lengthSquared
                        if d2 < perc2 {
                            headingSum = headingSum + velocities[j]
                            centerSum = centerSum + positions[j]
                            neighborCount += 1
                        }
                        if d2 < sep2, d2 > 1e-9 {
                            separationForce = separationForce + offset * (1 / d2)   // stronger when closer
                            separationCount += 1
                        }
                    }
                }
            }

            var acceleration = Vector2.zero
            if separationCount > 0 {
                acceleration = acceleration + steer(toward: separationForce, from: velocities[i]) * separation
            }
            if neighborCount > 0 {
                acceleration = acceleration + steer(toward: headingSum, from: velocities[i]) * alignment
                let center = centerSum * (1 / Double(neighborCount))
                acceleration = acceleration + steer(toward: center - p, from: velocities[i]) * cohesion
            }
            if let field, fieldStrength > 0 {
                acceleration = acceleration + steer(toward: field.direction(at: p), from: velocities[i]) * fieldStrength
            }
            acceleration = acceleration + edgeForce(at: p)

            newVelocities[i] = (velocities[i] + acceleration).limited(to: maxSpeed)
        }

        velocities = newVelocities
        for i in 0 ..< n { positions[i] = positions[i] + velocities[i] }
    }

    /// Advance the flock by `steps` steps.
    public func step(_ steps: Int) {
        for _ in 0 ..< Swift.max(steps, 0) { step() }
    }

    // MARK: - Steering

    /// The steering force toward a desired direction: aim at top speed along
    /// `direction`, subtract the current velocity, and cap the turn.
    private func steer(toward direction: Vector2, from velocity: Vector2) -> Vector2 {
        guard direction.lengthSquared > 1e-12 else { return .zero }
        let desired = direction.normalized * maxSpeed
        return (desired - velocity).limited(to: maxForce)
    }

    /// A force that pushes a boid back inside `bounds` as it nears an edge.
    private func edgeForce(at p: Vector2) -> Vector2 {
        let push = maxForce * 1.8
        var dx = 0.0, dy = 0.0
        if p.x < bounds.x + margin { dx += push }
        if p.x > bounds.x + bounds.width - margin { dx -= push }
        if p.y < bounds.y + margin { dy += push }
        if p.y > bounds.y + bounds.height - margin { dy -= push }
        return Vector2(dx, dy)
    }
}

/// A uniform-grid cell key for the flock's neighbor search.
private struct BoidCell: Hashable {
    let column: Int, row: Int
    init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
    init(column: Int, row: Int) { self.column = column; self.row = row }
    init(_ p: Vector2, _ cell: Double) {
        self.column = Int(floor(p.x / cell))
        self.row = Int(floor(p.y / cell))
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Draw each boid of `flock` as a triangle of the given `size` pointing along
    /// its heading, filled with the current `fill`.
    func drawBoids(_ flock: Boids, size: Double = 10) {
        for i in 0 ..< flock.count {
            let p = flock.positions[i]
            let a = flock.heading(i)
            let nose = Vector2(p.x + cos(a) * size, p.y + sin(a) * size)
            let left = Vector2(p.x + cos(a + 2.5) * size * 0.7, p.y + sin(a + 2.5) * size * 0.7)
            let right = Vector2(p.x + cos(a - 2.5) * size * 0.7, p.y + sin(a - 2.5) * size * 0.7)
            drawTriangle(nose, left, right)
        }
    }
}
