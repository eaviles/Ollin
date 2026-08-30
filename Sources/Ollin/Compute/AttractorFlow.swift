import Foundation
import simd
import COllinShaders   // OllinPoint, OllinAttractorParams

/// One of the classic chaotic systems, as a value the GPU can run: which velocity
/// field, with which constants, and the integration step it was published at.
///
/// The factories mirror `StrangeAttractor`'s, defaults and all, and `attractor`
/// hands back that CPU twin, so the same system can be integrated once into a
/// `[Vector3]` orbit or ridden by a million particles without the two disagreeing.
public struct AttractorSystem: Sendable, Equatable {

    /// The systems the kernel knows how to integrate. Internal: a sketch builds one
    /// through the static factories below. The `shaderIndex` order is the switch's
    /// order in the kernel and must stay in step with it.
    enum Kind: Sendable, Equatable {
        case lorenz(sigma: Double, rho: Double, beta: Double)
        case rossler(a: Double, b: Double, c: Double)
        case aizawa(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double)
        case thomas(b: Double)
        case halvorsen(a: Double)
        case dadras(a: Double, b: Double, c: Double, d: Double, e: Double)
        case chen(alpha: Double, beta: Double, delta: Double)
        case fourWing(a: Double, b: Double, c: Double)
    }

    let kind: Kind

    /// The integration step the system was tuned at, in its own time. The step a
    /// running flow takes is never larger than this: past it the integrator is
    /// solving a different system.
    public let step: Double

    /// The initial condition to integrate from. Stay off the system's fixed points (the
    /// origin is one for several of them) or the orbit never moves.
    public let start: Vector3

    private init(_ kind: Kind, step: Double, start: Vector3) {
        self.kind = kind
        self.step = step
        self.start = start
    }

    /// Lorenz's system, the original strange attractor (a model of atmospheric
    /// convection): two lobes the orbit weaves between, the butterfly shape.
    public static func lorenz(sigma: Double = 10, rho: Double = 28, beta: Double = 8.0 / 3.0,
                              start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.01) -> AttractorSystem {
        AttractorSystem(.lorenz(sigma: sigma, rho: rho, beta: beta), step: step, start: start)
    }

    /// Rössler's system: a single spiral that stretches outward on a sheet, then
    /// folds back, a cleaner band than Lorenz's two lobes.
    public static func rossler(a: Double = 0.2, b: Double = 0.2, c: Double = 5.7,
                               start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.02) -> AttractorSystem {
        AttractorSystem(.rossler(a: a, b: b, c: c), step: step, start: start)
    }

    /// Aizawa's system: an orbit that wraps a torus while drilling through its axis,
    /// a spiralling sphere-and-spindle shape.
    public static func aizawa(a: Double = 0.95, b: Double = 0.7, c: Double = 0.6, d: Double = 3.5,
                              e: Double = 0.25, f: Double = 0.1,
                              start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.01) -> AttractorSystem {
        AttractorSystem(.aizawa(a: a, b: b, c: c, d: d, e: e, f: f), step: step, start: start)
    }

    /// Thomas's cyclically symmetric system: a looping, almost knotted lattice walk,
    /// symmetric across all three axes.
    public static func thomas(b: Double = 0.208186,
                              start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.05) -> AttractorSystem {
        AttractorSystem(.thomas(b: b), step: step, start: start)
    }

    /// Halvorsen's cyclically symmetric system: three intertwined scrolls.
    public static func halvorsen(a: Double = 1.89,
                                 start: Vector3 = Vector3(-1.48, -1.51, 2.04),
                                 step: Double = 0.005) -> AttractorSystem {
        AttractorSystem(.halvorsen(a: a), step: step, start: start)
    }

    /// Dadras's system: a four-winged shape with a central twist.
    public static func dadras(a: Double = 3, b: Double = 2.7, c: Double = 1.7, d: Double = 2, e: Double = 9,
                              start: Vector3 = Vector3(1.1, 2.1, -2), step: Double = 0.01) -> AttractorSystem {
        AttractorSystem(.dadras(a: a, b: b, c: c, d: d, e: e), step: step, start: start)
    }

