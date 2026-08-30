import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid, OllinSwarmChemistryParams

/// Swarm chemistry: every particle carries its own copy of the rule it moves by, and
/// on contact one copy overwrites the other. There is no generation boundary and no
/// score. A recipe spreads because the particles holding it keep meeting particles
/// holding something else and winning, which is a definition of fitness nobody had to
/// write down.
///
/// Written from Sayama's model: eight numbers per particle (how far it sees, how fast
/// it likes to go, how fast it can go, and the strengths of cohesion, alignment,
/// separation, random steering, and pace-keeping), with the evolutionary layer added
/// later, where recipes transmit between colliding particles with occasional
/// mutation and a `Competition` function decides which way the copy goes.
///
/// ```swift
/// var chem: SwarmChemistry!
/// override func setup() {
///     background(.black); noClear()
///     chem = makeSwarmChemistry(count: 4000, kinds: 6)
/// }
/// override func draw() {
///     background(Color.black.withAlpha(0.08))
///     updateSwarmChemistry(chem)
///     drawParticles(chem)
/// }
/// ```
///
/// This is the counterpart to `Evolution`, and the two answer different questions.
/// There, a generation flies, is scored against something the sketch asked for, and is
/// replaced all at once. Here nothing is asked for: a recipe is selected by whether it
/// can hold on to the particles it has, which is why it can go somewhere nobody aimed
/// it. Set `transmits` to false and the recipes freeze, leaving the plain mixture of
/// kinds the model started as.
@MainActor
public final class SwarmChemistry {
    /// One particle's rule: the eight numbers Sayama's model gives each particle, in
    /// the published units (lengths in points, speeds in points per step). A recipe is
    /// data worth passing around, so it prints and reads back as its eight values in
    /// the usual order.
    public struct Recipe: Equatable, Sendable {
        /// How far this particle sees (points). Capped at the sim's `perceptionLimit`.
        public var perception: Double
        /// The speed it settles back toward (points per step).
        public var normalSpeed: Double
        /// The fastest it may travel (points per step).
        public var maxSpeed: Double
        /// Strength of the pull toward the middle of what it can see.
        public var cohesion: Double
        /// Strength of the pull toward its neighbors' average heading.
        public var alignment: Double
        /// Strength of the shove away from whoever is closest.
        public var separation: Double
        /// Chance per step that it simply turns somewhere else.
        public var randomSteering: Double
        /// How insistently it returns to its normal speed.
        public var pace: Double

        public init(perception: Double, normalSpeed: Double, maxSpeed: Double,
                    cohesion: Double, alignment: Double, separation: Double,
                    randomSteering: Double, pace: Double) {
            self.perception = perception
            self.normalSpeed = normalSpeed
            self.maxSpeed = maxSpeed
            self.cohesion = cohesion
            self.alignment = alignment
            self.separation = separation
            self.randomSteering = randomSteering
            self.pace = pace
        }

        /// The eight values in the published order, which is how recipes are written
        /// down and shared.
        public var values: [Double] {
            [perception, normalSpeed, maxSpeed, cohesion, alignment, separation,
             randomSteering, pace]
        }

        /// Read a recipe back from its eight values. Anything shorter is refused.
        public init?(_ values: [Double]) {
            guard values.count >= 8 else { return nil }
            self.init(perception: values[0], normalSpeed: values[1], maxSpeed: values[2],
                      cohesion: values[3], alignment: values[4], separation: values[5],
                      randomSteering: values[6], pace: values[7])
        }

        /// The range each value is drawn and mutated within, from the published model.
        /// Mutation nudges within these and clamps, so a recipe cannot wander into
        /// numbers the model was never described at.
        public static let ranges: [ClosedRange<Double>] = [
            0...300,    // perception, points
            0...20,     // normal speed, points per step
            0...40,     // max speed, points per step
            0...1,      // cohesion
            0...1,      // alignment
            0...100,    // separation
            0...0.5,    // random steering
            0...1,      // pace
        ]

