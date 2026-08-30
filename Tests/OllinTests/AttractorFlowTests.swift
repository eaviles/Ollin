import Foundation
import Testing
import simd
import COllinShaders   // OllinPoint, OllinAttractorParams
@testable import Ollin

/// The GPU strange-attractor flow. The system values, the survey that places and paces
/// a flow, and the parameter packing run everywhere; stepping is Metal-gated and soft
/// skips without a GPU (`Snapshot.hasMetal`).
///
/// A chaotic system cannot be pinned trajectory by trajectory: two particles a float's
/// width apart separate exponentially by design, so "the GPU got the same answer as the
/// CPU" is only ever true for a few steps and never true after a second of running.
/// What *is* invariant is where the orbit lives, so the stepping tests compare the
/// particle cloud's own region and pace against a CPU orbit of the same equations, each
/// against the counterfactual of a different system. There is no pixel snapshot, for
/// the same reason the rest of this path carries none.
@Suite
@MainActor
struct AttractorFlowTests {

    static let everySystem: [(String, AttractorSystem)] = [
        ("lorenz", .lorenz()), ("rossler", .rossler()), ("aizawa", .aizawa()),
        ("thomas", .thomas()), ("halvorsen", .halvorsen()), ("dadras", .dadras()),
        ("chen", .chen()), ("fourWing", .fourWing()),
    ]

    // MARK: GPU-free: layout, systems, packing

    @Test func paramsStrideMatchesHeader() {
        // Two float4 rows, eight ramp stops, the seed row, then six floats and three
        // uints: 208 bytes. A drift here silently feeds the kernel the wrong fields.
        #expect(MemoryLayout<OllinAttractorParams>.stride == 208)
    }

    @Test func everySystemHasItsOwnShaderIndex() {
        // The kernel dispatches on this number, so a collision would quietly run one
        // system's equations under another's name.
        let indices = Self.everySystem.map { $0.1.shaderIndex }
        #expect(Set(indices).count == Self.everySystem.count)
        #expect(indices.max()! == UInt32(Self.everySystem.count - 1))
    }

