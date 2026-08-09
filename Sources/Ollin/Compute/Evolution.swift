import Foundation
import simd
import COllinShaders   // OllinParticle, OllinEvolutionParams

/// A population that gets better at something, on the GPU: tens of thousands of
/// individuals fly a path written in their own genome, are scored on how close they
/// came to a target, and are replaced by the children of whoever did best. Watch it
/// for a minute and the spray narrows into a route.
///
/// A genome is a short list of steering impulses, played back over the trial in order,
/// so the genome *is* a plan for a journey and the flight is what that plan turns out
/// to be worth. Nothing about an individual is decided by a fitness function you write:
/// you place a start, a target, and whatever walls are in the way, and selection finds
/// its own way around them.
///
/// Build it in `setup()`, then step and draw it in `draw()`:
///
/// ```swift
/// var run: Evolution!
///
/// override func setup() {
///     run = evolution(count: 30_000, genes: 32,
///                     from: Vector2(540, 980), to: Vector2(540, 120))
///     run.obstacles = [Rectangle(x: 180, y: 520, width: 720, height: 40)]
/// }
///
/// override func draw() {
///     background(Color.black.withAlpha(0.08))
///     blendMode(.add)
///     updateEvolution(run)
///     drawParticles(run)
/// }
/// ```
///
/// Everything about the pace comes from the distance the trial has to cover: the top
/// speed crosses it in about two seconds, the trial runs long enough to go the long way
/// round, and one gene pushes hard enough to reach that speed in a quarter of a trial.
/// So a sketch names a population, a genome length, and two points, and nothing else.
/// Because those figures are re-derived every frame, dragging the target re-paces the
/// whole run rather than leaving it tuned for where the target used to be.
///
/// Selection is by tournament: each parent is the best of `tournament` individuals
/// picked at random. That is the one selection method needing no total, no sort, and no
/// normalizing, because it only ever *compares* two scores, which is what lets a whole
/// generation be bred in one pass with every child working alone. It also means the
/// scale of a score never matters, only its order.
///
/// Like the other systems on this path, a run is reproducible on one machine but is not
/// promised frame-exact across GPUs: a hair of difference in one flight changes which
/// individual wins a tournament, and from there the two populations part company. There
/// is no pixel snapshot of one.
@MainActor
public final class Evolution {

    /// How many individuals in the population.
    public let count: Int

    /// How many steering impulses a genome holds. Fewer genes make a smoother, coarser
    /// path that evolution finds sooner; more give finer control over a longer search.
    public let genes: Int

    /// Where every trial begins (canvas points).
    public var start: Vector2

    /// The point the population is selected for reaching (canvas points). Move it and
    /// the pace, the scores, and the colors all re-derive around the new distance.
    public var target: Vector2

    /// How close counts as arrived (canvas points).
    public var targetRadius: Double = 30

    /// Walls a flight is stopped by. An individual that touches one is finished, and
    /// keeps a tenth of the score it had reached. Up to eight; past that the extras are
    /// ignored with a note.
    public var obstacles: [Rectangle] = []

    /// Top speed an individual may travel (points per second). `nil`, the default,
    /// crosses the distance to the target in about two seconds, so a run over a wide
    /// canvas and one over a narrow one both open at a watchable pace.
    public var maxSpeed: Double?

    /// How long one generation flies for (seconds). `nil`, the default, is long enough
    /// to cover the distance at top speed with room to go the long way round a wall.
    public var trialDuration: Double?

    /// What one gene is worth (points per second squared). `nil`, the default, is
    /// enough to reach top speed in a quarter of a trial, so a genome's early genes
    /// choose a direction and its later ones correct it.
    public var thrust: Double?

    /// How many individuals a parent is picked as the best of. Larger is stronger
    /// selection: the population converges sooner and explores less.
    ///
    /// This is also what keeps the best genome alive without any explicit elitism.
    /// Every child draws `2 * tournament` rivals, so across a whole generation the best
    /// individual is passed over only about `e^(-2 * tournament)` of the time, which at
    /// the default is three generations in ten thousand.
    public var tournament: Int = 4

    /// The chance a gene is nudged as it is copied into a child. The published range
    /// for a run scored by a measure is a few percent: too little and the population
    /// converges on the first decent route it finds, too much and selection stops
    /// meaning anything because a good genome cannot survive being copied.
    public var mutationRate: Double = 0.04

