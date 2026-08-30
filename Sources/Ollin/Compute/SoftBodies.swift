import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid, OllinSoftBody, OllinSoftBodyParams

/// Squishy blobs: each body is a cloud of particles that remembers its rest shape
/// and is pulled back toward the best-fit rotation of that shape every step
/// (meshless shape matching, Müller, Heidelberger, Teschner & Gross 2005). The
/// pull is a single stiffness dial that cannot blow up: soft bodies squash on
/// impact, wobble, and recover, and even a fully crushed blob springs back. Bodies
/// collide with each other through the `SpatialHash` neighbor search and tumble
/// under gravity inside a walled box.
///
/// Build them in `setup()`, then step and draw in `draw()`:
///
/// ```swift
/// var blobs: SoftBodies!
/// override func setup() {
///     blobs = makeSoftBodies(bodies: 12, radius: 80)
/// }
/// override func draw() {
///     background(.black)
///     if mouseIsPressed { blobs.pull(at: Vector2(mouseX, mouseY)) }
///     updateSoftBodies(blobs)
///     drawParticles(blobs)
/// }
/// ```
///
/// Each substep, one small pass per body finds its current centroid and the
/// rotation that best maps its rest layout onto today's (the closed-form 2D fit:
/// the summed cross and dot products of rest offsets against current ones,
/// normalized); every particle then steers toward its rotated rest position at
/// `squish` strength. There are no springs to tune and no stiff system to
/// integrate, which is why the blobs stay stable at any setting.
@MainActor
public final class SoftBodies {
    /// Number of bodies.
    public let bodies: Int
    /// Total particle count across all bodies.
    public let count: Int
    /// The nominal blob radius (points); each body varies around it.
    public let radius: Double
    /// The seeded particle spacing inside a blob (points).
    public let spacing: Double
    /// The walled box the bodies live in.
    public let bounds: Rectangle

    /// Downward pull, points/s².
    public var gravity = Vector2(0, 1600)
    /// How firmly a body holds its shape, 0…1 (the shape-match pull per frame).
    /// Low is jelly, high is rubber.
    public var squish: Double = 0.3
    /// Fraction of the normal velocity kept when a particle hits a wall (0…1).
    public var bounce: Double = 0.35
    /// Fraction of velocity kept per second (0…1). Lower settles the pile faster.
    public var damping: Double = 0.4
    /// Repulsion acceleration between touching bodies, points/s² at full overlap.
    public var collisionStrength: Double = 35_000
    /// Fixed substeps per frame (2…8 sensible).
    public var substeps: Int = 4

    /// Where each body was seeded (its rest centroid), in seeding order. The live
    /// centroids evolve on the GPU; this is the CPU-known starting layout.
    let seededCenters: [Vector2]

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private let bodyBuffer: ComputeBuffer<OllinSoftBody>
    private let reduceKernel: ComputeKernel
    private let stepKernel: ComputeKernel
    private let collisionRadius: Double

    // The one-frame interaction, consumed by the next `recordStep`.
    private var interactionPoint = Vector2(0, 0)
    private var interactionStrength: Double = 0
    private var interactionRadius: Double = 0