        /// A recipe drawn evenly from the published ranges.
        public static func random(using rng: inout SplitMix64) -> Recipe {
            var v = [Double]()
            for r in ranges { v.append(Double.random(in: r, using: &rng)) }
            return Recipe(v)!
        }
    }

    /// Which of two particles in contact becomes the source of the copy. The published
    /// model varies this to keep the evolution from settling, and it is the one knob
    /// that decides what "doing well" even means here.
    public enum Competition: Int, Sendable, CaseIterable {
        /// The faster particle's recipe wins, which rewards recipes that keep moving.
        case faster = 0
        /// The slower one's wins, which rewards recipes that hold still together.
        case slower = 1
        /// Whichever is surrounded by more of its own line wins, which rewards
        /// whatever is already crowded and makes territory the thing at stake.
        case majority = 2

        var shaderIndex: UInt32 { UInt32(rawValue) }
    }

    /// The mean spacing of the world the published value ranges were chosen for: ten
    /// thousand particles over five thousand units square. Every length in a recipe is
    /// converted out of that world and into this one.
    static let publishedSpacing: Double = 50
    /// The published perception ceiling, as a multiple of that spacing. It is what
    /// fixes how many others a particle can see, which is the number the whole balance
    /// of cohesion against separation rests on.
    static let publishedReach: Double = 300 / publishedSpacing

    /// Particle count.
    public let count: Int
    /// How many distinct recipes the world opened with.
    public let kinds: Int
    /// The mean distance between particles in this world, `√(area / count)`. Every
    /// derived figure below comes from it.
    public let spacing: Double
    /// This world's spacing over the published one's. Recipes are stored in published
    /// units and converted by this, so a recipe written down anywhere means the same
    /// behavior here whatever the canvas size and particle count.
    public let lengthScale: Double
    /// The largest perception any recipe can reach with (points), which is also the
    /// neighbor search's cell size. Derived, so that a particle sees about as many
    /// others as one in the published world did.
    public let perceptionLimit: Double
    /// The recipes the world opened with, one per line, in published units. Everything
    /// alive later is one of these or a mutated descendant of one.
    public let openingRecipes: [Recipe]

    /// Whether recipes copy on contact at all. False freezes every recipe, leaving the
    /// plain mixture of kinds, which is the model before the evolutionary layer.
    public var transmits: Bool = true
    /// Who wins a contact.
    public var competition: Competition = .majority
    /// Chance that a recipe is mutated as it is copied.
    ///
    /// Much lower than a generational algorithm's, and it has to be: there are no
    /// generations here, so this is a chance *per contact*, and a particle in a crowd
    /// makes contact a few times a second. At the rate `Evolution` uses, a recipe would
    /// take dozens of nudges within one takeover and arrive as noise, which is the plain
    /// even gas the model turns into when this is set too high.
    public var mutationRate: Double = 0.01
    /// How far one mutated value may move, as a fraction of its own range.
    public var mutationAmount: Double = 0.08
    /// How close two particles must come to count as a contact (points). Derived from
    /// the spacing, so a contact stays a meeting rather than a permanent condition.
    public var contactRadius: Double
    /// Model steps per second. The model is discrete, and its published units are per
    /// step, so this is what makes a shared recipe mean the same thing whatever the
    /// frame rate. At 60 it is one step per frame on a 60 Hz display.
    public var stepRate: Double = 60
    /// Dot diameter, points.
    public var size: Double
    /// How much light one particle contributes, 0…1.
    public var opacity: Double = 0.9

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private let recipes: PingPong<Float>
    private let kernel: ComputeKernel
    private let seed: Int
    private var stepCount: UInt32 = 0
    private var stepDebt: Double = 0

    /// Twelve floats per particle: the eight values, the lineage, then padding to a
    /// whole number of four-float rows.
    static let recipeStride = 12

