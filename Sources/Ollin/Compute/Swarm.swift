import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid, OllinSwarmParams

/// A crowd of steering creatures on the GPU: the same behavior vocabulary the CPU
/// `Vehicle` and `Boids` speak, run over the `SpatialHash` neighbor search so a flock
/// is hundreds of thousands of agents instead of a few hundred.
///
/// Every behavior is a **weight**, and a weight of zero is a behavior that is off, so
/// one swarm is a flock, a crowd chasing the mouse, or a field of aimless wanderers
/// depending on which numbers you set. Each behavior works out a *desired velocity*
/// and returns the difference from the velocity the agent already has; the weighted
/// sum is capped at `maxForce` and drives the agent, capped at `maxSpeed`.
///
/// - `separation` steers away from whoever is too close (within `separationRadius`).
/// - `alignment` steers toward the average heading of the neighbors it can see.
/// - `cohesion` steers toward the middle of them.
/// - `seek` steers at `target`; `flee` steers away from it.
/// - `arrive` steers at `target` but slows to a stop, easing in over `slowingRadius`.
/// - `wander` roams, turning by a random walk rather than jittering on the spot.
/// - `flow` follows a swirling flow field (`flowScale` sets how big its eddies are).
///
/// Build it in `setup()`, then step and draw it in `draw()`:
///
/// ```swift
/// var swarm: Swarm!
/// override func setup() {
///     background(.black); noClear()
///     swarm = makeSwarm(count: 120_000, perceptionRadius: 34)
///     swarm.alignment = 1.2
///     swarm.cohesion = 0.7
///     swarm.separation = 1.6
/// }
/// override func draw() {
///     background(Color.black.withAlpha(0.14))
///     blendMode(.add)
///     swarm.target = Vector2(mouseX, mouseY)
///     swarm.seek = mouseIsPressed ? 1.5 : 0
///     updateSwarm(swarm)
///     drawParticles(swarm)
/// }
/// ```
///
/// The world is a torus, like the other systems on this path: an agent that leaves one
/// edge comes back at the opposite one, and neighbors are found across the seam too, so
/// there are no edges for a flock to pile up against.
///
/// Speeds and forces are **per second** here (the CPU `Vehicle`'s are per step), so the
/// swarm keeps its pace whatever the frame rate. Pursuit and evasion are not separate
/// behaviors because they do not need to be: pursuit is `seek` aimed at where the quarry
/// *will* be, so lead the `target` yourself and `seek` becomes pursuit.
@MainActor
public final class Swarm {
    /// How many agents.
    public let count: Int
    /// How far an agent can see other agents (points). Fixed at build: it is the
    /// neighbor grid's cell size.
    public let perceptionRadius: Double

    /// The point `seek`, `flee`, and `arrive` steer by (canvas points).
    public var target: Vector2 = .zero

    /// Steer-away-from-crowding weight.
    public var separation: Double = 0
    /// Match-the-neighbors'-heading weight.
    public var alignment: Double = 0
    /// Steer-toward-the-neighbors'-middle weight.
    public var cohesion: Double = 0
    /// Steer-at-`target` weight.
    public var seek: Double = 0
    /// Steer-away-from-`target` weight.
    public var flee: Double = 0
    /// Steer-at-`target`-and-stop weight.
    public var arrive: Double = 0
    /// Roam weight.
    public var wander: Double = 0
    /// Follow-the-flow-field weight.
    public var flow: Double = 0

    /// Top speed an agent may travel (points per second).
    public var maxSpeed: Double = 190
    /// The slowest an agent may travel (points per second). Zero, the default, is
    /// the plain steering model, where an agent that is pushed at from every side
    /// simply stops. A crowded swarm will then jam: the stalled agents are a wall
    /// the rest cannot get through, and the whole thing sets into a fixed pattern.
    /// Setting a floor is what makes a dense crowd keep flowing, on the grounds
    /// that a bird cannot hover.
    public var minSpeed: Double = 0
    /// The strongest steering force an agent may apply (points per second squared).
    /// Lower turns are smoother and more sluggish, higher ones snap.
    public var maxForce: Double = 620
    /// How close is too close, for `separation` (points). Clamped to
    /// `perceptionRadius`.
    public var separationRadius: Double = 14
    /// How wide an agent's field of view is (radians, the full angle). The default
    /// leaves a blind spot behind it, which is what keeps a flock from folding back
    /// through itself; `.tau` sees all the way round.
    public var viewAngle: Double = 4.6
    /// Where `arrive` starts slowing down (points).
    public var slowingRadius: Double = 140

