import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid, OllinSPHParams

/// A particle fluid: tens of thousands of particles that press apart when crowded
/// and pull together at the surface, so they pour, splash, pile, and settle like
/// water (smoothed-particle hydrodynamics, the classic particle method for liquids
/// with a free surface: Müller, Charypar & Gross 2003, plus the near-pressure
/// anti-clustering term of Clavet, Beaudoin & Poulin 2005). Runs on the GPU over
/// the `SpatialHash` neighbor search, inside a walled box you can splash with the
/// mouse.
///
/// Build one in `setup()`, then step and draw it in `draw()`:
///
/// ```swift
/// var fluid: ParticleFluid!
/// override func setup() {
///     fluid = particleFluid(count: 24_000, radius: 12)
/// }
/// override func draw() {
///     background(.black)
///     if mouseIsPressed { fluid.pull(at: Vector2(mouseX, mouseY)) }
///     updateParticleFluid(fluid)
///     drawParticles(fluid)
/// }
/// ```
///
/// `count`, `radius` (the interaction range, which is also the fluid's resolution),
/// and the seeded block are fixed at build; the live feel comes from `gravity`,
/// `stiffness`, `nearStiffness`, `viscosity`, and the wall `bounce` (tune them, or
/// bind them to `@Param`s). Particles tint from `colorSlow` to `colorFast` by speed.
///
/// Each frame runs a few fixed substeps; each substep predicts where particles are
/// heading, measures how crowded each one is there (a density and a sharper
/// near-density), turns crowding into pressure, and nudges velocities apart with
/// equal-and-opposite forces, so momentum balances without any cross-thread
/// writes. The near-pressure term is what keeps particles from clumping into
/// stacks and, at the surface, is what pulls stray drops into beads and filaments.
@MainActor
public final class ParticleFluid {
    /// Particle count.
    public let count: Int
    /// The interaction radius (points): the fluid's resolution. Smaller is finer
    /// (and denser, since the seeded spacing scales with it).
    public let radius: Double
    /// The seeded inter-particle spacing (points); also the drawn particle size.
    public let spacing: Double
    /// The walled box the fluid lives in.
    public let bounds: Rectangle

    /// Downward pull, points/s². Flip it, tilt it, or zero it for drifting blobs.
    public var gravity = Vector2(0, 1500)
    /// Pressure strength (roughly the fluid's speed of sound, squared). Higher is
    /// less compressible but wants more `substeps` to stay stable.
    public var stiffness: Double = 240_000
    /// The always-repulsive short-range pressure that keeps particles from
    /// clumping and gives the surface its bead-and-filament tension.
    public var nearStiffness: Double = 150_000
    /// Target density relative to the seeded packing (1 = as seeded). Below 1 the
    /// fluid relaxes looser; above 1 it contracts.
    public var restDensity: Double = 1.0
    /// Neighborhood velocity smoothing per substep (0…1). Higher is syrupier.
    public var viscosity: Double = 0.12
    /// Fraction of the normal velocity kept when a particle hits a wall (0…1).
    public var bounce: Double = 0.25
    /// Fixed substeps per frame (2…8 sensible). More lets `stiffness` run higher.
    public var substeps: Int = 4
    /// Particle color at rest.
    public var colorSlow = Color(red: 0.05, green: 0.30, blue: 0.95)
    /// Particle color at `speedForFastColor` and beyond.
    public var colorFast = Color(red: 0.72, green: 0.95, blue: 1.0)
    /// The speed (points/s) at which a particle reaches `colorFast`.
    public var speedForFastColor: Double = 1_100

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private let scratch: ComputeBuffer<OllinParticle>       // predicted evaluation state
    private let densities: ComputeBuffer<SIMD2<Float>>      // (density, near-density)
    private let predictKernel: ComputeKernel
    private let densityKernel: ComputeKernel
    private let forceKernel: ComputeKernel

    // The one-frame interaction, consumed by the next `recordStep`.
    private var interactionPoint = Vector2(0, 0)
    private var interactionStrength: Double = 0
    private var interactionRadius: Double = 0