    /// Build `bodies` blobs of roughly `radius` (each varies 0.72…1.15 of it) inside
    /// `bounds`, scattered in the upper half from `seed` so they fall into a pile.
    /// `spacing` is the particle spacing inside a blob (default `radius / 5.5`).
    public init(bodies bodyCount: Int, bounds: Rectangle, radius: Double,
                spacing: Double? = nil, seed: Int) {
        precondition(bodyCount > 0, "SoftBodies needs a positive count")
        precondition(radius > 0, "SoftBodies needs a positive radius")
        let s = max(spacing ?? radius / 5.5, 3)
        precondition(s < radius, "spacing must be below radius")
        self.bodies = bodyCount
        self.radius = radius
        self.spacing = s
        self.bounds = bounds
        self.collisionRadius = s * 1.5

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))

        // Scatter body centers in the upper part of the box, then relax the circles
        // apart: a blob that spawns inside another starts with a violent overlap the
        // collision pass turns into an explosion, so separated spawns are load-bearing.
        let spawnArea = Rectangle(x: bounds.x, y: bounds.y,
                                  width: bounds.width, height: bounds.height * 0.72)
        var circles: [Circle] = (0..<bodyCount).map { _ in
            let r = radius * Double.random(in: 0.72...1.15, using: &rng)
            let x = Double.random(in: (spawnArea.x + r)...(spawnArea.x + spawnArea.width - r), using: &rng)
            let y = Double.random(in: (spawnArea.y + r)...(spawnArea.y + spawnArea.height - r), using: &rng)
            return Circle(center: Vector2(x, y), radius: r)
        }
        circles = relaxCircles(circles, in: spawnArea, iterations: 60, padding: s)
        let centers = circles.map { ($0.center, $0.radius) }

        // Fill each blob with a hex lattice of particles; the rest offset rides
        // seedA/seedB and the body index rides life, so the step kernel can build
        // its goal position without any extra per-particle buffer.
        var seeds: [OllinParticle] = []
        var ranges: [OllinSoftBody] = []
        for (b, (center, r)) in centers.enumerated() {
            let start = seeds.count
            let hue = Double(b) / Double(bodyCount)
            let c = Color(hue: hue.truncatingRemainder(dividingBy: 1),
                          saturation: 0.68, brightness: 1.0)
            let color = SIMD4<Float>(Float(c.red), Float(c.green), Float(c.blue), 1)
            let rowStep = s * 3.0.squareRoot() / 2
            var offsets: [Vector2] = []
            var row = 0
            var y = -r
            while y <= r {
                let xOffset = row % 2 == 0 ? 0 : s / 2
                var x = -r + xOffset
                while x <= r {
                    if (x * x + y * y).squareRoot() <= r - s * 0.25 {
                        offsets.append(Vector2(x, y))
                    }
                    x += s
                }
                row += 1
                y += rowStep
            }
            precondition(!offsets.isEmpty, "SoftBodies blob radius too small for its spacing")
            // Rest offsets must be relative to the rest *centroid* (the mean of the
            // lattice points, which the hex rows shift off the disk center), or the
            // summed shape-match pull is nonzero and the body silently thrusts
            // itself around: goals would sit shifted from the particles even at
            // perfect rest, and that uniform pull never cancels.
            let mean = offsets.reduce(Vector2(0, 0), +) / Double(offsets.count)
            for q in offsets {
                let o = q - mean
                seeds.append(OllinParticle(
                    position: SIMD2<Float>(Float(center.x + o.x), Float(center.y + o.y)),
                    velocity: SIMD2<Float>(0, 0),
                    color: color, size: Float(s * 1.35), life: Float(b),
                    seedA: Float(o.x), seedB: Float(o.y)))
            }
            ranges.append(OllinSoftBody(
                center: SIMD2<Float>(Float(center.x), Float(center.y)),
                rotation: SIMD2<Float>(1, 0),
                start: UInt32(start), count: UInt32(offsets.count), _bodyPad: .zero))
        }
        self.count = seeds.count
        self.seededCenters = centers.map(\.0)
        self.pingpong = PingPong(seeds)
        self.bodyBuffer = ComputeBuffer(ranges)
        self.hash = SpatialHash(bounds: bounds, cellSize: collisionRadius, count: seeds.count)

        let source = SoftBodies.kernelSource
        self.reduceKernel = ComputeKernel(entry: "ollin_softbody_reduce", source)
        self.stepKernel = ComputeKernel(entry: "ollin_softbody_step", source)
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Pull the bodies toward `point` this frame (call it every frame while a drag
    /// is held; it clears after the step). `strength` is an acceleration, pt/s².
    public func pull(at point: Vector2, strength: Double = 3_200, radius: Double = 170) {
        interactionPoint = point
        interactionStrength = strength
        interactionRadius = radius
    }

    /// Push the bodies away from `point` this frame. See `pull`.
    public func push(at point: Vector2, strength: Double = 3_200, radius: Double = 170) {
        pull(at: point, strength: -strength, radius: radius)
    }

    /// Record one frame: per substep, build the neighbor hash, fit each body's
    /// centroid + rotation, then steer, collide, and integrate every particle.
    /// Called by `Sketch.updateSoftBodies`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        let steps = max(1, min(substeps, 8))
        let dtFrame = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        let dt = dtFrame / Double(steps)
        let bytes = paramBytes(dt: dt)
        for _ in 0..<steps {
            let read = pingpong.read, write = pingpong.write
            hash.recordBuild(into: drawer, positions: read)
            drawer.recordDispatch(RecordedDispatch(
                kernel: reduceKernel, threadCount: bodies,
                buffers: [read, nil, nil, nil, nil, nil, bodyBuffer], params: bytes))
            drawer.recordDispatch(RecordedDispatch(
                kernel: stepKernel, threadCount: count,
                buffers: [read, write, hash.sortedIndices, hash.cellStart,
                          hash.cellCount, hash.gridBuffer, bodyBuffer], params: bytes))
            pingpong.advance()
        }
        interactionStrength = 0
    }

    private func paramBytes(dt: Double) -> [UInt8] {
        let inset = spacing * 0.7
        // `squish` is the pull per 1/60 s frame; convert to this substep's alpha so
        // the feel doesn't change with the substep count or the frame rate.
        let alpha = 1 - pow(1 - min(max(squish, 0), 0.999), dt * 60)
        var p = OllinSoftBodyParams()
        p.gravity = SIMD2<Float>(Float(gravity.x), Float(gravity.y))
        p.interactionPoint = SIMD2<Float>(Float(interactionPoint.x), Float(interactionPoint.y))
        p.box = SIMD4<Float>(Float(bounds.x + inset), Float(bounds.y + inset),
                             Float(bounds.x + bounds.width - inset),
                             Float(bounds.y + bounds.height - inset))
        p.interactionStrength = Float(interactionStrength)
        p.interactionRadius = Float(max(interactionRadius, 1))
        p.stiffness = Float(alpha)
        p.collisionRadius = Float(collisionRadius)
        p.collisionStrength = Float(max(collisionStrength, 0))
        p.dt = Float(dt)
        p.wallBounce = Float(min(max(bounce, 0), 1))
        p.damping = Float(min(max(damping, 0.001), 1))
        var bytes: [UInt8] = []
        withUnsafeBytes(of: p) { bytes.append(contentsOf: $0) }
        return bytes
    }

    /// Two kernels. The reduce is one thread per body (dozens of bodies, hundreds
    /// of particles each, so a serial loop per body is cheap, the same trade the
    /// hash's prefix-sum makes); it writes the centroid and the closed-form 2D
    /// best-fit rotation of rest offsets onto current ones. The step is one thread
    /// per particle: steer toward the rotated rest position, repel touching
    /// particles of *other* bodies (the same-body shape is the fit's job), then
    /// integrate and bounce off the walls.
    private static let kernelSource = """
    static inline float2 ollin_softbody_apart(uint id) {
        float a = hash11(float(id) * 0.6180339887) * 6.2831853;
        return float2(cos(a), sin(a));
    }

    kernel void ollin_softbody_reduce(
        device const OllinParticle *inBuf [[buffer(0)]],
        device OllinSoftBody *bodies      [[buffer(6)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }   // dispatched one thread per body
        OllinSoftBody b = bodies[id];
        float2 cm = float2(0.0);
        for (uint k = b.start; k < b.start + b.count; ++k) {
            cm += inBuf[k].position;
        }
        cm /= float(b.count);
        // Best-fit rotation of rest offsets q onto current offsets p: the angle
        // whose cosine/sine are the normalized sums of dot(q,p) and cross(q,p).
        float cc = 0.0, sc = 0.0;
        for (uint k = b.start; k < b.start + b.count; ++k) {
            float2 p = inBuf[k].position - cm;
            float2 q = float2(inBuf[k].seedA, inBuf[k].seedB);
            cc += q.x * p.x + q.y * p.y;
            sc += q.x * p.y - q.y * p.x;
        }
        float len = sqrt(cc * cc + sc * sc);
        bodies[id].center = cm;
        bodies[id].rotation = len > 1e-5 ? float2(cc, sc) / len : float2(1.0, 0.0);
    }

    kernel void ollin_softbody_step(
        device const OllinParticle *inBuf  [[buffer(0)]],
        device OllinParticle       *outBuf [[buffer(1)]],
        device const uint *sortedIdx [[buffer(2)]],
        device const uint *cellStart [[buffer(3)]],
        device const uint *cellCount [[buffer(4)]],
        constant OllinSpatialGrid &grid       [[buffer(5)]],
        device const OllinSoftBody *bodies    [[buffer(6)]],
        constant OllinComputeUniforms &u  [[buffer(10)]],
        constant OllinSoftBodyParams &P   [[buffer(11)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        OllinParticle p = inBuf[id];
        uint bodyId = uint(p.life + 0.5);
        OllinSoftBody b = bodies[bodyId];

        // The goal: this particle's rest offset, rotated by the body's best fit,
        // hung on the current centroid. Steering toward it at alpha is the whole
        // elasticity model.
        float2 q = float2(p.seedA, p.seedB);
        float2 goal = b.center + float2(b.rotation.x * q.x - b.rotation.y * q.y,
                                        b.rotation.y * q.x + b.rotation.x * q.y);
        float2 v = p.velocity + (goal - p.position) * (P.stiffness / P.dt);

        float2 a = P.gravity;
        if (P.interactionStrength != 0.0) {
            float2 d = P.interactionPoint - p.position;
            float dist = length(d);
            if (dist < P.interactionRadius) {
                float t = 1.0 - dist / P.interactionRadius;
                float2 dir = dist > 1e-4 ? d / dist : float2(0.0);
                float st = P.interactionStrength;
                if (st > 0.0) {
                    float g = clamp(st / max(length(P.gravity), 1.0), 0.0, 1.0);
                    a = P.gravity * (1.0 - t * g) + dir * (t * st)
                      - p.velocity * (t * st / P.interactionRadius);
                } else {
                    a += dir * (t * st);
                }
            }
        }

        // Contact: particles of *other* bodies within the collision radius push
        // this one away, proportionally to overlap, and shed the pair's approach
        // speed along the normal (each side takes half, so the contact is
        // inelastic and a pile settles instead of jittering). Both sides compute
        // the same pair from the same snapshot, so every shove is equal-and-opposite.
        OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
            if (j == id) { continue; }
            OllinParticle other = inBuf[j];
            if (uint(other.life + 0.5) == bodyId) { continue; }
            float2 dvec = other.position - p.position;
            float r = length(dvec);
            if (r < P.collisionRadius) {
                float overlap = 1.0 - r / P.collisionRadius;
                float2 dir = r > 1e-4 ? dvec / r : ollin_softbody_apart(id);
                a -= dir * (overlap * P.collisionStrength);
                float approach = dot(p.velocity - other.velocity, dir);
                if (approach > 0.0) { v -= dir * (0.5 * overlap * approach); }
            }
        OLLIN_END_NEIGHBORS

        v += P.dt * a;
        v *= pow(P.damping, P.dt);
        float vmax = 0.45 * P.collisionRadius / P.dt;
        float sp = length(v);
        if (sp > vmax) { v *= vmax / sp; }

        float2 x = p.position + P.dt * v;
        if (x.x < P.box.x) { x.x = P.box.x; v.x =  fabs(v.x) * P.wallBounce; }
        if (x.x > P.box.z) { x.x = P.box.z; v.x = -fabs(v.x) * P.wallBounce; }
        if (x.y < P.box.y) { x.y = P.box.y; v.y =  fabs(v.y) * P.wallBounce; }
        if (x.y > P.box.w) { x.y = P.box.w; v.y = -fabs(v.y) * P.wallBounce; }

        p.position = x;
        p.velocity = v;
        outBuf[id] = p;
    }
    """
}