    /// Chen's system: a double-scroll relative of Lorenz, more tightly wound.
    public static func chen(alpha: Double = 5, beta: Double = -10, delta: Double = -0.38,
                            start: Vector3 = Vector3(-0.1, 0.5, -0.6), step: Double = 0.005) -> AttractorSystem {
        AttractorSystem(.chen(alpha: alpha, beta: beta, delta: delta), step: step, start: start)
    }

    /// The Wang-Sun four-wing system: four lobes meeting at the center.
    public static func fourWing(a: Double = 0.2, b: Double = 0.01, c: Double = -0.4,
                                start: Vector3 = Vector3(1, -1, 1), step: Double = 0.05) -> AttractorSystem {
        AttractorSystem(.fourWing(a: a, b: b, c: c), step: step, start: start)
    }

    /// The same system as a CPU `StrangeAttractor`: the one-orbit form, for a static
    /// plot, a measurement, or anything a flow's GPU state cannot be read back for.
    public var attractor: StrangeAttractor {
        switch kind {
        case let .lorenz(sigma, rho, beta):
            return .lorenz(sigma: sigma, rho: rho, beta: beta, start: start, step: step)
        case let .rossler(a, b, c):
            return .rossler(a: a, b: b, c: c, start: start, step: step)
        case let .aizawa(a, b, c, d, e, f):
            return .aizawa(a: a, b: b, c: c, d: d, e: e, f: f, start: start, step: step)
        case let .thomas(b):
            return .thomas(b: b, start: start, step: step)
        case let .halvorsen(a):
            return .halvorsen(a: a, start: start, step: step)
        case let .dadras(a, b, c, d, e):
            return .dadras(a: a, b: b, c: c, d: d, e: e, start: start, step: step)
        case let .chen(alpha, beta, delta):
            return .chen(alpha: alpha, beta: beta, delta: delta, start: start, step: step)
        case let .fourWing(a, b, c):
            return .fourWing(a: a, b: b, c: c, start: start, step: step)
        }
    }

    /// The kernel switch's case for this system. Kept in step with
    /// `ollin_attractor_field` by hand, the way the SDF leaf distances are.
    var shaderIndex: UInt32 {
        switch kind {
        case .lorenz:    return 0
        case .rossler:   return 1
        case .aizawa:    return 2
        case .thomas:    return 3
        case .halvorsen: return 4
        case .dadras:    return 5
        case .chen:      return 6
        case .fourWing:  return 7
        }
    }

    /// The system's constants, packed into the two parameter rows the kernel reads.
    var packedParameters: (SIMD4<Float>, SIMD4<Float>) {
        var a = SIMD4<Float>(repeating: 0), b = SIMD4<Float>(repeating: 0)
        switch kind {
        case let .lorenz(sigma, rho, beta):
            a = SIMD4<Float>(Float(sigma), Float(rho), Float(beta), 0)
        case let .rossler(x, y, z):
            a = SIMD4<Float>(Float(x), Float(y), Float(z), 0)
        case let .aizawa(p, q, r, s, t, u):
            a = SIMD4<Float>(Float(p), Float(q), Float(r), Float(s))
            b = SIMD4<Float>(Float(t), Float(u), 0, 0)
        case let .thomas(x):
            a = SIMD4<Float>(Float(x), 0, 0, 0)
        case let .halvorsen(x):
            a = SIMD4<Float>(Float(x), 0, 0, 0)
        case let .dadras(p, q, r, s, t):
            a = SIMD4<Float>(Float(p), Float(q), Float(r), Float(s))
            b = SIMD4<Float>(Float(t), 0, 0, 0)
        case let .chen(alpha, beta, delta):
            a = SIMD4<Float>(Float(alpha), Float(beta), Float(delta), 0)
        case let .fourWing(x, y, z):
            a = SIMD4<Float>(Float(x), Float(y), Float(z), 0)
        }
        return (a, b)
    }
}

