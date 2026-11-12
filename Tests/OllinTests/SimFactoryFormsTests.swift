import Testing
import CoreGraphics
@testable import Ollin

/// Every GPU simulation factory on `Sketch` hands back what the type's own
/// initializer builds from the same arguments: `makeSwarm(count:...)` and
/// `Swarm(count:bounds:...)` are two spellings of one swarm, and the factory
/// adds only the two defaults a sketch can supply (its canvas for `bounds`,
/// its `variation` for `seed`).
///
/// A particle sim is read three ways: what the type lets a caller read back
/// about how it was built, the particles it was seeded with (which carry the
/// bounds, the seed, the colors, and the size), and the particles after five
/// steps on the GPU (which carry what only the step reads: a radius, a rule
/// matrix). The particle buffers are compared byte for byte, a stricter
/// reading than the picture drawn from them, and the three sims of a pair
/// step in one frame so each kernel is compiled once.
///
/// A sim that keeps its state out of reach (the slime mold's agents, a
/// field's texels, a sea's spectrum) is read the way `BareFormsTests` reads a
/// primitive: its picture after five frames, pixel for pixel.
///
/// The numbers are uneven on purpose (a box off the corner and unlike the
/// canvas, a canvas wider than tall, counts and radii that are nobody's
/// default), so a factory that handed two of them over in the wrong order, or
/// dropped one for its default, would build something else.
@Suite
@MainActor
struct SimFactoryFormsTests {

    /// One simulation behind the four things a test does with it, so sims of
    /// different types sit in one table.
    struct Rig {
        /// Everything the type lets a caller read back about how it was built.
        let configuration: [String]
        /// The particles as bytes, as seeded before the first step and as the
        /// GPU left them after it; nil where the type keeps its state out of
        /// reach and the picture is the only reading.
        let state: @MainActor () -> [UInt8]?
        /// One step.
        let step: @MainActor (Sketch) -> Void
        /// One draw.
        let draw: @MainActor (Sketch) -> Void
    }