    /// Build `count` particles inside `bounds`, interacting within `radius`, seeded
    /// as a jittered block (a dam ready to break) from `seed`. `spacing` defaults
    /// to `radius * 0.45` (about 15 neighbors each at rest).
    public init(count: Int, bounds: Rectangle, radius: Double, spacing: Double? = nil,
                seed: UInt64) {
        precondition(count > 0, "ParticleFluid needs a positive count")
        precondition(radius > 0, "ParticleFluid needs a positive radius")
        let s = spacing ?? radius * 0.45
        precondition(s > 0 && s < radius, "spacing must be positive and below radius")
        self.count = count
        self.radius = radius
        self.spacing = s
        self.bounds = bounds
        self.hash = SpatialHash(bounds: bounds, cellSize: radius, count: count)

        // Seed a block: wider than tall, centered, hanging in the upper half so the
        // first frames are a splash. Jitter breaks the lattice so pressure doesn't
        // release along grid lines.
        var rng = SplitMix64(seed: seed)
        let cols = max(1, min(Int((Double(count) * 2.2).squareRoot().rounded(.up)),
                              Int(bounds.width * 0.86 / s)))
        let rows = (count + cols - 1) / cols
        let x0 = bounds.x + (bounds.width - Double(cols - 1) * s) / 2
        let y0 = max(bounds.y + s, bounds.y + bounds.height * 0.42 - Double(rows) * s)
        var seeds: [OllinParticle] = []
        seeds.reserveCapacity(count)
        let slow = SIMD4<Float>(Float(colorSlow.red), Float(colorSlow.green),
                                Float(colorSlow.blue), Float(colorSlow.alpha))
        for i in 0..<count {
            let cx = i % cols, cy = i / cols
            let jx = Double.random(in: -0.05...0.05, using: &rng) * s
            let jy = Double.random(in: -0.05...0.05, using: &rng) * s
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(x0 + Double(cx) * s + jx),
                                       Float(y0 + Double(cy) * s + jy)),
                velocity: SIMD2<Float>(0, 0),
                color: slow, size: Float(s), life: 1, seedA: 0, seedB: 0))
        }
        self.pingpong = PingPong(seeds)
        self.scratch = ComputeBuffer(count: count)
        self.densities = ComputeBuffer(count: count)

        let source = ParticleFluid.makeKernelSource(radius: radius, spacing: s)
        self.predictKernel = ComputeKernel(entry: "ollin_sph_predict", source)
        self.densityKernel = ComputeKernel(entry: "ollin_sph_density", source)
        self.forceKernel = ComputeKernel(entry: "ollin_sph_force", source)
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Pull the fluid toward `point` this frame (call it every frame while a drag
    /// is held; it clears after the step). `strength` is an acceleration, pt/s².
    public func pull(at point: Vector2, strength: Double = 2_600, radius: Double = 140) {
        interactionPoint = point
        interactionStrength = strength
        interactionRadius = radius
    }

    /// Push the fluid away from `point` this frame (the splash). See `pull`.
    public func push(at point: Vector2, strength: Double = 2_600, radius: Double = 140) {
        pull(at: point, strength: -strength, radius: radius)
    }

    /// Record one frame: `substeps` fixed substeps, each predicting evaluation
    /// positions, rebuilding the neighbor hash over them, measuring densities, and
    /// applying pressure + viscosity before integrating. Called by
    /// `Sketch.updateParticleFluid`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        let steps = max(1, min(substeps, 8))
        let dtFrame = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        let bytes = paramBytes(dt: dtFrame / Double(steps))
        for _ in 0..<steps {
            let read = pingpong.read, write = pingpong.write
            drawer.recordDispatch(RecordedDispatch(
                kernel: predictKernel, threadCount: count,
                buffers: [read, scratch], params: bytes))
            hash.recordBuild(into: drawer, positions: scratch)
            drawer.recordDispatch(RecordedDispatch(
                kernel: densityKernel, threadCount: count,
                buffers: [scratch, nil, hash.sortedIndices, hash.cellStart,
                          hash.cellCount, hash.gridBuffer, densities], params: bytes))
            drawer.recordDispatch(RecordedDispatch(
                kernel: forceKernel, threadCount: count,
                buffers: [scratch, write, hash.sortedIndices, hash.cellStart,
                          hash.cellCount, hash.gridBuffer, densities, read],
                params: bytes))
            pingpong.advance()
        }
        interactionStrength = 0   // the pull/push lasts one frame
    }

    private func paramBytes(dt: Double) -> [UInt8] {
        // Inset the walls by half a particle so drawn discs rest on, not in, them.
        let inset = spacing * 0.5
        var p = OllinSPHParams()
        p.gravity = SIMD2<Float>(Float(gravity.x), Float(gravity.y))
        p.interactionPoint = SIMD2<Float>(Float(interactionPoint.x), Float(interactionPoint.y))
        p.box = SIMD4<Float>(Float(bounds.x + inset), Float(bounds.y + inset),
                             Float(bounds.x + bounds.width - inset),
                             Float(bounds.y + bounds.height - inset))
        p.colorSlow = SIMD4<Float>(Float(colorSlow.red), Float(colorSlow.green),
                                   Float(colorSlow.blue), Float(colorSlow.alpha))
        p.colorFast = SIMD4<Float>(Float(colorFast.red), Float(colorFast.green),
                                   Float(colorFast.blue), Float(colorFast.alpha))
        p.interactionStrength = Float(interactionStrength)
        p.interactionRadius = Float(max(interactionRadius, 1))
        p.restDensity = Float(restDensity)
        p.stiffness = Float(max(stiffness, 0))
        p.nearStiffness = Float(max(nearStiffness, 0))
        p.viscosity = Float(min(max(viscosity, 0), 1))
        p.dt = Float(dt)
        p.wallBounce = Float(min(max(bounce, 0), 1))
        p.speedForFastColor = Float(max(speedForFastColor, 1))
        p.predictDt = Float(1.0 / 120.0)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: p) { bytes.append(contentsOf: $0) }
        return bytes
    }

    /// The kernel-sum a particle reads on its own seeded lattice (self included):
    /// the reference the GPU densities are normalized by, so density 1 means
    /// "packed as seeded" whatever the radius. Internal for the tests.
    static func latticeDensity(radius h: Double, spacing s: Double) -> (density: Double, near: Double) {
        let norm2 = 6.0 / (.pi * h * h)
        let norm3 = 10.0 / (.pi * h * h)
        var d = 0.0, dn = 0.0
        let reach = Int((h / s).rounded(.up))
        for i in -reach...reach {
            for j in -reach...reach {
                let r = Double(i * i + j * j).squareRoot() * s
                guard r < h else { continue }
                let q = 1 - r / h
                d += norm2 * q * q
                dn += norm3 * q * q * q
            }
        }
        return (d, dn)
    }

    /// The three kernels, with the radius and the 2D kernel constants baked in as
    /// literals (fixed at build, like the seeded lattice they normalize against).
    /// Density uses the quadratic spike (1 − r/h)² and near-density the cubic
    /// (1 − r/h)³, both normalized over the disc; the pressure gradients are their
    /// radial derivatives, which do not vanish as r → 0, so crowded particles
    /// always feel a shove apart. Every pass is a pure gather over a consistent
    /// snapshot (the predicted positions plus this substep's densities), so the
    /// symmetric pair terms cancel to equal-and-opposite without atomics.
    private static func makeKernelSource(radius h: Double, spacing s: Double) -> String {
        let rho = latticeDensity(radius: h, spacing: s)
        func lit(_ v: Double) -> String { String(format: "%.9e", v) }
        let norm2 = 6.0 / (.pi * h * h)
        let norm3 = 10.0 / (.pi * h * h)
        return """
        constant float SPH_H        = \(lit(h));
        constant float SPH_W2_SELF  = \(lit(norm2 / rho.density));
        constant float SPH_W3_SELF  = \(lit(norm3 / rho.near));
        constant float SPH_GRAD2    = \(lit(12.0 / (.pi * h * h * h) / rho.density));
        constant float SPH_GRAD3    = \(lit(30.0 / (.pi * h * h * h) / rho.near));

        // Fallback direction for a fully coincident pair: a fixed per-particle
        // angle, so the pair separates instead of dividing by zero.
        static inline float2 ollin_sph_apart(uint id) {
            float a = hash11(float(id) * 0.6180339887) * 6.2831853;
            return float2(cos(a), sin(a));
        }

        // External forces (gravity + the one-frame pull/push) onto velocity, then
        // a fixed short look-ahead: the positions every evaluation pass reads.
        kernel void ollin_sph_predict(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinSPHParams &P       [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle p = inBuf[id];
            float2 a = P.gravity;
            if (P.interactionStrength != 0.0) {
                float2 d = P.interactionPoint - p.position;
                float dist = length(d);
                if (dist < P.interactionRadius) {
                    float t = 1.0 - dist / P.interactionRadius;
                    float2 dir = dist > 1e-4 ? d / dist : float2(0.0);
                    float st = P.interactionStrength;
                    if (st > 0.0) {
                        // A grab: fade gravity inside the radius and damp the swirl
                        // so held fluid hangs instead of orbiting or streaming down.
                        float g = clamp(st / max(length(P.gravity), 1.0), 0.0, 1.0);
                        a = P.gravity * (1.0 - t * g) + dir * (t * st)
                          - p.velocity * (t * st / P.interactionRadius);
                    } else {
                        a += dir * (t * st);
                    }
                }
            }
            p.velocity += P.dt * a;
            p.position += P.predictDt * p.velocity;
            outBuf[id] = p;
        }

        // Crowding at the predicted positions: density (quadratic kernel) and the
        // sharper near-density (cubic), both normalized so 1 = the seeded packing.
        // Distances are plain (the box is walls, not a torus): the hash's wrapped
        // 3x3 block may offer far-wall particles near the edges, and the r < h
        // test is what rejects them.
        kernel void ollin_sph_density(
            device const OllinParticle *evalBuf [[buffer(0)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid [[buffer(5)]],
            device float2 *densities        [[buffer(6)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinSPHParams &P       [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            float2 pos = evalBuf[id].position;
            float d = SPH_W2_SELF;
            float dn = SPH_W3_SELF;
            OLLIN_FOR_NEIGHBORS(pos, grid, sortedIdx, cellStart, cellCount, j)
                if (j == id) { continue; }
                float r = length(evalBuf[j].position - pos);
                if (r < SPH_H) {
                    float q = 1.0 - r / SPH_H;
                    d  += SPH_W2_SELF * q * q;
                    dn += SPH_W3_SELF * q * q * q;
                }
            OLLIN_END_NEIGHBORS
            densities[id] = float2(d, dn);
        }

        // Pressure from crowding (shared between each pair, so the push is
        // equal-and-opposite), neighborhood velocity smoothing, then integrate
        // from the *original* position and bounce off the walls.
        kernel void ollin_sph_force(
            device const OllinParticle *evalBuf [[buffer(0)]],
            device OllinParticle       *outBuf  [[buffer(1)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid  [[buffer(5)]],
            device const float2 *densities   [[buffer(6)]],
            device const OllinParticle *origBuf [[buffer(7)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinSPHParams &P       [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle p = evalBuf[id];
            float2 rho = densities[id];
            float pressI     = P.stiffness * (rho.x - P.restDensity);
            float pressNearI = P.nearStiffness * rho.y;

            float2 acc = float2(0.0);
            float2 smooth = float2(0.0);
            OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
                if (j == id) { continue; }
                float2 dvec = evalBuf[j].position - p.position;
                float r = length(dvec);
                if (r < SPH_H) {
                    float q = 1.0 - r / SPH_H;
                    float2 rhoJ = densities[j];
                    float pressJ     = P.stiffness * (rhoJ.x - P.restDensity);
                    float pressNearJ = P.nearStiffness * rhoJ.y;
                    float2 dir = r > 1e-4 ? dvec / r : ollin_sph_apart(id);
                    float shared = 0.5 * (pressI + pressJ) * SPH_GRAD2 * q
                                 + 0.5 * (pressNearI + pressNearJ) * SPH_GRAD3 * q * q;
                    acc -= dir * (shared / max(rhoJ.x, 0.05));
                    smooth += (evalBuf[j].velocity - p.velocity) * (SPH_W2_SELF * q * q);
                }
            OLLIN_END_NEIGHBORS

            float2 v = p.velocity + P.dt * acc + P.viscosity * smooth;
            // A particle never crosses more than half a radius per substep, so it
            // can't tunnel a neighbor however hard it was flung.
            float vmax = 0.45 * SPH_H / P.dt;
            float sp = length(v);
            if (sp > vmax) { v *= vmax / sp; }

            float2 x = origBuf[id].position + P.dt * v;
            if (x.x < P.box.x) { x.x = P.box.x; v.x =  fabs(v.x) * P.wallBounce; }
            if (x.x > P.box.z) { x.x = P.box.z; v.x = -fabs(v.x) * P.wallBounce; }
            if (x.y < P.box.y) { x.y = P.box.y; v.y =  fabs(v.y) * P.wallBounce; }
            if (x.y > P.box.w) { x.y = P.box.w; v.y = -fabs(v.y) * P.wallBounce; }

            float s01 = clamp(length(v) / P.speedForFastColor, 0.0, 1.0);
            p.color = mix(P.colorSlow, P.colorFast, s01);
            p.position = x;
            p.velocity = v;
            outBuf[id] = p;
        }
        """
    }
}