    @Test func aSystemMatchesItsCPUTwin() {
        // The two sides must be the same equations with the same constants, since the
        // CPU orbit is what places, paces, and seeds the GPU one.
        for (name, system) in Self.everySystem {
            let twin = system.attractor
            #expect(twin.step == system.step, "\(name) step")
            #expect(twin.start.x == system.start.x && twin.start.y == system.start.y
                    && twin.start.z == system.start.z, "\(name) start")
        }
        // And the field itself, against Lorenz's published equations by hand at (1,2,3):
        // sigma(y-x) = 10, x(rho-z)-y = 23, xy - beta*z = -6.
        let d = AttractorSystem.lorenz().attractor.derivative(Vector3(1, 2, 3))
        #expect(abs(d.x - 10) < 1e-12)
        #expect(abs(d.y - 23) < 1e-12)
        #expect(abs(d.z - (2 - (8.0 / 3.0) * 3)) < 1e-12)
    }

    @Test func constantsPackInTheOrderTheKernelReads() {
        // Aizawa is the only system that reaches the second row, so it is the one that
        // pins the split.
        let (a, b) = AttractorSystem.aizawa(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6).packedParameters
        #expect(a == SIMD4<Float>(1, 2, 3, 4))
        #expect(b.x == 5 && b.y == 6)
        // A three-constant system fills the first row and leaves the second alone.
        let (c, d) = AttractorSystem.lorenz(sigma: 7, rho: 8, beta: 9).packedParameters
        #expect(c == SIMD4<Float>(7, 8, 9, 0))
        #expect(d == SIMD4<Float>(repeating: 0))
    }

    @Test func theReachIsRobustToHowLongYouWatch() {
        // The counterfactual: measured as an outright maximum, the four-wing system's
        // reach nearly doubles between a short sample and a long one (its rare
        // excursions keep finding new ground), which would move the framing, the dot
        // size, and the stray test with it. Measured as a percentile it settles.
        let system = AttractorSystem.fourWing()
        let short = AttractorFlow(count: 4_000, system: system, seed: 1).extent
        let long = AttractorFlow(count: 120_000, system: system, seed: 1).extent
        #expect(abs(long - short) / short < 0.25, "percentile reach: \(short) vs \(long)")

        let maxShort = Self.maximumReach(system, points: 4_000)
        let maxLong = Self.maximumReach(system, points: 120_000)
        #expect(abs(maxLong - maxShort) / maxShort > 0.5,
                "the extremes should be the unstable measure: \(maxShort) vs \(maxLong)")
    }

    @Test func aFlowStartsOnItsAttractor() {
        // Seeded from a settled orbit rather than a box around it, so a system whose
        // phase volume barely contracts still opens looking like itself.
        let flow = AttractorFlow(count: 20_000, system: .aizawa(), seed: 3)
        guard let seeds = flow.current.snapshot() else { return }
        let reach = seeds.map { p -> Double in
            let d = Vector3(Double(p.position.x) - flow.center.x,
                            Double(p.position.y) - flow.center.y,
                            Double(p.position.z) - flow.center.z)
            return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        }
        // Every particle within the measured reach and a margin; a box scatter of the
        // same width would put the corners at sqrt(3) times it.
        #expect(reach.allSatisfy { $0 < flow.extent * 1.6 })
        // And spread over the shape, not piled at one point.
        #expect(reach.max()! > flow.extent * 0.5)
    }

    @Test func aFlowReproducesFromItsSeed() {
        let a = AttractorFlow(count: 500, system: .lorenz(), seed: 12_345)
        let b = AttractorFlow(count: 500, system: .lorenz(), seed: 12_345)
        let c = AttractorFlow(count: 500, system: .lorenz(), seed: 54_321)
        guard let pa = a.current.snapshot(), let pb = b.current.snapshot(),
              let pc = c.current.snapshot() else { return }
        #expect(zip(pa, pb).allSatisfy { $0.position == $1.position })
        #expect(zip(pa, pc).contains { $0.position != $1.position })
    }

    /// The reach measured the naive way, as the outright extreme, for the counterfactual
    /// above.
    private static func maximumReach(_ system: AttractorSystem, points: Int) -> Double {
        let path = system.attractor.orbit(count: points, settle: 2000)
        var lo = path[0], hi = path[0]
        for p in path {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        return max(max(hi.x - lo.x, hi.y - lo.y), hi.z - lo.z) / 2
    }

    // MARK: Stepping (Metal-gated)

    @Test(.enabled(if: Snapshot.hasMetal))
    func steppingKeepsTheParticlesOnTheAttractor() throws {
        // Run each system for a while and check the cloud still occupies the region its
        // own CPU orbit does. A sign slip or a mis-packed constant in the kernel would
        // send the particles somewhere else or off to infinity; neither survives this.
        for (name, system) in Self.everySystem {
            let probe = FlowProbe()
            probe.system = system
            probe.particles = 20_000
            _ = OllinApp.image(of: probe, frame: 90)
            guard let points = probe.flow.current.snapshot() else {
                Issue.record("\(name): the flow buffer was never realized")
                continue
            }
            #expect(points.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite
                                        && $0.position.z.isFinite }, "\(name) went non-finite")

            // The cloud's own middle and reach, measured the way the survey measures the
            // orbit's, against what the CPU side said to expect.
            let (center, extent) = Self.region(of: points)
            let expected = probe.flow.extent
            #expect(extent > expected * 0.5 && extent < expected * 1.8,
                    "\(name): cloud reach \(extent) against the orbit's \(expected)")
            let drift = (center - probe.flow.center).length
            #expect(drift < expected * 0.5,
                    "\(name): cloud middle drifted \(drift) from the orbit's")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aDifferentSystemLandsSomewhereElse() throws {
        // The counterfactual for the test above: the region check is only worth
        // anything if running the wrong equations fails it. Lorenz's butterfly reaches
        // about twenty units; Aizawa's shell about one and a half.
        let lorenz = FlowProbe(); lorenz.system = .lorenz(); lorenz.particles = 10_000
        let aizawa = FlowProbe(); aizawa.system = .aizawa(); aizawa.particles = 10_000
        _ = OllinApp.image(of: lorenz, frame: 60)
        _ = OllinApp.image(of: aizawa, frame: 60)
        guard let a = lorenz.flow.current.snapshot(), let b = aizawa.flow.current.snapshot()
        else { return }
        let (_, ra) = Self.region(of: a), (_, rb) = Self.region(of: b)
        #expect(ra > rb * 5, "Lorenz \(ra) should dwarf Aizawa \(rb)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStrayIsPutBackRatherThanLeftToStreak() throws {
        // Constants nobody checked can throw particles out of the basin, and a position
        // running to infinity draws a splat wherever the projection lands it. The guard
        // catches anything past the escape radius and drops it back in the middle, so
        // the cloud stays bounded however wild the system is.
        let probe = FlowProbe()
        probe.system = .chen(alpha: 40, beta: -60, delta: 4)   // well outside the published set
        probe.particles = 8_000
        _ = OllinApp.image(of: probe, frame: 45)
        guard let points = probe.flow.current.snapshot() else { return }
        #expect(points.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite
                                    && $0.position.z.isFinite })
        let escape = probe.flow.extent * 12
        let far = points.filter { p in
            let d = Vector3(Double(p.position.x) - probe.flow.center.x,
                            Double(p.position.y) - probe.flow.center.y,
                            Double(p.position.z) - probe.flow.center.z)
            return d.length > escape * 1.5
        }
        #expect(far.isEmpty, "\(far.count) particles left the escape radius behind")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func colorFollowsSpeed() throws {
        // The ramp is read by how fast a particle is moving, which is what shows the
        // structure. Two flat ramps that differ only in their one color must come back
        // differing the same way, and a real ramp must produce more than one color.
        let flat = FlowProbe()
        flat.system = .lorenz(); flat.particles = 4_000
        flat.colors = [Color.red]
        _ = OllinApp.image(of: flat, frame: 30)
        guard let flatPoints = flat.flow.current.snapshot() else { return }
        #expect(flatPoints.allSatisfy { abs($0.color.x - 1) < 1e-5 && $0.color.y < 1e-5 })

        let graded = FlowProbe()
        graded.system = .lorenz(); graded.particles = 4_000
        graded.colors = [Color.red, Color.green]
        _ = OllinApp.image(of: graded, frame: 30)
        guard let gradedPoints = graded.flow.current.snapshot() else { return }
        let greens = gradedPoints.map(\.color.y)
        #expect(greens.max()! - greens.min()! > 0.3, "the ramp should spread across the cloud")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theStepNeverOutrunsTheSystem() throws {
        // Asking for far more pace than the substep ceiling allows must slow the flow
        // down, never coarsen the step: a step past the one a system was published at
        // is a different system, and for these it usually means a cloud that blows up.
        let sane = FlowProbe(); sane.system = .halvorsen(); sane.particles = 8_000
        let greedy = FlowProbe(); greedy.system = .halvorsen(); greedy.particles = 8_000
        greedy.speed = 400
        _ = OllinApp.image(of: sane, frame: 60)
        _ = OllinApp.image(of: greedy, frame: 60)
        guard let a = sane.flow.current.snapshot(), let b = greedy.flow.current.snapshot()
        else { return }
        let (_, ra) = Self.region(of: a), (_, rb) = Self.region(of: b)
        #expect(rb < ra * 1.8, "a greedy pace should stay on the attractor, not detonate: \(rb) vs \(ra)")
        #expect(b.allSatisfy { $0.position.x.isFinite })
    }

    /// The middle and reach of a particle cloud, read off percentiles the way the survey
    /// reads them off an orbit, so the two are comparable.
    private static func region(of points: [OllinPoint]) -> (Vector3, Double) {
        var xs = points.map { Double($0.position.x) }
        var ys = points.map { Double($0.position.y) }
        var zs = points.map { Double($0.position.z) }
        xs.sort(); ys.sort(); zs.sort()
        func span(_ v: [Double]) -> (Double, Double) {
            (v[v.count / 200], v[min(v.count - 1, (v.count * 199) / 200)])
        }
        let (x0, x1) = span(xs), (y0, y1) = span(ys), (z0, z1) = span(zs)
        return (Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                max(max(x1 - x0, y1 - y0), z1 - z0) / 2)
    }
}

@MainActor
private final class FlowProbe: Sketch {
    var system: AttractorSystem = .lorenz()
    var particles = 10_000
    var speed: Double?
    var colors: [Color]?
    private(set) var flow: AttractorFlow!

    override func setup() {
        flow = makeAttractorFlow(count: particles, system, seed: 4242)
        if let speed { flow.speed = speed }
        if let colors { flow.colors = colors }
    }

    override func draw() { updateAttractorFlow(flow) }
}
