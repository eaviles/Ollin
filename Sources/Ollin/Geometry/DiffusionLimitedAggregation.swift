import Foundation

/// Diffusion-limited aggregation: random walkers drift in from far away and
/// freeze the moment they touch the growing cluster, so the cluster grows the
/// branching, dendritic fingers of frost, coral, and mineral deposits (the
/// classic aggregation model). Tips catch walkers before hollows ever see
/// one, which is the whole secret of the shape.
///
/// It's a stateful stepper you hold: `step()` walks one particle until it
/// sticks, `step(_:)` grows a batch per frame. Seed it for a reproducible
/// cluster. Particles carry a `parent` link, so the cluster draws as dots
/// (`positions`) or as a branching skeleton (`segments`).
///
/// ```swift
/// let cluster = DiffusionLimitedAggregation(seeds: [center], seed: 7)
///
/// override func draw() {
///     cluster.step(12)
///     background(.black); fill(.white); noStroke()
///     drawCircles(cluster.positions, radius: 3)
/// }
/// ```
public final class DiffusionLimitedAggregation {
    /// One frozen particle of the cluster.
    public struct Particle {
        /// Where the particle froze.
        public let position: Vector2
        /// The index of the particle it stuck to (`nil` for a seed).
        public let parent: Int?
    }

    /// The cluster so far (seeds first, then in sticking order).
    public private(set) var particles: [Particle]
    /// The particle radius (two particles touch at twice this distance).
    public let particleRadius: Double
    /// The chance (`0...1`) that a touching walker sticks. `1` sticks on
    /// first contact and grows wispy fingers; lower values let walkers slide
    /// deeper before freezing, so the cluster grows denser and rounder.
    public var stickiness: Double
    /// An optional cage: walkers never leave it, and growth stops reaching
    /// past it.
    public var bounds: Rectangle?
    /// A cap on the cluster's size.
    public var maxParticles: Int

    private var rng: SplitMix64
    /// The frozen particles, kept in step with `particles`: a point's index in
    /// the index is its index in that array.
    private var index = SpatialIndex(bounds: Rectangle(x: 0, y: 0, width: 0, height: 0),
                                     cellSize: 1)
    private var center: Vector2
    private var clusterRadius: Double = 0

    /// A cluster started from `seeds` (one frozen particle each).
    public init(seeds: [Vector2], particleRadius: Double = 4, stickiness: Double = 1,
                bounds: Rectangle? = nil, maxParticles: Int = 20000, seed: UInt64 = 0) {
        let radius = Swift.max(particleRadius, 0.5)
        self.particleRadius = radius
        self.stickiness = Swift.min(Swift.max(stickiness, 0.01), 1)
        self.bounds = bounds
        self.maxParticles = maxParticles
        self.rng = SplitMix64(seed: seed)
        self.index = SpatialIndex(bounds: bounds ?? Rectangle(x: 0, y: 0, width: 0, height: 0),
                                  cellSize: radius * 4)
        self.particles = []
        self.center = .zero
        guard !seeds.isEmpty else { return }
        self.center = seeds.reduce(.zero, +) / Double(seeds.count)
        for p in seeds { freeze(Particle(position: p, parent: nil)) }
    }

    /// The number of particles frozen so far.
    public var count: Int { particles.count }

    /// The frozen positions, ready for `drawCircles`.
    public var positions: [Vector2] { particles.map(\.position) }

    /// The cluster as line segments (each particle to the one it stuck to),
    /// the branching skeleton for stroking or SVG export.
    public var segments: [(Vector2, Vector2)] {
        particles.compactMap { particle in
            particle.parent.map { (particles[$0].position, particle.position) }
        }
    }

    /// Walk one particle in from the edge until it sticks. Returns the index
    /// of the new particle, or `nil` once the cluster is full.
    @discardableResult
    public func step() -> Int? {
        guard !particles.isEmpty, particles.count < maxParticles else { return nil }

        let touch = particleRadius * 2
        let spawnRadius = clusterRadius + touch * 3
        let killRadius = spawnRadius * 2 + touch * 8

        // Give a walker a few lives so a step can't stall forever when the
        // cage is tight or the walker drifts away.
        for _ in 0 ..< 64 {
            var p = spawnPoint(spawnRadius)
            for _ in 0 ..< 4000 {
                // Far from the cluster the walker jumps its whole free
                // distance at once; near it, it diffuses one radius at a time.
                let fromCenter = p.distance(to: center)
                let free = fromCenter - clusterRadius - touch * 2
                let stride = Swift.max(particleRadius, free)
                p += Vector2(angle: Double.random(in: 0 ..< .tau, using: &rng), length: stride)
                if let bounds { p = clamped(p, to: bounds) }

                if p.distance(to: center) > killRadius { break }   // drifted off, respawn
                if let hit = touching(p, within: touch) {
                    if Double.random(in: 0 ..< 1, using: &rng) < stickiness {
                        // Land exactly at touching distance from the particle
                        // it stuck to, so the cluster stays evenly knit.
                        let anchor = particles[hit].position
                        let position = anchor + (p - anchor).normalized * touch
                        freeze(Particle(position: position, parent: hit))
                        return particles.count - 1
                    }
                }
            }
        }
        return nil
    }

    /// Walk `count` particles in.
    public func step(_ count: Int) {
        for _ in 0 ..< Swift.max(count, 0) {
            if step() == nil { return }
        }
    }

    // MARK: - Internals

    private func freeze(_ particle: Particle) {
        particles.append(particle)
        index.insert(particle.position)
        clusterRadius = Swift.max(clusterRadius, particle.position.distance(to: center))
    }

    /// A random point on the spawn circle (clamped into the cage, if any).
    private func spawnPoint(_ radius: Double) -> Vector2 {
        let p = center + Vector2(angle: Double.random(in: 0 ..< .tau, using: &rng), length: radius)
        if let bounds { return clamped(p, to: bounds) }
        return p
    }

    private func clamped(_ p: Vector2, to r: Rectangle) -> Vector2 {
        Vector2(Swift.min(Swift.max(p.x, r.x), r.x + r.width),
                Swift.min(Swift.max(p.y, r.y), r.y + r.height))
    }

    /// The index of a frozen particle within `distance` of `p`, if any.
    private func touching(_ p: Vector2, within distance: Double) -> Int? {
        index.anyNeighbor(of: p, within: distance)
    }
}