    /// One simulation's two spellings, and a third built from one argument
    /// changed, which the readings must tell apart.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        let factory: @MainActor @Sendable (Sketch) -> Rig
        let core: @MainActor @Sendable (Sketch) -> Rig
        let other: @MainActor @Sendable (Sketch) -> Rig
        var testDescription: String { name }
    }

    nonisolated static let box = Rectangle(x: 3, y: 5, width: 57, height: 41)
    nonisolated static let warm = Color(red: 0.95, green: 0.6, blue: 0.2)
    nonisolated static let cool = Color(red: 0.2, green: 0.6, blue: 1)
    nonisolated static let rule = Sim.cyclic(states: 5, seed: 4)
    nonisolated static let water = Ocean(waveHeight: 3, seed: 6)

    /// The seed every bench pins its sketch to, so a factory left to its
    /// default seed has a known one to read.
    nonisolated static let variation = 4217

    /// Frames 0 through 4: five steps.
    nonisolated static let lastFrame = 4

    // MARK: Particle sims, read back from their buffers

    nonisolated static let particlePairs: [Pair] = [
        Pair(name: "particle life",
             factory: { rig($0.makeParticleLife(count: 120, kinds: 3, radius: 9, bounds: box, seed: 31)) },
             core: { _ in rig(ParticleLife(count: 120, kinds: 3, bounds: box, radius: 9, seed: 31)) },
             other: { _ in rig(ParticleLife(count: 120, kinds: 3, bounds: box, radius: 7, seed: 31)) }),
        Pair(name: "primordial particles",
             factory: { rig($0.makePrimordialParticles(count: 110, radius: 8, bounds: box, seed: 31)) },
             core: { _ in rig(PPS(count: 110, bounds: box, radius: 8, seed: 31)) },
             other: { _ in rig(PPS(count: 110, bounds: box, radius: 8, seed: 32)) }),
        Pair(name: "swarm",
             factory: { rig($0.makeSwarm(count: 90, perceptionRadius: 11, colors: [warm, cool], size: 3.5,
                                         bounds: box, seed: 31)) },
             core: { _ in rig(Swarm(count: 90, bounds: box, perceptionRadius: 11, colors: [warm, cool],
                                    size: 3.5, seed: 31)) },
             other: { _ in rig(Swarm(count: 90, bounds: box, perceptionRadius: 13, colors: [warm, cool],
                                     size: 3.5, seed: 31)) }),
        Pair(name: "particle lenia",
             factory: { rig($0.makeParticleLenia(count: 70, spacing: 2.5, bounds: box, seed: 31)) },
             core: { _ in rig(ParticleLenia(count: 70, bounds: box, spacing: 2.5, seed: 31)) },
             other: { _ in rig(ParticleLenia(count: 70, bounds: box, spacing: 3.5, seed: 31)) }),
        Pair(name: "swarm chemistry",
             factory: { rig($0.makeSwarmChemistry(count: 96, kinds: 4, size: 3.5, bounds: box, seed: 31)) },
             core: { _ in rig(SwarmChemistry(count: 96, bounds: box, kinds: 4, size: 3.5, seed: 31)) },
             other: { _ in rig(SwarmChemistry(count: 96, bounds: box, kinds: 3, size: 3.5, seed: 31)) }),
        Pair(name: "attractor flow",
             factory: { rig($0.makeAttractorFlow(count: 300, .lorenz(rho: 26.5), seed: 31)) },
             core: { _ in rig(AttractorFlow(count: 300, system: .lorenz(rho: 26.5), seed: 31)) },
             other: { _ in rig(AttractorFlow(count: 300, system: .lorenz(rho: 26.5), seed: 32)) }),
        Pair(name: "evolution",
             factory: { rig($0.makeEvolution(count: 60, genes: 7, from: Vector2(9, 40), to: Vector2(52, 11),
                                             seed: 31)) },
             core: { _ in rig(Evolution(count: 60, genes: 7, start: Vector2(9, 40), target: Vector2(52, 11),
                                        seed: 31)) },
             other: { _ in rig(Evolution(count: 60, genes: 7, start: Vector2(52, 11), target: Vector2(9, 40),
                                         seed: 31)) }),
        Pair(name: "particle fluid",
             factory: { rig($0.makeParticleFluid(count: 80, radius: 8, spacing: 3.5, bounds: box, seed: 31)) },
             core: { _ in rig(ParticleFluid(count: 80, bounds: box, radius: 8, spacing: 3.5, seed: 31)) },
             other: { _ in rig(ParticleFluid(count: 80, bounds: box, radius: 8, spacing: 3.5, seed: 32)) }),
        Pair(name: "soft bodies",
             factory: { rig($0.makeSoftBodies(bodies: 3, radius: 8, spacing: 3.5, bounds: box, seed: 31)) },
             core: { _ in rig(SoftBodies(bodies: 3, bounds: box, radius: 8, spacing: 3.5, seed: 31)) },
             other: { _ in rig(SoftBodies(bodies: 3, bounds: box, radius: 7, spacing: 3.5, seed: 31)) }),
    ]

    /// The factory's sim, the initializer's, and the third all step five
    /// frames side by side. The first two were seeded alike and end alike,
    /// byte for byte; the steps moved them; and the third ends somewhere else.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: particlePairs)
    func theFactoryBuildsTheSimItsInitializerBuilds(_ pair: Pair) throws {
        let bench = Bench { [pair.factory($0), pair.core($0), pair.other($0)] }
        let picture = pixels(of: try OllinApp.image(of: bench, frame: Self.lastFrame))
        try #require(bench.rigs.count == 3 && bench.opening.count == 3)
        let made = bench.rigs[0], built = bench.rigs[1], other = bench.rigs[2]

        #expect(made.configuration == built.configuration)
        let seeded = try #require(bench.opening[0])
        let builtSeeded = bench.opening[1]
        #expect(!seeded.isEmpty)
        #expect(seeded == builtSeeded, "the two were seeded apart")

        let after = try #require(made.state())
        let builtAfter = built.state()
        let otherAfter = try #require(other.state())
        #expect(after != seeded, "five steps moved nothing")
        #expect(after == builtAfter, "the two stepped apart")
        #expect(after != otherAfter, "a different argument stepped to the same particles")
        #expect(holdsInk(picture), "the factory's sim drew nothing")
    }

    // MARK: Left to their defaults

    nonisolated static let defaults: [Pair] = [
        Pair(name: "particle life",
             factory: { rig($0.makeParticleLife(count: 120, kinds: 3, radius: 9)) },
             core: { rig(ParticleLife(count: 120, kinds: 3, bounds: $0.bounds, radius: 9, seed: $0.variation)) },
             other: { rig(ParticleLife(count: 120, kinds: 3, bounds: $0.bounds, radius: 9,
                                       seed: $0.variation + 1)) }),
        Pair(name: "primordial particles",
             factory: { rig($0.makePrimordialParticles(count: 110, radius: 8)) },
             core: { rig(PPS(count: 110, bounds: $0.bounds, radius: 8, seed: $0.variation)) },
             other: { rig(PPS(count: 110, bounds: $0.bounds, radius: 8, seed: $0.variation + 1)) }),
        Pair(name: "swarm",
             factory: { rig($0.makeSwarm(count: 90, perceptionRadius: 11)) },
             core: { rig(Swarm(count: 90, bounds: $0.bounds, perceptionRadius: 11, colors: [], size: 2.0,
                               seed: $0.variation)) },
             other: { rig(Swarm(count: 90, bounds: $0.bounds, perceptionRadius: 11, colors: [], size: 2.0,
                                seed: $0.variation + 1)) }),
        Pair(name: "particle lenia",
             factory: { rig($0.makeParticleLenia(count: 70, spacing: 2.5)) },
             core: { rig(ParticleLenia(count: 70, bounds: $0.bounds, spacing: 2.5, seed: $0.variation)) },
             other: { rig(ParticleLenia(count: 70, bounds: $0.bounds, spacing: 2.5, seed: $0.variation + 1)) }),
        Pair(name: "swarm chemistry",
             factory: { rig($0.makeSwarmChemistry(count: 96)) },
             core: { rig(SwarmChemistry(count: 96, bounds: $0.bounds, kinds: 6, size: 2.6, seed: $0.variation)) },
             other: { rig(SwarmChemistry(count: 96, bounds: $0.bounds, kinds: 6, size: 2.6,
                                         seed: $0.variation + 1)) }),
        Pair(name: "attractor flow",
             factory: { rig($0.makeAttractorFlow(count: 300, .lorenz(rho: 26.5))) },
             core: { rig(AttractorFlow(count: 300, system: .lorenz(rho: 26.5), seed: $0.variation)) },
             other: { rig(AttractorFlow(count: 300, system: .lorenz(rho: 26.5), seed: $0.variation + 1)) }),
        Pair(name: "evolution",
             factory: { rig($0.makeEvolution(count: 60, genes: 7, from: Vector2(9, 40), to: Vector2(52, 11))) },
             core: { rig(Evolution(count: 60, genes: 7, start: Vector2(9, 40), target: Vector2(52, 11),
                                   seed: $0.variation)) },
             other: { rig(Evolution(count: 60, genes: 7, start: Vector2(9, 40), target: Vector2(52, 11),
                                    seed: $0.variation + 1)) }),
        Pair(name: "particle fluid",
             factory: { rig($0.makeParticleFluid(count: 80, radius: 8)) },
             core: { rig(ParticleFluid(count: 80, bounds: $0.bounds, radius: 8, spacing: nil,
                                       seed: $0.variation)) },
             other: { rig(ParticleFluid(count: 80, bounds: $0.bounds, radius: 8, spacing: nil,
                                        seed: $0.variation + 1)) }),
        Pair(name: "soft bodies",
             factory: { rig($0.makeSoftBodies(bodies: 3, radius: 8)) },
             core: { rig(SoftBodies(bodies: 3, bounds: $0.bounds, radius: 8, spacing: nil, seed: $0.variation)) },
             other: { rig(SoftBodies(bodies: 3, bounds: $0.bounds, radius: 8, spacing: nil,
                                     seed: $0.variation + 1)) }),
    ]

    /// A factory left to its defaults fills the sketch's canvas and seeds
    /// from the sketch's `variation`, and where it has defaults of its own
    /// (a swarm's size, a chemistry's kinds) they are the ones written here.
    /// Nothing runs on the GPU: the seeded particles are the reading.
    @Test(arguments: defaults)
    func leftToItsDefaultsAFactoryFillsTheCanvasFromTheSketchSeed(_ pair: Pair) throws {
        let sketch = Sketch()
        sketch.setCanvasSize(width: 61, height: 47)
        sketch.seed(Self.variation)
        let made = pair.factory(sketch), built = pair.core(sketch), other = pair.other(sketch)

        #expect(made.configuration == built.configuration)
        let seeded = try #require(made.state())
        let builtSeeded = built.state()
        let otherSeeded = try #require(other.state())
        #expect(!seeded.isEmpty)
        #expect(seeded == builtSeeded, "the default bounds or seed is not the sketch's")
        #expect(seeded != otherSeeded, "a different seed scattered the same particles")
    }

    /// The neighbor grid under the particle sims: the factory's `radius` is
    /// the initializer's `cellSize`, and with no bounds named the grid covers
    /// the canvas.
    @Test func theHashFactoryBuildsTheGridItsInitializerBuilds() {
        let sketch = Sketch()
        sketch.setCanvasSize(width: 61, height: 47)
        let made = sketch.makeSpatialHash(in: Self.box, radius: 9, count: 77)
        let built = SpatialHash(bounds: Self.box, cellSize: 9, count: 77)
        #expect(gridLayout(of: made) == gridLayout(of: built))

        let whole = sketch.makeSpatialHash(radius: 9, count: 77)
        let canvas = SpatialHash(bounds: sketch.bounds, cellSize: 9, count: 77)
        #expect(gridLayout(of: whole) == gridLayout(of: canvas))
        #expect(gridLayout(of: whole) != gridLayout(of: made), "the bounds made no difference")
    }

    // MARK: Sims read from their picture

    nonisolated static let fieldPairs: [Pair] = [
        Pair(name: "physarum by resolution, seeded by the sketch",
             factory: { rig($0.makePhysarum(agents: 900, resolution: 36)) },
             core: { rig(Physarum(agents: 900, width: 36, height: 36, seed: $0.variation)) },
             other: { rig(Physarum(agents: 900, width: 36, height: 36, seed: $0.variation + 1)) }),
        Pair(name: "physarum by width and height",
             factory: { rig($0.makePhysarum(agents: 900, width: 40, height: 28, seed: 31)) },
             core: { _ in rig(Physarum(agents: 900, width: 40, height: 28, seed: 31)) },
             other: { _ in rig(Physarum(agents: 900, width: 28, height: 40, seed: 31)) }),
        Pair(name: "sim field on the canvas",
             factory: { rig($0.makeSimField(rule, scale: 0.5, edge: .clamped, precision: .float32)) },
             core: { rig($0.makeSimField(rule, width: 64, height: 48, scale: 0.5, edge: .clamped,
                                         precision: .float32)) },
             other: { rig($0.makeSimField(rule, width: 48, height: 64, scale: 0.5, edge: .clamped,
                                          precision: .float32)) }),
        Pair(name: "sim field by size",
             factory: { rig($0.makeSimField(rule, width: 40, height: 28, scale: 0.5, edge: .clamped,
                                            precision: .float32)) },
             core: { rig(SimField(sim: rule, width: 40, height: 28, scale: 0.5, drawer: $0.drawer,
                                  edge: .clamped, precision: .float32)) },
             other: { rig(SimField(sim: rule, width: 40, height: 28, scale: 0.25, drawer: $0.drawer,
                                   edge: .clamped, precision: .float32)) }),
        Pair(name: "ocean field on the sketch clock",
             factory: { _ in rig(sea: { $0.makeOceanField(water, resolution: 64) }) },
             core: { _ in rig(sea: { $0.makeOceanField(water, at: $0.time, resolution: 64) }) },
             other: { _ in rig(sea: { $0.makeOceanField(water, at: $0.time + 1.7, resolution: 64) }) }),
    ]

    /// Each spelling runs five frames in a sketch of its own, and the two
    /// pictures match pixel for pixel; the third spelling's does not.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: fieldPairs)
    func theFactoryDrawsWhatItsCoreCallDraws(_ pair: Pair) throws {
        let made = Bench { [pair.factory($0)] }
        let built = Bench { [pair.core($0)] }
        let other = Bench { [pair.other($0)] }
        let factory = pixels(of: try OllinApp.image(of: made, frame: Self.lastFrame))
        let core = pixels(of: try OllinApp.image(of: built, frame: Self.lastFrame))
        let third = pixels(of: try OllinApp.image(of: other, frame: Self.lastFrame))

        let madeRig = try #require(made.rigs.first), builtRig = try #require(built.rigs.first)
        #expect(madeRig.configuration == builtRig.configuration)
        #expect(holdsInk(factory), "the factory's field drew nothing")
        #expect(factory == core)
        #expect(factory != third, "a different argument drew the same picture")
    }
}

