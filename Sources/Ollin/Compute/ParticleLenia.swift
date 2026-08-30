import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid, OllinLeniaParams

/// Particle Lenia: matter that organizes itself, written as an energy field rather
/// than a force law. Every particle sums a ring-shaped kernel over its neighbors to
/// get a field value, a growth function scores that field, a repulsion term keeps
/// anything closer than one unit apart, and a particle simply walks downhill on the
/// result. Out of those three lines come membranes, cells that hold a shape, rotors,
/// crawlers, and things that divide.
///
/// Written from Mordvintsev, Niklasson and Randazzo's energy-based formulation, which
/// rebuilt the grid-based continuous automaton as particles. It runs here on the GPU
/// over the `SpatialHash` neighbor search, so tens of thousands of particles find
/// their structure in real time. Build one in `setup()`, step and draw it in `draw()`:
///
/// ```swift
/// var lenia: ParticleLenia!
/// override func setup() {
///     background(.black); noClear()
///     lenia = makeParticleLenia(count: 6000, spacing: 9)
/// }
/// override func draw() {
///     background(.black)
///     blendMode(.add)
///     updateParticleLenia(lenia)
///     drawParticles(lenia)
/// }
/// ```
///
/// There is no velocity and no per-particle state: a particle's whole future is the
/// shape of the field around it, which is why the same six numbers can produce such
/// different worlds. `muK` and `sigmaK` set the ring a particle reaches with, `muG`
/// and `sigmaG` say which crowding it prefers, and `cRep` how hard it refuses to be
/// stood on. `spacing` is the only length a sketch names: everything else is measured
/// in the model's own units, so a configuration keeps its shape at any size.
@MainActor
public final class ParticleLenia {
    /// Particle count.
    public let count: Int
    /// Canvas points per model unit: how large the structures are drawn.
    public let spacing: Double

    /// Where the kernel's ring of influence sits, in model units. A particle is most
    /// aware of others at roughly this distance, which is what sets how wide a
    /// membrane can be.
    public var muK: Double = 4.0 { didSet { wK = ParticleLenia.normalization(muK, sigmaK) } }
    /// How wide that ring is. Narrow is a shell that only feels one distance; wide
    /// blurs into a plain neighborhood.
    public var sigmaK: Double = 1.0 { didSet { wK = ParticleLenia.normalization(muK, sigmaK) } }
    /// The field value growth peaks at: the crowding a particle is trying to sit in.
    public var muG: Double = 0.6
    /// How narrow that preference is. Small is fussy, and fussy is what makes an
    /// edge sharp.
    public var sigmaG: Double = 0.15
    /// How hard two particles closer than one unit push apart. This is the only term
    /// that stops the whole population collapsing to a point.
    public var cRep: Double = 1.0

    /// Model time per second of wall clock. The published step is 0.1, and a step
    /// larger than that is integrating a different model, so asking for more pace
    /// splits the frame into as many steps as it takes rather than taking a coarser
    /// one.
    public var speed: Double = 1.0
    /// The largest step the model is integrated at, in model time.
    public var maxStep: Double = 0.1

    /// Dot diameter, points.
    public var size: Double = 2.4
    /// How much light one particle contributes, 0…1.
    public var opacity: Double = 0.85

    /// The field ramp: a particle is colored by how crowded it is, as a fraction of
    /// the crowding the growth function wants, so the ramp's middle is a particle
    /// sitting exactly where the rule prefers. That makes the inside of a cell, its
    /// membrane, and a particle out on its own read differently, which is the whole
    /// structure. One color is a flat color; past four stops the ramp is resampled.
    ///
    /// The default stops shift hue and hold their brightness roughly level, for the
    /// reason the attractor flow's do: drawn additively, brightness already means how
    /// many particles are piled here.
    public var colors: [Color] = [Color(red: 0.20, green: 0.28, blue: 0.72),
                                  Color(red: 0.25, green: 0.72, blue: 0.85),
                                  Color(red: 0.95, green: 0.80, blue: 0.35),
                                  Color(red: 0.92, green: 0.35, blue: 0.42)]

    /// The kernel's normalization over the plane. Not a free parameter: it is fixed by
    /// `muK` and `sigmaK`, and deriving it is what keeps `muG` meaning the same
    /// crowding when the ring moves.
    private(set) var wK: Double

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private let kernel: ComputeKernel