/// A million particles riding a strange attractor: every one of them integrates the
/// same velocity field on the GPU, so instead of one orbit drawn as a still curve you
/// get the whole shape as moving material, streaming along itself forever.
///
/// A flow is 3D and rides the camera, like a `PointCloud`. Build it in `setup()`, then
/// step and draw it in `draw()`:
///
/// ```swift
/// var flow: AttractorFlow!
///
/// override func setup() {
///     flow = makeAttractorFlow(count: 1_000_000, .lorenz())
/// }
///
/// override func draw() {
///     background(.black)
///     blendMode(.add)
///     cameraShowcase(target: flow.center, radius: flow.extent * 3)
///     updateAttractorFlow(flow)
///     drawParticles(flow)
/// }
/// ```
///
/// Everything about the flow's placing and pace comes from the system itself: it is
/// measured once at build from a short CPU orbit of the same equations, so `center`,
/// `extent`, the colors' speed range, and the default pace all suit whatever the
/// system and its constants happen to be. Change `system` live and the flow re-measures
/// and carries on, which is what makes the constants worth putting on a knob.
///
/// Particles never die, so the picture is the attractor's own density: bright where the
/// orbit dwells, faint where it hurries. A particle that leaves the neighborhood
/// altogether (a wild set of constants can push one out) is dropped back into the middle
/// rather than flying off, so a stray can never streak the frame.
///
/// Like the other systems on this path, a step is a race between GPU threads only in
/// its ordering, not its arithmetic, so a flow is reproducible on one machine but is
/// not promised frame-exact across GPUs. There is no pixel snapshot of one.
@MainActor
public final class AttractorFlow {

    /// How many particles.
    public let count: Int

    /// Which system the particles ride. Settable live: the flow re-measures its
    /// placing, pace, and speed range for the new constants and keeps its particles,
    /// so dragging a constant morphs one shape into another.
    public var system: AttractorSystem {
        didSet { if system != oldValue { measure() } }
    }

    /// How fast the flow runs, as a multiple of the pace measured for the system (1,
    /// the default, crosses the attractor in about two seconds). The step itself never
    /// grows past the system's own: asking for more than the substep ceiling allows
    /// slows the flow down rather than integrating a system nobody chose.
    public var speed: Double = 1

    /// The splat diameter, in world units. `nil`, the default, derives one from the
    /// attractor's measured reach, so a system whose whole shape is a couple of units
    /// across and one that is fifty both open with legible dots; set it to take over.
    public var size: Double?

    /// The speed ramp: a particle's color is read from these stops by how fast it is
    /// moving, which is what shows the attractor's structure (the fast outer sweeps
    /// against the slow crowded core). One color is a flat color. Past eight stops the
    /// ramp is resampled to eight.
    ///
    /// The default stops shift hue and hold their brightness roughly level on purpose.
    /// Drawn additively, brightness already means *density*, so a ramp that also runs
    /// dark to light puts two different facts on the same channel and the picture
    /// muddles: a slow crowded region and a fast empty one come out the same.
    public var colors: [Color] = [Color(red: 0.42, green: 0.14, blue: 0.62),
                                  Color(red: 0.11, green: 0.45, blue: 0.85),
                                  Color(red: 0.15, green: 0.76, blue: 0.72),
                                  Color(red: 0.96, green: 0.72, blue: 0.28)]

    /// How much light one particle contributes, 0…1. Low by default because a million
    /// additive splats are a *density* plot: let them pile up and the attractor's own
    /// measure comes out as tone, where at full strength everything the orbit visits
    /// more than a few times reads as flat white.
    public var opacity: Double = 0.22

    /// The middle of the attractor, measured from a CPU orbit of the same system: what
    /// to point a camera at.
    public private(set) var center: Vector3 = .zero

    /// How far the attractor reaches from `center`, measured the same way: a camera
    /// radius of about three times this frames it. A percentile of the orbit rather
    /// than its outright maximum, so a system that takes rare long excursions still
    /// reports the size of the thing you are looking at.
    public private(set) var extent: Double = 1

    /// The most Runge-Kutta steps one frame may take. The ceiling is what keeps a hitch
    /// (or a wildly raised `speed`) from spending a whole frame integrating.
    public var maxSubsteps: Int = 64

