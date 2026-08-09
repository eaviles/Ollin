import Foundation
import Testing
import simd
import COllinShaders   // OllinSwarmParams
@testable import Ollin

/// The GPU steering crowd. Like the artificial-life sims it shares the `SpatialHash`
/// with, its neighbor sums are GPU-race-ordered and flocking is chaotic, so there is
/// no pixel snapshot and no frame-exact promise. What is pinned instead is each
/// behavior's own unmistakable signature, measured against the counterfactual of the
/// same swarm with that one weight turned off: alignment makes headings agree,
/// cohesion pulls a scattered crowd together, separation pushes a packed one apart,
/// seek closes on the target, flee opens away from it, arrive stops on it, and
/// wander turns without ever settling on one direction.
@Suite
@MainActor
struct SwarmTests {

    // MARK: GPU-free

    @Test func paramStrideMatchesHeader() {
        // Shared CPU/GPU struct; a drift here corrupts every dispatch.
        #expect(MemoryLayout<OllinSwarmParams>.stride == 96)
    }

    @Test func derivations() {
        let box = Rectangle(x: 0, y: 0, width: 600, height: 600)
        let s = Swarm(count: 400, bounds: box, perceptionRadius: 30, seed: 1)
        #expect(s.count == 400)
        #expect(s.perceptionRadius == 30)
        // Every behavior starts off, so a fresh swarm only coasts.
        #expect(s.separation == 0 && s.alignment == 0 && s.cohesion == 0)
        #expect(s.seek == 0 && s.flee == 0 && s.arrive == 0)
        #expect(s.wander == 0 && s.flow == 0)
    }

    // MARK: Metal-gated: each behavior against its counterfactual