    /// Build `count` particles over `bounds` holding `kinds` distinct random recipes,
    /// each recipe given to an equal share of the population.
    ///
    /// The share is the design decision. One random recipe per particle would give
    /// every particle a rule nobody else has, and the structures this model is known
    /// for are made of many particles agreeing, so there would be nothing to see and
    /// nothing to spread. A handful of recipes each held in quantity is the state the
    /// model was described in, and it is what makes the first contest visible.
    public init(count: Int, bounds: Rectangle, kinds: Int, size: Double, seed: Int) {
        precondition(count > 0, "SwarmChemistry needs a positive count")
        precondition(kinds > 0, "SwarmChemistry needs at least one kind")
        self.count = count
        self.kinds = kinds
        self.size = size
        self.seed = seed

        // Everything with a length in it comes from how far apart these particles
        // actually are, rather than from a number anyone typed.
        let area = max(bounds.width * bounds.height, 1)
        self.spacing = (area / Double(count)).squareRoot()
        self.lengthScale = spacing / SwarmChemistry.publishedSpacing
        self.perceptionLimit = SwarmChemistry.publishedReach * spacing
        // A fifth of the spacing: close enough that touching is an event rather than a
        // standing state, which is what keeps a recipe from changing hands every step.
        self.contactRadius = spacing * 0.2
        self.hash = SpatialHash(bounds: bounds, cellSize: perceptionLimit, count: count)

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        var opening: [Recipe] = []
        for _ in 0..<kinds { opening.append(Recipe.random(using: &rng)) }
        self.openingRecipes = opening

        let origin = hash.origin, world = hash.worldSize
        var seeds: [OllinParticle] = []
        var genes = [Float](repeating: 0, count: count * SwarmChemistry.recipeStride)
        seeds.reserveCapacity(count)
        for i in 0..<count {
            let kind = i % kinds
            let r = opening[kind]
            let px = origin.x + Double.random(in: 0..<world.x, using: &rng)
            let py = origin.y + Double.random(in: 0..<world.y, using: &rng)
            let heading = Double.random(in: 0..<(2 * .pi), using: &rng)
            let speed = r.normalSpeed * lengthScale   // published units into this world's
            let c = SwarmChemistry.color(of: r)
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(px), Float(py)),
                velocity: SIMD2<Float>(Float(cos(heading) * speed), Float(sin(heading) * speed)),
                color: SIMD4<Float>(Float(c.red), Float(c.green), Float(c.blue), 1),
                size: Float(size), life: 1,
                seedA: Float(heading),   // a stopped particle still faces somewhere
                seedB: 0))               // neighbors of my own line, as of the last step
            SwarmChemistry.write(r, lineage: kind, into: &genes, at: i)
        }
        self.pingpong = PingPong(seeds)
        self.recipes = PingPong(genes)
        self.kernel = SwarmChemistry.makeKernel()
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Every particle's recipe as it stands. Valid once the GPU has caught up, so it
    /// is for inspection and tests rather than for reading every frame.
    public func snapshotRecipes() -> [Recipe] {
        guard let flat = recipes.read.snapshot() else { return [] }
        return (0..<count).compactMap { i in
            let base = i * SwarmChemistry.recipeStride
            return Recipe((0..<8).map { Double(flat[base + $0]) })
        }
    }

    /// Which line each particle belongs to: the opening recipe it descends from.
    /// Mutation stays inside its line, so this is what `Competition.majority` counts
    /// and what a takeover is a takeover *of*.
    public func snapshotLineages() -> [Int] {
        guard let flat = recipes.read.snapshot() else { return [] }
        return (0..<count).map { Int(flat[$0 * SwarmChemistry.recipeStride + 8]) }
    }

    /// How many particles each opening line still holds, in line order. This is the
    /// scoreboard the model never keeps for itself.
    public func snapshotLineageCounts() -> [Int] {
        var counts = [Int](repeating: 0, count: kinds)
        for line in snapshotLineages() where line >= 0 && line < kinds { counts[line] += 1 }
        return counts
    }

    /// The published visualization: cohesion, alignment and separation as red, green
    /// and blue, each against its own range, so two particles that move alike look
    /// alike and a mutation shows as a shift in shade rather than a new color.
    static func color(of r: Recipe) -> Color {
        let ranges = Recipe.ranges
        func norm(_ v: Double, _ i: Int) -> Double {
            let range = ranges[i]
            let span = range.upperBound - range.lowerBound
            return span > 0 ? min(max((v - range.lowerBound) / span, 0), 1) : 0
        }
        // Lifted off the floor so a recipe with three weak forces is still visible.
        return Color(red: 0.15 + 0.85 * norm(r.cohesion, 3),
                     green: 0.15 + 0.85 * norm(r.alignment, 4),
                     blue: 0.15 + 0.85 * norm(r.separation, 5))
    }

    static func write(_ r: Recipe, lineage: Int, into buffer: inout [Float], at index: Int) {
        let base = index * recipeStride
        let v = r.values
        for k in 0..<8 { buffer[base + k] = Float(v[k]) }
        buffer[base + 8] = Float(lineage)
        buffer[base + 9] = 0
        buffer[base + 10] = 0
        buffer[base + 11] = 0
    }

    /// Record one frame: as many model steps as the frame is worth, each one a fresh
    /// neighbor sort followed by the kinetic-and-transmission kernel. Called by
    /// `Sketch.updateSwarmChemistry`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        let frame = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        // Whole steps only, with the remainder banked, so a display that is not 60 Hz
        // still runs the model at the rate it was described at instead of drifting.
        stepDebt += frame * max(stepRate, 0)
        let steps = min(Int(stepDebt), 4)
        stepDebt -= Double(steps)
        guard steps > 0 else { return }
        for _ in 0..<steps {
            let read = pingpong.read, write = pingpong.write
            hash.recordBuild(into: drawer, positions: read)
            drawer.recordDispatch(RecordedDispatch(
                kernel: kernel, threadCount: count,
                buffers: [read, write, hash.sortedIndices, hash.cellStart, hash.cellCount,
                          hash.gridBuffer, recipes.read, recipes.write],
                params: paramBytes()))
            pingpong.advance()
            recipes.advance()
            stepCount &+= 1
        }
    }

    private func paramBytes() -> [UInt8] {
        var p = OllinSwarmChemistryParams()
        p.dt = 1
        p.perceptionLimit = Float(perceptionLimit)
        p.contactRadius = Float(max(contactRadius, 0))
        p.mutationRate = Float(min(max(mutationRate, 0), 1))
        p.mutationAmount = Float(min(max(mutationAmount, 0), 1))
        p.competition = competition.shaderIndex
        p.transmits = transmits ? 1 : 0
        p.step = stepCount
        p.seed = UInt32(truncatingIfNeeded: seed)
        p.size = Float(max(size, 0))
        p.opacity = Float(min(max(opacity, 0), 1))
        p.lengthScale = Float(lengthScale)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: p) { bytes.append(contentsOf: $0) }
        return bytes
    }

    // MARK: The kernel

    /// The kinetic step and the transmission, in one pass.
    ///
    /// The published rule is a gather already (a particle reads the middle and the
    /// average heading of what it can see), so the only thing that had to be decided
    /// is which way a contact copies. On one thread per particle the natural reading is
    /// the pull form: I look at everyone I am touching and, if any of them beats me,
    /// I take the best one's recipe. That is the same rule as the published push form
    /// with no atomics and no ordering between threads, and ties break on the lower
    /// index so a step does not depend on the order the neighbor sort happened to
    /// produce.
    ///
    /// `Competition.majority` compares how many of its own line each particle had
    /// around it as of the previous step, since a thread can count its own
    /// neighborhood but not a neighbor's. One step is 1/60 of a second, over which a
    /// neighborhood barely changes.
    private static func makeKernel() -> ComputeKernel {
        let source = """
        // The published ranges, which are the model's own definition of what a value
        // may be, and so where a mutation is clamped back to.
        constant float ollin_chem_lo[8] = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
        constant float ollin_chem_hi[8] = { 300.0, 20.0, 40.0, 1.0, 1.0, 100.0, 0.5, 1.0 };

        kernel void ollin_chem_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid [[buffer(5)]],
            device const float *genesIn  [[buffer(6)]],
            device float       *genesOut [[buffer(7)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinSwarmChemistryParams &S [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle p = inBuf[id];
            uint base = id * 12u;

            // Recipes are stored in the published units. Lengths and speeds convert by
            // the world's own scale, and separation by its square, because its units
            // are length² over step². Cohesion, alignment, the straying chance and
            // pace-keeping have no length in them and pass straight through.
            float sc = S.lengthScale;
            float perception = min(genesIn[base + 0u] * sc, S.perceptionLimit);
            float normalSpeed = genesIn[base + 1u] * sc;
            float maxSpeed    = genesIn[base + 2u] * sc;
            float c1 = genesIn[base + 3u];
            float c2 = genesIn[base + 4u];
            float c3 = genesIn[base + 5u] * sc * sc;
            float c4 = genesIn[base + 6u];
            float c5 = genesIn[base + 7u];
            float myLine = genesIn[base + 8u];

            float2 pos = p.position;
            float2 vel = p.velocity;
            float mySpeed = length(vel);

            float2 sumOffset = float2(0.0);   // neighbor positions, relative to me
            float2 sumVel = float2(0.0);
            float2 shove = float2(0.0);
            float neighbors = 0.0;
            float sameLine = 0.0;             // this step's count, for the next one

            // The best contact found so far, as (score, index). `winner` staying at my
            // own index means nobody beat me.
            uint winner = id;
            float winScore = -1e30;

            OLLIN_FOR_NEIGHBORS(pos, grid, sortedIdx, cellStart, cellCount, j)
                if (j == id) { continue; }
                float2 d = ollin_torus_delta(pos, inBuf[j].position, grid.worldSize);
                float dist = length(d);
                if (dist > perception || dist < 1e-6) { continue; }
                neighbors += 1.0;
                sumOffset += d;
                sumVel += inBuf[j].velocity;
                // Away from the neighbor, falling off with distance: the published
                // separation term.
                shove -= d / (dist * dist);
                float theirLine = genesIn[j * 12u + 8u];
                if (theirLine == myLine) { sameLine += 1.0; }

                if (S.transmits != 0u && dist <= S.contactRadius) {
                    float theirSpeed = length(inBuf[j].velocity);
                    float score;
                    bool beatsMe;
                    if (S.competition == 0u) {            // faster
                        score = theirSpeed;
                        beatsMe = theirSpeed > mySpeed;
                    } else if (S.competition == 1u) {     // slower
                        score = -theirSpeed;
                        beatsMe = theirSpeed < mySpeed;
                    } else {                              // majority
                        score = inBuf[j].seedB;
                        beatsMe = inBuf[j].seedB > p.seedB;
                    }
                    // Ties break on the lower index, so the winner never depends on the
                    // order the neighbor sort produced.
                    if (beatsMe && (score > winScore || (score == winScore && j < winner))) {
                        winScore = score;
                        winner = j;
                    }
                }
            OLLIN_END_NEIGHBORS

            // The kinetic rule. With nobody in range there is no middle to steer
            // toward, so the particle strays instead, which is what spreads a swarm
            // back out after it has flung someone clear.
            float2 accel = float2(0.0);
            float heading = mySpeed > 1e-4 ? atan2(vel.y, vel.x) : p.seedA;
            float roll = hash12(float2(float(id) + 0.5, float(S.step) + float(S.seed) * 0.618));
            if (neighbors > 0.0) {
                float2 center = sumOffset / neighbors;
                float2 avgVel = sumVel / neighbors;
                accel = c1 * center + c2 * (avgVel - vel) + c3 * shove;
            }
            // Steering randomly is one operation used twice: on its own when there is
            // nobody in range at all, and *added to* the other three with probability
            // c4 when there is. Added, not instead of: the published rule lists it
            // beside cohesion, alignment and separation rather than in place of them,
            // and taking their place is what turns a swarm into an even gas, since a
            // recipe with a third of its steps random then spends a third of them with
            // no cohesion at all. Steering toward a heading is the same
            // desired-minus-current the model borrowed from Boids, and the desired
            // speed is the only one a recipe carries: its own normal speed.
            if (neighbors <= 0.0 || roll < c4) {
                float a = hash12(float2(float(S.step) + 1.5, float(id) + float(S.seed) * 0.318)) * 6.2831853;
                accel += float2(cos(a), sin(a)) * normalSpeed - vel;
            }

            vel += accel * S.dt;
            // Pace-keeping: the pull back toward the speed this recipe likes, which is
            // what stops a swarm either freezing or running flat out.
            float sp = length(vel);
            if (sp > 1e-5) { vel += (c5 * (normalSpeed - sp) * S.dt) * (vel / sp); }
            sp = length(vel);
            if (sp > maxSpeed) { vel *= (maxSpeed / max(sp, 1e-6)); }

            pos += vel * S.dt;
            p.velocity = vel;
            if (length(vel) > 1e-4) { heading = atan2(vel.y, vel.x); }
            p.seedA = heading;
            p.seedB = sameLine;
            p.size = S.size;

            // Toroidal wrap, matching how the neighbor grid wraps.
            float2 rel = pos - grid.origin;
            rel = rel - grid.worldSize * floor(rel / grid.worldSize);
            p.position = grid.origin + rel;

            // Transmission. Whoever won the contact is the source; with nobody winning,
            // a particle simply keeps what it had.
            uint src = winner * 12u;
            float outValues[8];
            for (uint k = 0u; k < 8u; ++k) { outValues[k] = genesIn[src + k]; }
            float outLine = genesIn[src + 8u];

            if (S.transmits != 0u && winner != id) {
                float mutRoll = hash12(float2(float(id) + 2.5, float(S.step) + float(S.seed) * 0.771));
                if (mutRoll < S.mutationRate) {
                    for (uint k = 0u; k < 8u; ++k) {
                        float n = hash12(float2(float(id) * 8.0 + float(k) + 3.5,
                                                float(S.step) + float(S.seed) * 0.911)) * 2.0 - 1.0;
                        float span = ollin_chem_hi[k] - ollin_chem_lo[k];
                        // A nudge, not a fresh number, so a mutant is a variation on
                        // what it came from. The line it belongs to is unchanged.
                        outValues[k] = clamp(outValues[k] + n * S.mutationAmount * span,
                                             ollin_chem_lo[k], ollin_chem_hi[k]);
                    }
                }
            }

            for (uint k = 0u; k < 8u; ++k) { genesOut[base + k] = outValues[k]; }
            genesOut[base + 8u] = outLine;
            genesOut[base + 9u] = 0.0;
            genesOut[base + 10u] = 0.0;
            genesOut[base + 11u] = 0.0;

            // Cohesion, alignment and separation as red, green and blue: the published
            // way of showing a recipe, lifted off the floor so a weak one still reads.
            p.color = float4(0.15 + 0.85 * clamp(outValues[3] / 1.0, 0.0, 1.0),
                             0.15 + 0.85 * clamp(outValues[4] / 1.0, 0.0, 1.0),
                             0.15 + 0.85 * clamp(outValues[5] / 100.0, 0.0, 1.0),
                             S.opacity);
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_chem_step", source)
    }
}

extension SwarmChemistry.Competition: ParamOption {}