    /// Build `count` particles over `bounds`, with one model unit drawn `spacing`
    /// points wide. They start in a disc at the middle, packed at about one particle
    /// per unit of area, which is the density the repulsion term itself describes:
    /// scattered over the whole canvas instead, most of them would begin outside
    /// everyone's kernel with nothing to organize with. `seed` makes that opening
    /// scatter reproducible.
    public init(count: Int, bounds: Rectangle, spacing: Double, seed: Int) {
        precondition(count > 0, "ParticleLenia needs a positive count")
        precondition(spacing > 0, "ParticleLenia needs a positive spacing")
        self.count = count
        self.spacing = spacing
        self.wK = ParticleLenia.normalization(4.0, 1.0)

        // The kernel has no hard edge, so the search radius is where it has decayed to
        // nothing (four widths out, about one part in ten million), and never less than
        // the repulsion's own reach of one unit.
        let reach = max(1.0, 4.0 + 4 * 1.0) * spacing
        self.hash = SpatialHash(bounds: bounds, cellSize: reach, count: count)

        let placed = ParticleLenia.seedPositions(count: count, center: bounds.center,
                                                 spacing: spacing, seed: UInt64(bitPattern: Int64(seed)))
        let dot = Float(size)   // a local: the map must not capture a half-built self
        let seeds = placed.map {
            OllinParticle(position: $0, velocity: SIMD2<Float>(0, 0),
                          color: SIMD4<Float>(1, 1, 1, 1),
                          size: dot, life: 1, seedA: 0, seedB: 0)
        }
        self.pingpong = PingPong(seeds)
        self.kernel = ParticleLenia.makeKernel()
    }

    /// Where the particles start: a disc holding about one of them per unit of area,
    /// which is the density the repulsion term itself describes. Scattered over a whole
    /// canvas instead, most would open outside everyone's kernel with nothing to
    /// organize with, and the first thing a viewer would see is a minute of nothing.
    static func seedPositions(count: Int, center: Vector2, spacing: Double,
                              seed: UInt64) -> [SIMD2<Float>] {
        let discRadius = (Double(count) / .pi).squareRoot() * spacing
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            // Uniform over the disc: the square root is what keeps it from bunching in
            // the middle.
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let r = discRadius * Double.random(in: 0..<1, using: &rng).squareRoot()
            out.append(SIMD2<Float>(Float(center.x + cos(a) * r), Float(center.y + sin(a) * r)))
        }
        return out
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// The kernel's normalization over the plane, in closed form.
    ///
    /// The weight is whatever makes `∫ K dA = 1`, and that integral has an exact
    /// value: `∫₀^∞ 2πr·exp(−((r−μ)/σ)²) dr = πσ(μ√π(1+erf(μ/σ)) + σ·exp(−(μ/σ)²))`.
    /// At the published μ=4, σ=1 it comes to 44.5466, whose reciprocal is 0.02245,
    /// the 0.022 the paper prints.
    static func normalization(_ mu: Double, _ sigma: Double) -> Double {
        let s = max(sigma, 1e-9), m = max(mu, 0)
        let a = m / s
        let integral = .pi * s * (m * Double.pi.squareRoot() * (1 + erf(a)) + s * exp(-a * a))
        return integral > 1e-12 ? 1 / integral : 0
    }