    @Test(.enabled(if: Snapshot.hasMetal))
    func alignmentMakesNeighborsAgree() throws {
        // Alignment is a *local* rule, so what it must produce is local agreement:
        // each agent pointing the way its own neighbors point. Measuring the whole
        // crowd's agreement instead would be measuring how long the swarm takes to
        // mix, which is a much slower and quite separate thing (it does get there:
        // 0.10 of one heading at 1s, 0.46 at 4s, 0.97 at 20s).
        let aligned = try localOrder(frames: 240) { $0.alignment = 2 }
        let loose = try localOrder(frames: 240) { _ in }
        #expect(aligned > 0.9, "aligned swarm agreed only \(aligned) with its neighbors")
        #expect(loose < 0.3, "unsteered swarm agreed \(loose) with no alignment")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func cohesionCrowdsAndSeparationOpensUp() throws {
        // Both are measured as how far an agent sits from its *nearest* neighbor,
        // which is the thing each behavior is actually about, and which works on a
        // uniformly seeded torus where distance from the centre would not move.
        let coasting = try nearestNeighborDistance { _ in }
        let gathered = try nearestNeighborDistance { $0.cohesion = 2 }
        let spread = try nearestNeighborDistance {
            $0.separation = 2; $0.separationRadius = 60
        }
        #expect(gathered < coasting * 0.9,
                "cohesion crowded to \(gathered) vs \(coasting) without it")
        #expect(spread > coasting * 1.1,
                "separation opened to \(spread) vs \(coasting) without it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func seekClosesOnTheTargetAndFleeOpensAway() throws {
        let target = Vector2(300, 300)
        let seeking = try meanDistanceToTarget(target) { $0.seek = 2 }
        let fleeing = try meanDistanceToTarget(target) { $0.flee = 2 }
        let coasting = try meanDistanceToTarget(target) { _ in }
        #expect(seeking < coasting * 0.8, "seek closed to \(seeking) vs \(coasting) coasting")
        #expect(fleeing > coasting, "flee opened to \(fleeing) vs \(coasting) coasting")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func arriveStopsWhereSeekKeepsOvershooting() throws {
        // Both crowds end up on the target; the difference is that arrive is *done*
        // and seek never is, because seek always wants to be travelling at top speed
        // and so keeps sailing through and turning back. The ramp that stops arrive
        // lives in the force's magnitude, which is why arrive is the one behavior
        // whose steering must not be normalized.
        let target = Vector2(300, 300)
        let arriving = try probeSwarm(target: target, frames: 600) {
            $0.arrive = 2; $0.slowingRadius = 160
        }
        let seeking = try probeSwarm(target: target, frames: 600) { $0.seek = 2 }
        let arriveSpeed = meanSpeed(arriving)
        let seekSpeed = meanSpeed(seeking)
        #expect(arriveSpeed < seekSpeed * 0.1,
                "arrive settled at \(arriveSpeed) vs seek's \(seekSpeed)")
        #expect(meanDistance(arriving, to: target) < 5,
                "arrive should be sitting on its target, not \(meanDistance(arriving, to: target)) away")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func wanderTurnsWithoutSettling() throws {
        // Wander must be a random *walk* on the heading, not a fresh random force:
        // agents keep moving (they never stall) and the crowd as a whole never
        // agrees on a direction the way an aligned one does.
        let ps = try probeSwarm(target: .zero) { $0.wander = 2 }
        #expect(meanSpeed(ps) > 40, "wandering agents stalled at \(meanSpeed(ps))")
        #expect(polarization(of: ps) < 0.5,
                "wander should not polarize the crowd (\(polarization(of: ps)))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func agentsStayFiniteAndInsideTheWorld() throws {
        // Everything on at once, in the worst combination, still lands inside the
        // torus with no NaN: the numbers a sketch drags a knob to must stay safe.
        let ps = try probeSwarm(target: Vector2(300, 300), frames: 90) {
            $0.separation = 3; $0.alignment = 3; $0.cohesion = 3
            $0.seek = 3; $0.flee = 3; $0.arrive = 3; $0.wander = 3; $0.flow = 3
        }
        #expect(ps.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
        #expect(ps.allSatisfy { $0.velocity.x.isFinite && $0.velocity.y.isFinite })
        #expect(ps.allSatisfy {
            $0.position.x >= 0 && $0.position.x <= 600 &&
            $0.position.y >= 0 && $0.position.y <= 600
        })
        // maxSpeed is a cap, not a suggestion, whatever the forces sum to.
        #expect(ps.allSatisfy { simd_length($0.velocity) <= Float(SwarmProbe.topSpeed) + 1 })
    }

    // MARK: Measurements

    /// How much the crowd agrees on a direction: 1 is every agent pointing the same
    /// way, 0 is no agreement at all.
    private func polarization(of ps: [OllinParticle]) -> Double {
        var sum = SIMD2<Float>.zero
        for p in ps where simd_length(p.velocity) > 1e-4 {
            sum += simd_normalize(p.velocity)
        }
        return Double(simd_length(sum)) / Double(ps.count)
    }

    private func meanSpeed(_ ps: [OllinParticle]) -> Double {
        Double(ps.map { simd_length($0.velocity) }.reduce(0, +)) / Double(ps.count)
    }

    private func meanDistance(_ ps: [OllinParticle], to point: Vector2) -> Double {
        let t = SIMD2<Float>(Float(point.x), Float(point.y))
        return Double(ps.map { simd_length($0.position - t) }.reduce(0, +)) / Double(ps.count)
    }

    /// How far each agent's heading agrees with the mean heading of the neighbors it
    /// can see: 1 is every agent going with its own crowd, 0 is no local agreement.
    /// This is what alignment is a rule about, so it is what the test measures.
    private func localOrder(frames: Int,
                            _ configure: @escaping (Swarm) -> Void) throws -> Double {
        let ps = try probeSwarm(target: .zero, frames: frames, configure: configure)
        guard !ps.isEmpty else { return 0 }
        let radius: Float = 60
        var total = 0.0
        for (i, p) in ps.enumerated() {
            var neighbors = SIMD2<Float>.zero
            for (j, q) in ps.enumerated() where j != i {
                guard simd_length_squared(p.position - q.position) < radius * radius,
                      simd_length(q.velocity) > 1e-4 else { continue }
                neighbors += simd_normalize(q.velocity)
            }
            guard simd_length(neighbors) > 1e-4, simd_length(p.velocity) > 1e-4 else { continue }
            total += Double(simd_dot(simd_normalize(p.velocity), simd_normalize(neighbors)))
        }
        return total / Double(ps.count)
    }

    private func meanDistanceToTarget(_ target: Vector2,
                                      _ configure: @escaping (Swarm) -> Void) throws -> Double {
        meanDistance(try probeSwarm(target: target, configure: configure), to: target)
    }

    /// Mean distance from an agent to its nearest neighbor: how crowded the swarm
    /// is, which is what cohesion tightens and separation opens.
    private func nearestNeighborDistance(_ configure: @escaping (Swarm) -> Void) throws -> Double {
        let ps = try probeSwarm(target: .zero, configure: configure)
        guard ps.count > 1 else { return 0 }
        var total = 0.0
        for (i, p) in ps.enumerated() {
            var best = Float.greatestFiniteMagnitude
            for (j, q) in ps.enumerated() where j != i {
                best = min(best, simd_length_squared(p.position - q.position))
            }
            total += Double(best.squareRoot())
        }
        return total / Double(ps.count)
    }

    private func probeSwarm(target: Vector2, count: Int = 600, perception: Double = 60,
                            frames: Int = 120,
                            configure: @escaping (Swarm) -> Void) throws -> [OllinParticle] {
        let probe = SwarmProbe()
        probe.agentCount = count
        probe.perception = perception
        probe.target = target
        probe.configure = configure
        _ = OllinApp.image(of: probe, frame: frames)
        guard let ps = probe.swarm.current.snapshot() else {
            Issue.record("swarm never realized")
            return []
        }
        return ps
    }
}

/// One swarm in a 600×600 world, configured by the test and stepped headlessly.
@MainActor
private final class SwarmProbe: Sketch {
    static let topSpeed = 150.0
    let box = Rectangle(x: 0, y: 0, width: 600, height: 600)
    var swarm: Swarm!
    // Set by the test before the headless run; `Sketch` owns `init()`, so the probe
    // is configured by assignment rather than by a custom initializer.
    var agentCount = 600
    var perception = 60.0
    var target = Vector2.zero
    var configure: (Swarm) -> Void = { _ in }

    override var canvasSize: CanvasSize { .square(600) }

    override func setup() {
        swarm = Swarm(count: agentCount, bounds: box, perceptionRadius: perception, seed: 11)
        swarm.maxSpeed = SwarmProbe.topSpeed
        swarm.maxForce = 1200
        swarm.target = target
        configure(swarm)
    }

    override func draw() {
        background(.black)
        updateSwarm(swarm)
        drawParticles(swarm)
    }
}