    /// How far such a nudge may reach. Genes live in -1…1, and a nudge adds a random
    /// amount within this of what the gene already held rather than replacing it, so a
    /// mutated path is a bent version of its parent's rather than a new random one.
    public var mutationAmount: Double = 0.35

    /// The score ramp: an individual is colored by how far along the way to the target
    /// it has got, so a leading flight is legible against the crowd. One color is a
    /// flat color. Past four stops the ramp is resampled to four.
    ///
    /// The default stops shift hue and hold their brightness roughly level, for the
    /// same reason the attractor flow's do. Drawn additively, brightness already means
    /// *how many flights came this way*, and a whole population leaves at one point, so
    /// a ramp running dark to light would report the launch crowd as the leaders.
    public var colors: [Color] = [Color(red: 0.62, green: 0.34, blue: 0.95),
                                  Color(red: 0.25, green: 0.60, blue: 0.95),
                                  Color(red: 0.30, green: 0.72, blue: 0.55),
                                  Color(red: 0.99, green: 0.62, blue: 0.25)]

    /// How much light one individual contributes, 0…1. Low by default: drawn
    /// additively, tens of thousands of dots are a density plot, and the crowding is
    /// most of what a generation has to say.
    public var opacity: Double = 0.22

    /// The dot diameter (points).
    public var size: Double = 2.2

    /// How many generations have been bred so far. The first trial is generation 0.
    public private(set) var generation: Int = 0

    /// How far through the current trial, 0…1.
    public var progress: Double { min(elapsed / resolvedTrialDuration, 1) }

    /// What one finished generation managed, which is the only number a run gives back
    /// about itself: the picture is otherwise the readout.
    public struct Report: Sendable, Equatable {
        /// Which generation this describes.
        public let generation: Int
        /// The best score anyone reached. A score under 1 is a near miss; anything over
        /// 2 arrived, and the more over, the sooner.
        public let best: Double
        /// The population's average score, which is what actually moves as a run
        /// improves: the best individual can be a fluke, the mean cannot.
        public let mean: Double
        /// The fraction of the population that reached the target, 0…1.
        public let arrived: Double
        /// How close the closest flight came (canvas points).
        public let closest: Double
    }

    /// Whether to measure each generation as it finishes. Off by default, because
    /// measuring means reading the whole population back from the GPU, which is cheap
    /// once every few seconds and not cheap every frame.
    public var measuresGenerations = false

    /// What the last finished generation managed, or `nil` before one has. Measured
    /// only when `measuresGenerations` is on, and taken without stalling the GPU, so it
    /// can be a frame stale: a summary, not a ledger.
    public private(set) var lastGeneration: Report?

    private let seed: UInt64
    private let pingpong: PingPong<OllinParticle>
    private let genePingpong: PingPong<SIMD2<Float>>
    private let stepKernel: ComputeKernel
    private let breedKernel: ComputeKernel
    private var elapsed: Double = 0
    private var notedObstacleLimit = false

    /// The most obstacles a run can carry.
    public static let maxObstacles = 8