    /// Record one frame: as many model steps as the pace asks for, each one a fresh
    /// neighbor sort followed by the gradient step. Called by
    /// `Sketch.updateParticleLenia`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        // A hitch must not tear the structure apart, so the frame's own step is capped
        // the way the other particle systems cap theirs.
        let frame = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        let wanted = max(speed, 0) * frame
        let cap = max(maxStep, 1e-4)
        guard wanted > 0 else { return }
        // Never a step larger than the model was published at: past that the gradient
        // overshoots its own repulsion core and the structure boils.
        let steps = min(Int((wanted / cap).rounded(.up)), 8)
        let dt = wanted / Double(steps)
        for _ in 0..<steps {
            let read = pingpong.read, write = pingpong.write
            hash.recordBuild(into: drawer, positions: read)
            drawer.recordDispatch(RecordedDispatch(
                kernel: kernel, threadCount: count,
                buffers: [read, write, hash.sortedIndices, hash.cellStart, hash.cellCount,
                          hash.gridBuffer],
                params: paramBytes(dt: dt)))
            pingpong.advance()
        }
    }

    private func paramBytes(dt: Double) -> [UInt8] {
        var p = OllinLeniaParams()
        p.muK = Float(max(muK, 0))
        p.sigmaK = Float(max(sigmaK, 1e-4))
        p.wK = Float(wK)
        p.muG = Float(max(muG, 1e-4))
        p.sigmaG = Float(max(sigmaG, 1e-4))
        p.cRep = Float(max(cRep, 0))
        p.spacing = Float(spacing)
        p.dt = Float(dt)
        p.size = Float(max(size, 0))

        let ramp = rampStops()
        p.stopCount = UInt32(ramp.count)
        withUnsafeMutableBytes(of: &p.stops) { raw in
            let slots = raw.bindMemory(to: SIMD4<Float>.self)
            for i in 0..<slots.count { slots[i] = ramp[min(i, ramp.count - 1)] }
        }

        var bytes: [UInt8] = []
        withUnsafeBytes(of: p) { bytes.append(contentsOf: $0) }
        return bytes
    }

    /// The field ramp as at most four stops, with `opacity` scaling whatever alpha the
    /// colors already carry.
    private func rampStops() -> [SIMD4<Float>] {
        let alpha = Float(min(max(opacity, 0), 1))
        let source = colors.isEmpty ? [Color.white] : colors
        let stops: [SIMD4<Float>]
        if source.count <= 4 {
            stops = source.map(\.simd4)
        } else {
            stops = (0..<4).map { i in
                let t = Double(i) / 3 * Double(source.count - 1)
                let a = min(Int(t), source.count - 1)
                let b = min(a + 1, source.count - 1)
                return Color.mix(source[a], source[b], t - Double(a)).simd4
            }
        }
        return stops.map { SIMD4<Float>($0.x, $0.y, $0.z, $0.w * alpha) }
    }

    // MARK: The kernel

    /// The gradient step.
    ///
    /// One pass over the neighbors accumulates three things at once: the field value
    /// `U`, its gradient, and the gradient of the repulsion. The growth term can only
    /// be applied after the loop, because it is a function *of* `U`, but its
    /// derivative is a scalar, so the field gradient collected along the way is still
    /// the right vector to scale. That is what keeps the whole model to a single pass.
    ///
    /// Distances are converted into model units on the way in and the resulting
    /// displacement back into points on the way out, so `spacing` never leaks into the
    /// model's own arithmetic.
    private static func makeKernel() -> ComputeKernel {
        let source = """
        kernel void ollin_lenia_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid [[buffer(5)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinLeniaParams &L     [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle p = inBuf[id];
            float2 pos = p.position;
            float sp = max(L.spacing, 1e-6);

            // A particle counts in its own field. It is the same constant for everyone,
            // so it shifts nothing, but the model is stated that way and the shift is
            // free.
            float selfZ = L.muK / L.sigmaK;
            float U = L.wK * exp(-selfZ * selfZ);
            float2 gradU = float2(0.0);   // per model unit
            float2 gradR = float2(0.0);

            OLLIN_FOR_NEIGHBORS(pos, grid, sortedIdx, cellStart, cellCount, j)
                if (j == id) { continue; }
                // From the neighbor to me: the direction the distance grows in, which
                // is the direction both gradients are expressed along.
                float2 d = ollin_torus_delta(inBuf[j].position, pos, grid.worldSize);
                float rp = length(d);
                if (rp > grid.cellSize || rp < 1e-9) { continue; }
                float2 dir = d / rp;
                float r = rp / sp;

                float z = (r - L.muK) / L.sigmaK;
                float k = L.wK * exp(-z * z);
                U += k;
                gradU += dir * (k * (-2.0 * z / L.sigmaK));

                // The repulsion has a hard edge at one unit, and only inside it.
                float over = 1.0 - r;
                if (over > 0.0) { gradR -= dir * (L.cRep * over); }
            OLLIN_END_NEIGHBORS

            // Growth scores the field the particle found itself in; its slope says
            // which way that score improves.
            float gz = (U - L.muG) / L.sigmaG;
            float g = exp(-gz * gz);
            float dG = g * (-2.0 * gz / L.sigmaG);

            // E = R - G(U), and a particle walks against its gradient.
            float2 gradE = gradR - dG * gradU;
            float2 stepModel = -gradE * L.dt;
            float2 stepPoints = stepModel * sp;

            p.position = pos + stepPoints;
            // No force law here, so there is no velocity to carry; the displacement is
            // kept anyway because it is what the motion actually is.
            p.velocity = stepPoints / max(L.dt, 1e-6);
            p.size = L.size;

            // Crowding as a fraction of the crowding the rule wants, with the ramp's
            // middle at exactly that. Inside a cell, on its membrane, and alone all
            // land in different places.
            float t = clamp(U / (2.0 * L.muG), 0.0, 1.0);
            float f = t * float(L.stopCount - 1);
            uint lo = min(uint(f), L.stopCount - 1);
            uint hi = min(lo + 1, L.stopCount - 1);
            p.color = mix(L.stops[lo], L.stops[hi], f - float(lo));

            // Toroidal wrap, matching how the neighbor grid wraps.
            float2 rel = p.position - grid.origin;
            rel = rel - grid.worldSize * floor(rel / grid.worldSize);
            p.position = grid.origin + rel;
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_lenia_step", source)
    }
}