private typealias Rig = SimFactoryFormsTests.Rig

// MARK: - One rig per type

@MainActor
private func rig(_ sim: ParticleLife) -> Rig {
    Rig(configuration: ["count \(sim.count)", "kinds \(sim.kinds)"],
        state: { readback(of: sim.current) },
        step: { $0.stepParticleLife(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: PPS) -> Rig {
    Rig(configuration: ["count \(sim.count)", "speed \(sim.speed)"],
        state: { readback(of: sim.current) },
        step: { $0.stepPrimordialParticles(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: Swarm) -> Rig {
    // Every weight starts at zero, and a swarm that only coasts never asks
    // who is near; with these, each step reads the neighbor grid.
    sim.separation = 1.3
    sim.alignment = 0.8
    sim.cohesion = 0.6
    return Rig(configuration: ["count \(sim.count)", "perceptionRadius \(sim.perceptionRadius)"],
               state: { readback(of: sim.current) },
               step: { $0.stepSwarm(sim) },
               draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: ParticleLenia) -> Rig {
    Rig(configuration: ["count \(sim.count)", "spacing \(sim.spacing)"],
        state: { readback(of: sim.current) },
        step: { $0.stepParticleLenia(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: SwarmChemistry) -> Rig {
    Rig(configuration: ["count \(sim.count)", "kinds \(sim.kinds)", "spacing \(sim.spacing)",
                        "lengthScale \(sim.lengthScale)", "perceptionLimit \(sim.perceptionLimit)",
                        "contactRadius \(sim.contactRadius)", "size \(sim.size)",
                        "openingRecipes \(sim.openingRecipes)"],
        state: { readback(of: sim.current) },
        step: { $0.stepSwarmChemistry(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: AttractorFlow) -> Rig {
    // A splat is about a pixel across on a full canvas; on this one it needs
    // to be larger and opaque to leave ink. Both spellings get the same.
    sim.size = sim.extent / 10
    sim.opacity = 1
    return Rig(configuration: ["count \(sim.count)", "system \(sim.system)", "center \(sim.center)",
                               "extent \(sim.extent)"],
               state: { readback(of: sim.current) },
               step: { $0.stepAttractorFlow(sim) },
               draw: { sketch in
                   // The flow is 3D and draws nothing without a camera.
                   let middle = sim.center, reach = sim.extent * 3
                   sketch.camera(Camera3D(eye: Vector3(middle.x + reach * 0.4, middle.y + reach * 0.3,
                                                       middle.z + reach),
                                          target: middle))
                   sketch.drawParticles(sim)
               })
}

@MainActor
private func rig(_ sim: Evolution) -> Rig {
    Rig(configuration: ["count \(sim.count)", "genes \(sim.genes)", "start \(sim.start)",
                        "target \(sim.target)"],
        state: {
            // The seed is in the genomes; the particles all open at the start.
            guard let particles = readback(of: sim.current),
                  let genomes = readback(of: sim.currentGenes) else { return nil }
            return particles + genomes
        },
        step: { $0.stepEvolution(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: ParticleFluid) -> Rig {
    Rig(configuration: ["count \(sim.count)", "radius \(sim.radius)", "spacing \(sim.spacing)",
                        "bounds \(sim.bounds)"],
        state: { readback(of: sim.current) },
        step: { $0.stepParticleFluid(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: SoftBodies) -> Rig {
    Rig(configuration: ["bodies \(sim.bodies)", "count \(sim.count)", "radius \(sim.radius)",
                        "spacing \(sim.spacing)", "bounds \(sim.bounds)",
                        "seededCenters \(sim.seededCenters)"],
        state: { readback(of: sim.current) },
        step: { $0.stepSoftBodies(sim) },
        draw: { $0.drawParticles(sim) })
}

@MainActor
private func rig(_ sim: Physarum) -> Rig {
    Rig(configuration: ["agents \(sim.agents)", "width \(sim.width)", "height \(sim.height)"],
        state: { nil },
        step: { $0.stepPhysarum(sim) },
        draw: { $0.drawImage(sim.image, in: $0.bounds) })
}

@MainActor
private func rig(_ field: SimField) -> Rig {
    // Reading the field's image is what steps it, so the draw is the step.
    Rig(configuration: ["width \(field.width)", "height \(field.height)", "scale \(field.scale)",
                        "precision \(field.precision)", "edge \(field.edge)"],
        state: { nil },
        step: { _ in },
        draw: { $0.drawImage(field.image, 0, 0) })
}

/// A sea is one frame's work, built again in every `draw()`, so there is
/// nothing to read back before the draw and the picture is the reading. The
/// field is signed data whose alpha is the fold, so its height is mapped to a
/// gray before it is drawn.
@MainActor
private func rig(sea field: @escaping @MainActor (Sketch) -> OceanField) -> Rig {
    Rig(configuration: [],
        state: { nil },
        step: { _ in },
        draw: { sketch in
            let heights = field(sketch).layer.filtered(.shader(Shader("""
            float4 shade(float2 uv, ShaderInfo info) {
                float4 field = sampleRaw(info, uv);
                float v = 0.5 + field[1] * 0.3;
                return float4(v, v, v, 1.0);
            }
            """)))
            sketch.drawImage(heights.image, 0, 0)
        })
}

// MARK: - Readings

/// A buffer's elements as bytes: what it was seeded with before it has been
/// bound, what the GPU last wrote after. The particle structs have no padding
/// the compiler chose (every pad is a named field, zeroed), so equal bytes
/// are equal particles.
@MainActor
private func readback<Element>(of buffer: ComputeBuffer<Element>) -> [UInt8]? {
    guard let values = buffer.snapshot() else { return nil }
    return values.withUnsafeBytes { [UInt8]($0) }
}

/// Everything a neighbor grid derives from its bounds, its cell size, and its
/// count.
@MainActor
private func gridLayout(of hash: SpatialHash) -> [String] {
    ["count \(hash.count)", "cellSize \(hash.cellSize)", "cellExtent \(hash.cellExtent)",
     "origin \(hash.origin)", "worldSize \(hash.worldSize)",
     "grid \(hash.gridWidth) by \(hash.gridHeight)"]
}

/// Whether a frame holds more than one flat color: some pixel unlike the first.
private func holdsInk(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 8 else { return false }
    return stride(from: 4, to: bytes.count, by: 4).contains { i in
        bytes[i] != bytes[0] || bytes[i + 1] != bytes[1] || bytes[i + 2] != bytes[2]
    }
}

/// A 64 by 48 canvas that builds its rigs in `setup()`, steps every one of
/// them each frame, and draws the first. The sketch is pinned to one seed
/// before anything is built, so a factory left to its default seed reads a
/// known one.
@MainActor
private final class Bench: Sketch {
    var rigging: @MainActor (Sketch) -> [Rig] = { _ in [] }
    private(set) var rigs: [Rig] = []
    /// Each rig's state as built, before the first step.
    private(set) var opening: [[UInt8]?] = []

    convenience init(_ rigging: @escaping @MainActor (Sketch) -> [Rig]) {
        self.init()
        self.rigging = rigging
    }

    override var canvasSize: CanvasSize { .size(64, 48) }

    override func setup() {
        seed(SimFactoryFormsTests.variation)
        rigs = rigging(self)
        opening = []
        for rig in rigs { opening.append(rig.state()) }
    }

    override func draw() {
        background(.black)
        for rig in rigs { rig.step(self) }
        rigs.first?.draw(self)
    }
}