    /// Build a population of `count` individuals, each carrying `genes` steering
    /// impulses, flying from `start` toward `target`. `seed` makes the opening
    /// generation reproducible.
    public init(count: Int, genes: Int, start: Vector2, target: Vector2, seed: UInt64) {
        precondition(count > 0, "Evolution needs a positive count")
        precondition(genes > 0, "Evolution needs at least one gene")
        self.count = count
        self.genes = genes
        self.start = start
        self.target = target
        self.seed = seed
        self.stepKernel = Evolution.makeStepKernel()
        self.breedKernel = Evolution.makeBreedKernel()

        var seeds: [OllinParticle] = []
        seeds.reserveCapacity(count)
        for _ in 0..<count {
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(start.x), Float(start.y)),
                velocity: .zero,
                color: SIMD4<Float>(1, 1, 1, 1),
                size: 2,
                life: 1,                            // flying
                seedA: .greatestFiniteMagnitude,    // closest approach so far
                seedB: 0))                          // what that closest approach scores
        }
        self.pingpong = PingPong(seeds)

        self.genePingpong = PingPong(Evolution.seedGenomes(count: count, genes: genes, seed: seed))
    }

    /// The opening generation, which is where a run either has something to select from
    /// or does not.
    ///
    /// Genes drawn independently at random make a *random walk*, whose steps cancel: a
    /// whole population of them mills around the start, every one of them equally bad,
    /// and selection has nothing to work with for a long time. So a genome opens as a
    /// smooth arc, a random heading with each gene a small turn from the one before, and
    /// generation 0 is already a spray of paths going somewhere different. Evolution's
    /// job is then to bend the good ones, which it can do in a handful of generations
    /// rather than a hundred.
    static func seedGenomes(count: Int, genes: Int, seed: UInt64) -> [SIMD2<Float>] {
        var rng = SplitMix64(seed: seed)
        var initial = [SIMD2<Float>]()
        initial.reserveCapacity(count * genes)
        for _ in 0..<count {
            var heading = Double.random(in: 0..<(2 * .pi), using: &rng)
            let curl = Double.random(in: -0.35..<0.35, using: &rng)
            for _ in 0..<genes {
                heading += curl + Double.random(in: -0.12..<0.12, using: &rng)
                let push = Double.random(in: 0.55..<1, using: &rng)
                initial.append(SIMD2<Float>(Float(cos(heading) * push),
                                            Float(sin(heading) * push)))
            }
        }
        return initial
    }

    /// The current population state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// The genomes, one run of `genes` impulses per individual. Read for tests and
    /// measurement; a sketch never needs it.
    var currentGenes: ComputeBuffer<SIMD2<Float>> { genePingpong.read }

    /// Record one frame: either another step of the current trial, or, when the trial
    /// is up, the breeding pass that makes the next generation. Called by
    /// `Sketch.updateEvolution`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        // A hitch must not fast-forward a trial, so the frame is capped the way the
        // other particle systems cap theirs.
        let dt = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        let particlesIn = pingpong.read, particlesOut = pingpong.write

        if elapsed >= resolvedTrialDuration {
            if measuresGenerations { lastGeneration = measure(particlesIn) }
            // Breeding both writes the children's genomes and stands the whole
            // population back at the start, so it ping-pongs both buffers at once.
            let genesIn = genePingpong.read, genesOut = genePingpong.write
            drawer.recordDispatch(RecordedDispatch(
                kernel: breedKernel, threadCount: count,
                buffers: [particlesIn, particlesOut, nil, nil, nil, nil, genesIn, genesOut],
                params: paramBytes(dt: dt)))
            pingpong.advance()
            genePingpong.advance()
            generation += 1
            elapsed = 0
            return
        }

        drawer.recordDispatch(RecordedDispatch(
            kernel: stepKernel, threadCount: count,
            buffers: [particlesIn, particlesOut, nil, nil, nil, nil, genePingpong.read],
            params: paramBytes(dt: dt)))
        pingpong.advance()
        elapsed += dt
    }

    /// Read a finished trial back and total it up. An individual that has not flown yet
    /// carries the sentinel its closest approach starts at, which is neither a distance
    /// anything stood at nor a number to report, so the summing skips it.
    private func measure(_ buffer: ComputeBuffer<OllinParticle>) -> Report? {
        guard let state = buffer.snapshot(), !state.isEmpty else { return nil }
        let sentinel = Double(Float.greatestFiniteMagnitude)
        var best = 0.0, total = 0.0, arrived = 0, closest = Double.infinity
        for p in state {
            let score = Double(p.seedB)
            if score.isFinite {
                best = max(best, score)
                total += score
                if score >= 2 { arrived += 1 }
            }
            let d = Double(p.seedA)
            if d.isFinite && d < sentinel { closest = min(closest, d) }
        }
        return Report(generation: generation, best: best,
                      mean: total / Double(state.count),
                      arrived: Double(arrived) / Double(state.count),
                      closest: closest.isFinite ? closest : spanToTarget)
    }

    // MARK: The derived pace

    /// The straight-line distance a trial has to cover. Floored, because a target
    /// standing exactly on the start would otherwise divide every derived figure by
    /// zero and leave the whole run measuring itself against nothing.
    var spanToTarget: Double { max(start.distance(to: target), 1e-6) }

    /// Top speed: cross the distance in about two seconds unless told otherwise.
    var resolvedMaxSpeed: Double { max(maxSpeed ?? spanToTarget / 2, 1e-6) }

    /// Trial length: long enough to fly the distance at top speed with a wide margin,
    /// which is what buys room to go the long way round a wall rather than only the
    /// direct way.
    var resolvedTrialDuration: Double {
        max(trialDuration ?? spanToTarget / resolvedMaxSpeed * 1.7, 1e-3)
    }

    /// One gene's push: enough to reach top speed in a quarter of a trial.
    var resolvedThrust: Double {
        max(thrust ?? resolvedMaxSpeed / (resolvedTrialDuration * 0.25), 0)
    }

    // MARK: Packing

    private func paramBytes(dt: Double) -> [UInt8] {
        var p = OllinEvolutionParams()
        p.start = SIMD2<Float>(Float(start.x), Float(start.y))
        p.target = SIMD2<Float>(Float(target.x), Float(target.y))
        p.targetRadius = Float(max(targetRadius, 0))
        p.spanToTarget = Float(spanToTarget)
        p.trialDuration = Float(resolvedTrialDuration)
        p.elapsed = Float(elapsed)
        p.thrust = Float(resolvedThrust)
        p.maxSpeed = Float(resolvedMaxSpeed)
        p.mutationRate = Float(min(max(mutationRate, 0), 1))
        p.mutationAmount = Float(max(mutationAmount, 0))
        p.dt = Float(dt)
        p.size = Float(max(size, 0))
        p.genes = UInt32(genes)
        p.tournament = UInt32(min(max(tournament, 1), 64))
        p.generation = UInt32(truncatingIfNeeded: generation)
        p.seed = UInt32(truncatingIfNeeded: seed)

        if obstacles.count > Evolution.maxObstacles && !notedObstacleLimit {
            notedObstacleLimit = true
            print("Ollin: Evolution carries at most \(Evolution.maxObstacles) obstacles; "
                  + "\(obstacles.count - Evolution.maxObstacles) more were left out.")
        }
        let walls = obstacles.prefix(Evolution.maxObstacles)
        p.obstacleCount = UInt32(walls.count)
        withUnsafeMutableBytes(of: &p.obstacles) { raw in
            let slots = raw.bindMemory(to: SIMD4<Float>.self)
            for (i, r) in walls.enumerated() {
                slots[i] = SIMD4<Float>(Float(r.x), Float(r.y), Float(r.width), Float(r.height))
            }
        }

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

    /// The score ramp as at most four stops, with `opacity` scaling whatever alpha the
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
                return Color.mix(source[a], source[b], t: t - Double(a)).simd4
            }
        }
        return stops.map { SIMD4<Float>($0.x, $0.y, $0.z, $0.w * alpha) }
    }

    // MARK: The kernels

    /// Shared between the two kernels: the wall test and the per-individual random
    /// stream. That stream is a pure function of who is asking, which generation it is,
    /// and the population's own seed, never a number handed in from the sketch's
    /// `random`, so adding a population cannot shift a sketch's other rolls and a run
    /// repeats from its seed alone.
    private static let preamble = """
    static inline uint ollin_evo_rand(thread uint &state) {
        state = state * 1664525u + 1013904223u;
        uint x = state;
        x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
        return x;
    }

    static inline float ollin_evo_unit(thread uint &state) {
        return float(ollin_evo_rand(state) >> 8) * (1.0 / 16777216.0);
    }

    static inline bool ollin_evo_hits(float2 p, constant OllinEvolutionParams &e) {
        for (uint i = 0; i < e.obstacleCount; ++i) {
            float4 r = e.obstacles[i];
            if (p.x >= r.x && p.x <= r.x + r.z && p.y >= r.y && p.y <= r.y + r.w) {
                return true;
            }
        }
        return false;
    }
    """

    /// The trial step: fly one frame along the live gene, then re-score.
    ///
    /// The score is the published shape for this problem: how close the flight came,
    /// sharpened so that gains near the target count for more than gains far from it, a
    /// tenth of it kept by anyone who hit a wall, and an arrival worth more than any
    /// near miss, by more the sooner it happened. Because selection only compares
    /// scores, none of that has to add up to anything in particular.
    private static func makeStepKernel() -> ComputeKernel {
        let source = preamble + """

        kernel void ollin_evolution_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const float2 *genes [[buffer(6)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinEvolutionParams &e [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle p = inBuf[id];

            if (p.life > 0.5) {
                // Which gene is steering right now: the genome is played back evenly
                // across the trial, so the same genome means the same journey whatever
                // the frame rate happens to be.
                float through = saturate(e.elapsed / max(e.trialDuration, 1e-6));
                uint g = min(uint(through * float(e.genes)), e.genes - 1u);
                float2 gene = genes[id * e.genes + g];

                p.velocity += gene * (e.thrust * e.dt);
                float speed = length(p.velocity);
                if (speed > e.maxSpeed) { p.velocity *= e.maxSpeed / speed; }
                p.position += p.velocity * e.dt;

                float d = distance(p.position, e.target);
                p.seedA = min(p.seedA, d);

                // Closest approach as a fraction of the way there, squared: near the
                // target a small gain is a large one, which is where a population needs
                // the pressure. Far from it every genome is roughly as bad as the next.
                float reached = saturate(1.0 - p.seedA / max(e.spanToTarget, 1e-6));
                p.seedB = reached * reached;

                if (ollin_evo_hits(p.position, e)) {
                    p.seedB *= 0.1;      // a crash keeps a tenth of what it had earned
                    p.life = 0.0;
                } else if (d <= e.targetRadius) {
                    // Any arrival beats any near miss, and an early one beats a late
                    // one, so a population that has found the target goes on to find
                    // the quick way to it.
                    p.seedB = 2.0 + saturate(1.0 - through);
                    p.life = 0.0;
                }
            }

            // Colored by how far along the way it has got, so the leaders read against
            // the crowd. A stopped flight keeps the color it stopped with.
            float t = saturate(1.0 - p.seedA / max(e.spanToTarget, 1e-6));
            float f = t * float(max(e.stopCount, 1u) - 1u);
            uint lo = min(uint(f), max(e.stopCount, 1u) - 1u);
            uint hi = min(lo + 1u, max(e.stopCount, 1u) - 1u);
            p.color = mix(e.stops[lo], e.stops[hi], f - float(lo));
            p.size = e.size;
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_evolution_step", source)
    }

    /// The breeding pass: every individual is replaced, in one go, by a child of two
    /// parents chosen by tournament.
    ///
    /// A child works entirely alone. It picks its own rivals, compares their scores,
    /// copies genes, and mutates, so a whole generation is bred in one dispatch with no
    /// ordering between threads and no atomics. That is what tournament selection buys:
    /// the wheel-of-fortune method every textbook teaches first needs the sum of the
    /// population's scores before it can pick anybody, and a sum is the one thing this
    /// pass would have to stop and agree on.
    private static func makeBreedKernel() -> ComputeKernel {
        let source = preamble + """

        // The best of `tournament` individuals drawn at random. Reads scores from the
        // finished trial, which no thread is writing, so a rival's score is settled.
        static inline uint ollin_evo_pick(device const OllinParticle *pop, uint count,
                                          uint rounds, thread uint &state) {
            uint best = ollin_evo_rand(state) % count;
            float bestScore = pop[best].seedB;
            for (uint i = 1; i < rounds; ++i) {
                uint other = ollin_evo_rand(state) % count;
                float score = pop[other].seedB;
                if (score > bestScore) { best = other; bestScore = score; }
            }
            return best;
        }

        kernel void ollin_evolution_breed(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const float2 *genesIn  [[buffer(6)]],
            device float2       *genesOut [[buffer(7)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinEvolutionParams &e [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            uint count = u.particleCount;
            if (id >= count) { return; }

            uint state = id * 747796405u + e.generation * 2891336453u + e.seed * 2654435761u + 1u;
            ollin_evo_rand(state);

            uint mum = ollin_evo_pick(inBuf, count, e.tournament, state);
            uint dad = ollin_evo_pick(inBuf, count, e.tournament, state);

            for (uint g = 0; g < e.genes; ++g) {
                // Gene by gene from one parent or the other with an even chance, which
                // mixes the two plans far more thoroughly than splitting them at a
                // single point does.
                float2 gene = (ollin_evo_unit(state) < 0.5)
                    ? genesIn[mum * e.genes + g]
                    : genesIn[dad * e.genes + g];
                if (ollin_evo_unit(state) < e.mutationRate) {
                    // A nudge, not a replacement: the child's path is a bent version of
                    // its parents' rather than a fresh random one.
                    float2 nudge = float2(ollin_evo_unit(state), ollin_evo_unit(state)) * 2.0 - 1.0;
                    gene = clamp(gene + nudge * e.mutationAmount, -1.0, 1.0);
                }
                genesOut[id * e.genes + g] = gene;
            }

            OllinParticle p = inBuf[id];
            p.position = e.start;
            p.velocity = float2(0.0);
            p.life = 1.0;
            p.seedA = FLT_MAX;
            p.seedB = 0.0;
            p.color = e.stops[0];
            p.size = e.size;
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_evolution_breed", source)
    }
}