    /// The radius of the circle `wander` picks its heading from (points): how far the
    /// roaming can swing.
    public var wanderRadius: Double = 26
    /// How far ahead of the agent that circle sits (points): larger is a wider,
    /// lazier arc.
    public var wanderDistance: Double = 62
    /// How fast the wander walk turns (radians per second). Small drifts in long
    /// curves, large is twitchy.
    public var wanderRate: Double = 5.5

    /// How big the flow field's eddies are, as cycles per point: smaller is broader
    /// swirls.
    public var flowScale: Double = 0.0022
    /// How far ahead an agent reads the flow field (points), so it turns into an
    /// eddy rather than after it.
    public var flowLookAhead: Double = 40

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private let kernel: ComputeKernel

    /// Build `count` agents scattered over `bounds`, each seeing others within
    /// `perceptionRadius`. Agents are colored from `colors` in turn (a hue spread by
    /// default, which makes the mixing legible; pass one color for a uniform swarm).
    /// `seed` makes the starting scatter reproducible.
    public init(count: Int, bounds: Rectangle, perceptionRadius: Double,
                colors: [Color] = [], size: Double = 2.0, seed: Int) {
        precondition(count > 0, "Swarm needs a positive count")
        precondition(perceptionRadius > 0, "Swarm needs a positive perceptionRadius")
        self.count = count
        self.perceptionRadius = perceptionRadius
        self.hash = SpatialHash(bounds: bounds, cellSize: perceptionRadius, count: count)

        let palette = colors.isEmpty
            ? (0..<6).map { Color(hue: 0.5 + Double($0) / 18, saturation: 0.55, brightness: 1) }
            : colors
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let origin = hash.origin, world = hash.worldSize
        var seeds: [OllinParticle] = []
        seeds.reserveCapacity(count)
        for i in 0..<count {
            let px = origin.x + Double.random(in: 0..<world.x, using: &rng)
            let py = origin.y + Double.random(in: 0..<world.y, using: &rng)
            let heading = Double.random(in: 0..<(2 * .pi), using: &rng)
            let speed = maxSpeed * Double.random(in: 0.3..<1, using: &rng)
            let c = palette[i % palette.count]
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(px), Float(py)),
                velocity: SIMD2<Float>(Float(cos(heading) * speed), Float(sin(heading) * speed)),
                color: SIMD4<Float>(Float(c.red), Float(c.green), Float(c.blue), Float(c.alpha)),
                size: Float(size), life: 1,
                seedA: Float(heading),   // last heading, so a stopped agent still faces somewhere
                seedB: 0))               // the wander walk's angle
        }
        self.pingpong = PingPong(seeds)
        self.kernel = Swarm.makeKernel()
    }

    /// The current agent state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Record one step: build the neighbor hash over the current agents, then the
    /// steering + integration kernel. Called by `Sketch.updateSwarm`.
    func recordStep(into drawer: Drawer, frameDt: Double) {
        let read = pingpong.read, write = pingpong.write
        // Only the three neighborhood behaviors need to know who is nearby, so a
        // swarm that is purely wandering, seeking, or riding the flow field skips
        // the sort entirely, which is what lets those run at a million agents.
        if separation > 0 || alignment > 0 || cohesion > 0 {
            hash.recordBuild(into: drawer, positions: read)
        }
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count,
            buffers: [read, write, hash.sortedIndices, hash.cellStart, hash.cellCount,
                      hash.gridBuffer],
            params: paramBytes(frameDt: frameDt)))
        pingpong.advance()
    }

    private func paramBytes(frameDt: Double) -> [UInt8] {
        // A hitch must not teleport the swarm, so the step is capped the way the
        // other particle systems cap theirs.
        let dt = frameDt > 0 ? min(frameDt, 1.0 / 30.0) : 1.0 / 60.0
        var p = OllinSwarmParams()
        p.target = SIMD2<Float>(Float(target.x), Float(target.y))
        p.maxSpeed = Float(max(maxSpeed, 0))
        p.minSpeed = Float(min(max(minSpeed, 0), max(maxSpeed, 0)))
        p.maxForce = Float(max(maxForce, 0))
        p.separation = Float(max(separation, 0))
        p.alignment = Float(max(alignment, 0))
        p.cohesion = Float(max(cohesion, 0))
        p.seek = Float(max(seek, 0))
        p.flee = Float(max(flee, 0))
        p.arrive = Float(max(arrive, 0))
        p.wander = Float(max(wander, 0))
        p.flow = Float(max(flow, 0))
        p.separationRadius = Float(min(max(separationRadius, 0), perceptionRadius))
        p.viewCosine = Float(cos(min(max(viewAngle, 0), 2 * .pi) * 0.5))
        p.slowingRadius = Float(max(slowingRadius, 1e-3))
        p.wanderRadius = Float(max(wanderRadius, 0))
        p.wanderDistance = Float(max(wanderDistance, 0))
        p.wanderRate = Float(max(wanderRate, 0))
        p.flowScale = Float(max(flowScale, 0))
        p.flowLookAhead = Float(max(flowLookAhead, 0))
        p.dt = Float(dt)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: p) { bytes.append(contentsOf: $0) }
        return bytes
    }

    /// The steering + integration kernel.
    ///
    /// Every behavior returns `desired − velocity`, so all eight forces are in the same
    /// units and their weights are comparable; the weighted sum is truncated once at
    /// `maxForce`, which is the published way to combine steering behaviors. The three
    /// neighborhood behaviors share one pass over the grid's 3×3 block, since they read
    /// the same neighbors. The neighbor macro, the toroidal helpers, `curlNoise`, and
    /// `hash12` all come from the spliced shader library.
    private static func makeKernel() -> ComputeKernel {
        let source = """
        // The steering move every behavior below is built out of: aim at top speed
        // along `dir`, then subtract the velocity already held.
        static inline float2 ollin_swarm_steer(float2 dir, float2 vel, float maxSpeed) {
            float len = length(dir);
            if (len < 1e-6) { return float2(0.0); }
            return dir * (maxSpeed / len) - vel;
        }

        kernel void ollin_swarm_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid [[buffer(5)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant OllinSwarmParams &s     [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            OllinParticle p = inBuf[id];
            float2 vel = p.velocity;
            float speed = length(vel);
            // A stopped agent still faces the way it last did, so wander and the
            // field of view have a forward to work from.
            float heading = speed > 1e-4 ? atan2(vel.y, vel.x) : p.seedA;
            float2 fwd = float2(cos(heading), sin(heading));

            float2 steering = float2(0.0);

            // ── the three neighborhood behaviors, over one pass of the 3x3 block ──
            if (s.separation > 0.0 || s.alignment > 0.0 || s.cohesion > 0.0) {
                float2 push = float2(0.0);      // separation: sum of 1/r^2 offsets
                float2 sumVel = float2(0.0);    // alignment: neighbors' velocities
                float2 sumOff = float2(0.0);    // cohesion: offsets to the neighbors
                float seen = 0.0;
                float sepR2 = s.separationRadius * s.separationRadius;
                float perR2 = grid.cellSize * grid.cellSize;
                OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
                    if (j == id) { continue; }
                    float2 d = ollin_torus_delta(p.position, inBuf[j].position, grid.worldSize);
                    float r2 = dot(d, d);
                    if (r2 >= perR2 || r2 < 1e-8) { continue; }
                    float r = sqrt(r2);
                    // Outside the field of view is behind it, so it is not seen.
                    if (dot(d / r, fwd) < s.viewCosine) { continue; }
                    if (r2 < sepR2) { push -= d / r2; }   // normalized, then 1/r weighted
                    sumVel += inBuf[j].velocity;
                    sumOff += d;
                    seen += 1.0;
                OLLIN_END_NEIGHBORS

                if (s.separation > 0.0 && dot(push, push) > 1e-12) {
                    steering += ollin_swarm_steer(push, vel, s.maxSpeed) * s.separation;
                }
                if (seen > 0.0) {
                    if (s.alignment > 0.0) {
                        // The neighbors' average velocity is the desired one.
                        steering += (sumVel / seen - vel) * s.alignment;
                    }
                    if (s.cohesion > 0.0) {
                        // The mean offset points at the middle of the neighbors.
                        steering += ollin_swarm_steer(sumOff / seen, vel, s.maxSpeed) * s.cohesion;
                    }
                }
            }

            // ── behaviors that need no neighbors ──
            float2 toTarget = ollin_torus_delta(p.position, s.target, grid.worldSize);
            if (s.seek > 0.0) {
                steering += ollin_swarm_steer(toTarget, vel, s.maxSpeed) * s.seek;
            }
            if (s.flee > 0.0) {
                steering += ollin_swarm_steer(-toTarget, vel, s.maxSpeed) * s.flee;
            }
            if (s.arrive > 0.0) {
                // Ramp the desired speed down inside the slowing radius, so the agent
                // settles on the target instead of orbiting it. The magnitude carries
                // the ramp, which is why this one is not normalized.
                float dist = length(toTarget);
                if (dist > 1e-4) {
                    float wanted = min(s.maxSpeed * dist / s.slowingRadius, s.maxSpeed);
                    steering += (toTarget * (wanted / dist) - vel) * s.arrive;
                } else {
                    steering += -vel * s.arrive;
                }
            }
            if (s.wander > 0.0) {
                // A random *walk* on the angle, not a fresh random force each step:
                // that is what makes the roaming hold a turn instead of twitching.
                float jitter = hash12(float2(float(id) + 0.5, float(u.frameCount) + 0.5)) * 2.0 - 1.0;
                float angle = p.seedB + jitter * s.wanderRate * s.dt;
                p.seedB = angle;
                float2 circleCenter = p.position + fwd * s.wanderDistance;
                float2 spot = circleCenter + float2(cos(heading + angle), sin(heading + angle)) * s.wanderRadius;
                steering += ollin_swarm_steer(spot - p.position, vel, s.maxSpeed) * s.wander;
            }
            if (s.flow > 0.0) {
                // Read the field where the agent is going, not where it is, so it
                // turns into an eddy rather than after it.
                float2 ahead = p.position + fwd * s.flowLookAhead;
                float2 dir = curlNoise(ahead * s.flowScale);
                steering += ollin_swarm_steer(dir, vel, s.maxSpeed) * s.flow;
            }

            // ── locomotion: truncate the summed steering, integrate, truncate again ──
            float mag = length(steering);
            if (mag > s.maxForce) { steering *= s.maxForce / mag; }
            vel += steering * s.dt;
            float newSpeed = length(vel);
            if (newSpeed > s.maxSpeed) { vel *= s.maxSpeed / newSpeed; newSpeed = s.maxSpeed; }
            // A floor on speed, if one was asked for, so a crowded agent keeps going
            // instead of stalling into a wall the rest of the swarm jams against.
            if (s.minSpeed > 0.0 && newSpeed < s.minSpeed) {
                vel = newSpeed > 1e-4 ? vel * (s.minSpeed / newSpeed) : fwd * s.minSpeed;
                newSpeed = s.minSpeed;
            }
            p.position += vel * s.dt;
            p.velocity = vel;
            if (newSpeed > 1e-4) { p.seedA = atan2(vel.y, vel.x); }

            // Toroidal wrap, matching how the neighbor grid wraps.
            float2 rel = p.position - grid.origin;
            rel = rel - grid.worldSize * floor(rel / grid.worldSize);
            p.position = grid.origin + rel;
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_swarm_step", source)
    }
}