    private let pingpong: PingPong<OllinPoint>
    private let kernel: ComputeKernel
    private var timePerSecond: Double = 1     // the measured pace, before `speed`
    private var speedLow: Float = 0           // ramp ends, in the system's own speed
    private var speedHigh: Float = 1

    /// Build `count` particles spread over the attractor itself (a settled CPU orbit,
    /// nudged off it so they are a million trajectories rather than one). `seed` makes
    /// that spread reproducible.
    public init(count: Int, system: AttractorSystem, seed: Int) {
        precondition(count > 0, "AttractorFlow needs a positive count")
        self.count = count
        self.system = system
        self.kernel = AttractorFlow.makeKernel()

        // One CPU orbit does double duty: it measures the attractor, and it *is* where
        // the particles start. Seeding on the shape rather than in a box around it is
        // the same call the CPU side makes when it throws the transient away with
        // `settle`, and it is what makes every system open looking like itself: how
        // long a scatter takes to fall onto the attractor is the system's contraction
        // rate, which runs from a fraction of a second (Lorenz) to a minute of watching
        // nothing (Aizawa, whose phase volume barely contracts at all).
        let sample = AttractorFlow.survey(system, points: min(max(count, 4000), 120_000))
        self.center = sample.center
        self.extent = sample.extent
        self.timePerSecond = sample.timePerSecond
        self.speedLow = sample.speedLow
        self.speedHigh = sample.speedHigh

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        var seeds: [OllinPoint] = []
        seeds.reserveCapacity(count)
        let path = sample.path
        // Nudged off the orbit, which is doing more than spreading the duplicates: on
        // the orbit exactly, every particle rides the *same* trajectory forever and the
        // picture can only ever be that one curve with dots sliding along it. Off it by
        // a hair, chaos separates them within a few laps into a million trajectories
        // filling the attractor's own measure, which is the whole point of running this
        // many at once.
        let jitter = max(sample.extent * 0.01, .leastNormalMagnitude)
        for _ in 0..<count {
            let base = path[Int.random(in: 0..<path.count, using: &rng)]
            var point = OllinPoint()
            point.position = SIMD4<Float>(
                Float(base.x + Double.random(in: -jitter..<jitter, using: &rng)),
                Float(base.y + Double.random(in: -jitter..<jitter, using: &rng)),
                Float(base.z + Double.random(in: -jitter..<jitter, using: &rng)), 1)
            point.color = SIMD4<Float>(1, 1, 1, 1)
            point.size = Float(sample.extent / 150)
            seeds.append(point)
        }
        self.pingpong = PingPong(seeds)
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinPoint> { pingpong.read }

    /// Record one step. Called by `Sketch.updateAttractorFlow`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        let read = pingpong.read, write = pingpong.write
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count,
            buffers: [read, write], params: paramBytes(frameDt: frameDt)))
        pingpong.advance()
    }

    // MARK: Measuring the system

    private struct Survey {
        var center: Vector3, extent: Double, timePerSecond: Double
        var speedLow: Float, speedHigh: Float
        var path: [Vector3]
    }

    private func measure() {
        let shape = AttractorFlow.survey(system, points: 4000)
        center = shape.center
        extent = shape.extent
        timePerSecond = shape.timePerSecond
        speedLow = shape.speedLow
        speedHigh = shape.speedHigh
    }

    /// Run a CPU orbit of the same system and read off everything the GPU side needs to
    /// place, pace, and color itself. The two sides integrate the same equations with
    /// the same method, so what the orbit measures is what the particles will do.
    private static func survey(_ system: AttractorSystem, points: Int) -> Survey {
        let attractor = system.attractor
        // Settled first: the transient is neither part of the shape nor where a
        // particle should start.
        let sampled = attractor.orbit(count: max(points, 2), settle: 2000)
        // A set of constants nobody checked has no attractor to find, and the orbit runs
        // off to infinity: what comes back is part real numbers and part not. Every
        // figure below is measured from these points, so one value that is not a number
        // spreads to all of them, and a flow built on it seeds every particle at nowhere.
        // Keep what stayed finite and say so plainly when there is nothing left.
        let path = sampled.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        guard path.count >= 2 else {
            return Survey(center: .zero, extent: 1, timePerSecond: 1,
                          speedLow: 0, speedHigh: 1, path: [.zero, .zero])
        }
        var xs = [Double](), ys = [Double](), zs = [Double]()
        var speeds: [Double] = []
        speeds.reserveCapacity(path.count)
        for p in path {
            xs.append(p.x); ys.append(p.y); zs.append(p.z)
            let d = attractor.derivative(p)
            let speed = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
            if speed.isFinite { speeds.append(speed) }
        }
        if speeds.isEmpty { speeds = [1] }
        // The reach is read off percentiles, not the extremes. Several of these systems
        // take rare long excursions (the four-wing's outlying arcs reach nearly twice as
        // far as its body), so the outright maximum keeps growing with how long you
        // watch: measured over 120,000 points its reach is 2.0, over 400,000 it is 3.5.
        // A percentile settles, which is what lets the framing, the dot size, and the
        // stray test all mean the same thing run to run.
        xs.sort(); ys.sort(); zs.sort()
        let span = { (v: [Double]) -> (Double, Double) in
            (v[v.count / 200], v[min(v.count - 1, (v.count * 199) / 200)])
        }
        let (x0, x1) = span(xs), (y0, y1) = span(ys), (z0, z1) = span(zs)
        let center = Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        let extent = max(max(x1 - x0, y1 - y0), z1 - z0) / 2
        speeds.sort()
        // The ends of the ramp are percentiles, not the extremes: one excursion at a
        // hundred times the usual speed would otherwise flatten the whole ramp onto
        // its first stop (the same reason the robust bounds exist in sonification).
        let lowSpeed = speeds[speeds.count / 20]
        let highSpeed = speeds[min(speeds.count - 1, (speeds.count * 19) / 20)]
        // Pace: at `speed` 1 a particle covers the attractor's own width once a second,
        // which is a statement about the picture rather than about the equations, so it
        // reads the same whether the system's natural time runs fast or slow (crossing
        // takes 0.48 of Lorenz's time units and 12.3 of the four-wing's). Derived rather
        // than tabulated, so a system nobody tuned still opens at a sensible pace.
        let mean = speeds.reduce(0, +) / Double(speeds.count)
        let crossing = mean > 1e-9 ? (2 * max(extent, 1e-6)) / mean : 1
        return Survey(center: center, extent: max(extent, 1e-6),
                      timePerSecond: max(crossing, 1e-6),
                      speedLow: Float(lowSpeed), speedHigh: Float(max(highSpeed, lowSpeed + 1e-6)),
                      path: path)
    }

    // MARK: Packing

    private func paramBytes(frameDt: Double) -> [UInt8] {
        // A hitch must not jump the flow forward, so the frame is capped the way the
        // other particle systems cap theirs.
        let dt = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        let advance = timePerSecond * max(speed, 0) * dt
        let ceiling = max(1, maxSubsteps)
        // Never a step larger than the system was published at: past that the
        // integrator is solving something else. When the ceiling binds, the flow runs
        // slower than asked rather than coarser.
        let wanted = system.step > 0 ? Int((advance / system.step).rounded(.up)) : 1
        let substeps = min(ceiling, max(1, wanted))
        let step = min(system.step, advance / Double(substeps))

        let (kA, kB) = system.packedParameters
        var p = OllinAttractorParams()
        p.kA = kA
        p.kB = kB
        p.seed = SIMD4<Float>(Float(center.x), Float(center.y), Float(center.z), Float(extent))
        p.step = Float(max(step, 0))
        // Generous: an orbit legitimately swings well past the box a flow seeds in, so
        // this catches what is leaving for good, not what is merely out wide.
        p.escapeRadius = Float(extent * 12)
        p.speedLow = speedLow
        p.speedHigh = speedHigh
        // A dot about a pixel across when the attractor is framed by a camera at a few
        // times its reach, which is what `cameraShowcase(radius: extent * 3)` gives.
        p.size = Float(max(size ?? extent / 150, 0))
        p.system = system.shaderIndex
        p.substeps = UInt32(substeps)

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

    /// The speed ramp as at most eight stops. More than eight are resampled evenly
    /// along the colors as given, so any palette works and none is refused.
    private func rampStops() -> [SIMD4<Float>] {
        let alpha = Float(min(max(opacity, 0), 1))
        let source = colors.isEmpty ? [Color.white] : colors
        let stops: [SIMD4<Float>]
        if source.count <= 8 {
            stops = source.map(\.simd4)
        } else {
            stops = (0..<8).map { i in
                let t = Double(i) / 7 * Double(source.count - 1)
                let a = min(Int(t), source.count - 1)
                let b = min(a + 1, source.count - 1)
                return Color.mix(source[a], source[b], t - Double(a)).simd4
            }
        }
        // `opacity` scales whatever alpha the colors carry, so a stop that was already
        // translucent stays relatively fainter.
        return stops.map { SIMD4<Float>($0.x, $0.y, $0.z, $0.w * alpha) }
    }

    // MARK: The kernel

    /// The integration step: every particle advances the same velocity field with the
    /// shared fourth-order Runge-Kutta macro, reads no other particle (which is what
    /// lets a million of them run without any neighbor search), and takes its color
    /// from how fast it ended up moving.
    private static func makeKernel() -> ComputeKernel {
        let source = """
        // Which system, by the index `AttractorSystem.shaderIndex` hands over. Kept in
        // step with that switch by hand; a new system goes in both.
        static inline float3 ollin_attractor_field(uint sys, float3 p, float4 kA, float4 kB) {
            switch (sys) {
                case 0: return ollin_lorenz(p, kA.x, kA.y, kA.z);
                case 1: return ollin_rossler(p, kA.x, kA.y, kA.z);
                case 2: return ollin_aizawa(p, kA.x, kA.y, kA.z, kA.w, kB.x, kB.y);
                case 3: return ollin_thomas(p, kA.x);
                case 4: return ollin_halvorsen(p, kA.x);
                case 5: return ollin_dadras(p, kA.x, kA.y, kA.z, kA.w, kB.x);
                case 6: return ollin_chen(p, kA.x, kA.y, kA.z);
                default: return ollin_four_wing(p, kA.x, kA.y, kA.z);
            }
        }

        kernel void ollin_attractor_step(
            device const OllinPoint *inBuf  [[buffer(0)]],
            device OllinPoint       *outBuf [[buffer(1)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinAttractorParams &a [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinPoint p = inBuf[id];
            float3 s = p.position.xyz;

            for (uint i = 0; i < a.substeps; ++i) {
                OLLIN_RK4_STEP(s, a.step, ollin_attractor_field(a.system, _p, a.kA, a.kB));
            }

            // A particle that has left for good goes back in the box rather than
            // streaking off. Checked after the steps and before the write, so the
            // buffer never holds a position the splat shader would choke on.
            float3 off = s - a.seed.xyz;
            if (!all(isfinite(s)) || dot(off, off) > a.escapeRadius * a.escapeRadius) {
                float3 r = hash33(float3(float(id) + 0.5, float(u.frameCount) + 0.5, 7.13));
                s = a.seed.xyz + (r * 2.0 - 1.0) * a.seed.w;
            }

            // Color by speed: the ramp's ends are the system's own typical slow and
            // fast, so the same stops read the same way whatever it is running.
            float3 v = ollin_attractor_field(a.system, s, a.kA, a.kB);
            float t = saturate((length(v) - a.speedLow) / max(a.speedHigh - a.speedLow, 1e-6));
            float f = t * float(max(a.stopCount, 1u) - 1u);
            uint lo = min(uint(f), max(a.stopCount, 1u) - 1u);
            uint hi = min(lo + 1u, max(a.stopCount, 1u) - 1u);
            float4 color = mix(a.stops[lo], a.stops[hi], f - float(lo));

            p.position = float4(s, 1.0);
            p.color = color;
            p.size = a.size;
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_attractor_step", source)
    }
}
