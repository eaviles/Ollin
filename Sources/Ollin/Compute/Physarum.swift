import Foundation
import simd
import COllinShaders   // OllinParticle

/// Physarum: thousands of tiny agents that lay down a chemical trail and steer toward
/// it, and out of that stigmergy grow the branching transport networks of slime mold
/// (Jeff Jones, *Characteristics of Pattern Formation and Evolution in Approximations
/// of Physarum Transport Networks*, 2010). Each agent sniffs the trail ahead of it
/// (three sensors: left, center, right), turns toward the strongest, steps forward,
/// and deposits a little trail where it lands; the trail map then blurs and fades a
/// touch each step. No agent talks to another directly, yet veins, sheets, and
/// foraging fronts appear.
///
/// This is the trail-field half of the artificial-life set (it needs no neighbor
/// search, unlike `ParticleLife`/`PPS`). The agents live on the GPU; you draw the
/// trail:
///
/// ```swift
/// var slime: Physarum!
/// override func setup() { slime = makePhysarum(agents: 200_000, resolution: 1024) }
/// override func draw() {
///     updatePhysarum(slime)
///     drawImage(slime.image, in: Rectangle(x: 0, y: 0, width: width, height: height))
/// }
/// ```
///
/// The look lives in the sensing/movement parameters (`senseAngle`, `turnAngle`,
/// `senseDistance`, `stepSize`) and the trail's `evaporation`; the defaults are Jones'
/// (22.5° / 45° / 9 / 1, evaporation 0.1). Deposit races are avoided with an atomic
/// deposit grid, so the trail is well-defined; the agent motion is still chaotic, so
/// there's no frame-exact export guarantee.
@MainActor
public final class Physarum {
    /// Number of agents.
    public let agents: Int
    /// Trail map width in texels (the sim resolution).
    public let width: Int
    /// Trail map height in texels.
    public let height: Int

    /// Angle between the center sensor and each side sensor, in degrees (Jones' SA).
    public var senseAngle: Double = 22.5
    /// How far an agent turns toward the stronger side each step, in degrees (RA).
    public var turnAngle: Double = 45
    /// How far ahead the sensors sample, in texels (SO).
    public var senseDistance: Double = 9
    /// How far an agent moves each step, in texels (SS).
    public var stepSize: Double = 1
    /// Fraction of the trail that dissipates each step (0…1). Higher fades faster.
    public var evaporation: Double = 0.1
    /// Display gain: how quickly trail strength saturates to white.
    public var glow: Double = 1.0

    private let agentBuffer: ComputeBuffer<OllinParticle>
    private let trail: PingPongTexture
    private let deposit: ComputeBuffer<UInt32>
    private let display: ComputeTexture

    private let clearKernel: ComputeKernel
    private let agentKernel: ComputeKernel
    private let diffuseKernel: ComputeKernel
    private let colorizeKernel: ComputeKernel

    /// The trail map as an `Image` for `drawImage` (colorized from the latest field).
    public var image: Image { display.image }

    /// Build `agents` agents on a `resolution`×`resolution` trail map, positions and
    /// headings randomized from `seed`. Use `init(agents:width:height:seed:)` for a
    /// non-square map.
    public convenience init(agents: Int, resolution: Int, seed: Int) {
        self.init(agents: agents, width: resolution, height: resolution, seed: seed)
    }

    /// Build `agents` agents on a `width`×`height` trail map.
    public init(agents: Int, width: Int, height: Int, seed: Int) {
        precondition(agents > 0, "Physarum needs a positive agent count")
        precondition(width > 0 && height > 0, "Physarum needs a positive resolution")
        self.agents = agents
        self.width = width
        self.height = height

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        var seeds: [OllinParticle] = []
        seeds.reserveCapacity(agents)
        // Start the agents in a central disc facing outward, the classic seeding that
        // grows a radial network (rather than a uniform field that just thickens).
        let cx = Double(width) / 2, cy = Double(height) / 2
        let spawnR = Double(min(width, height)) * 0.30
        for _ in 0..<agents {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let rr = spawnR * Double.random(in: 0..<1, using: &rng).squareRoot()
            let px = cx + cos(a) * rr, py = cy + sin(a) * rr
            let heading = Double.random(in: 0..<(2 * .pi), using: &rng)
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(px), Float(py)),
                velocity: SIMD2<Float>(0, 0),
                color: SIMD4<Float>(1, 1, 1, 1),
                size: 1, life: 1, seedA: Float(heading), seedB: 0))
        }
        self.agentBuffer = ComputeBuffer(seeds)
        self.trail = PingPongTexture(width: width, height: height, format: .r32Float)
        self.deposit = ComputeBuffer(count: width * height)
        self.display = ComputeTexture(width: width, height: height, format: .rgba16Float)

        self.clearKernel = ComputeKernel(entry: "ollin_physarum_clear", Physarum.source)
        self.agentKernel = ComputeKernel(entry: "ollin_physarum_agents", Physarum.source)
        self.diffuseKernel = ComputeKernel(entry: "ollin_physarum_diffuse", Physarum.source)
        self.colorizeKernel = ComputeKernel(entry: "ollin_physarum_colorize", Physarum.source)
    }

    /// Record one step: clear the deposit grid, run the agents (sense, steer, move,
    /// deposit), diffuse and decay the trail, then colorize it for display. Called by
    /// `Sketch.updatePhysarum`.
    func recordStep(into drawer: Drawer) {
        let cells = width * height
        // 1. Clear the atomic deposit grid.
        drawer.recordDispatch(RecordedDispatch(
            kernel: clearKernel, threadCount: cells,
            buffers: [nil, nil, deposit], params: []))
        // 2. Agents: sense the current trail, steer, move, deposit. A 1-D dispatch that
        //    also binds the trail texture, so it uses the 2-D dispatch init (height 1).
        let senseParams = SIMD4<Float>(
            Float(senseAngle * .pi / 180), Float(senseDistance),
            Float(turnAngle * .pi / 180), Float(stepSize))
        drawer.recordDispatch(RecordedDispatch(
            kernel: agentKernel, gridWidth: agents, gridHeight: 1,
            textures: [trail.read], buffers: [agentBuffer, nil, deposit],
            params: packed(senseParams)))
        // 3. Diffuse (3×3 mean) + add deposit + decay, into the next trail texture.
        let read = trail.read, write = trail.write
        drawer.recordDispatch(RecordedDispatch(
            kernel: diffuseKernel, gridWidth: width, gridHeight: height,
            textures: [read, write], buffers: [nil, nil, deposit],
            params: packed(SIMD4<Float>(Float(evaporation), 0, 0, 0))))
        trail.advance()
        // 4. Colorize the fresh trail into the display texture.
        drawer.recordDispatch(RecordedDispatch(
            kernel: colorizeKernel, gridWidth: width, gridHeight: height,
            textures: [trail.read, display], buffers: [],
            params: packed(SIMD4<Float>(Float(glow), 0, 0, 0))))
    }

    private func packed(_ v: SIMD4<Float>) -> [UInt8] {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: v) { bytes.append(contentsOf: $0) }
        return bytes
    }

    /// The four kernels, sharing one compiled source. `DEPOSIT` (the per-step trail a
    /// landing agent adds) and `SCALE` (the atomic fixed-point factor) are constants;
    /// the trail dimensions come from the texture, the live parameters from `custom`.
    private static let source = """
    constant float DEPOSIT = 1.0;
    constant float SCALE = 1024.0;

    // Zero the atomic deposit grid.
    kernel void ollin_physarum_clear(
        device uint *deposit [[buffer(2)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        deposit[id] = 0u;
    }

    // Sample the trail at a texel-space position, bilinearly and toroidally. Bilinear
    // (not nearest) is load-bearing: point sampling quantizes the sensed gradient to
    // the grid, and in the low-trail region an agent forages into, that bias steers the
    // escaping agents onto the cardinal axes (the four spurs). Smooth sampling removes
    // it.
    static inline float ollin_phys_sense(texture2d<float, access::read> trail, float2 p) {
        int W = int(trail.get_width()), H = int(trail.get_height());
        float2 c = p - 0.5;                       // texel centers sit at +0.5
        float2 f = floor(c);
        float2 t = c - f;
        int x0 = ((int(f.x) % W) + W) % W, x1 = ((int(f.x) + 1) % W + W) % W;
        int y0 = ((int(f.y) % H) + H) % H, y1 = ((int(f.y) + 1) % H + H) % H;
        float c00 = trail.read(uint2(x0, y0)).r, c10 = trail.read(uint2(x1, y0)).r;
        float c01 = trail.read(uint2(x0, y1)).r, c11 = trail.read(uint2(x1, y1)).r;
        return mix(mix(c00, c10, t.x), mix(c01, c11, t.x), t.y);
    }

    // Agents: sense three points ahead, steer toward the strongest, step, deposit.
    kernel void ollin_physarum_agents(
        device OllinParticle *agents [[buffer(0)]],
        device atomic_uint   *deposit [[buffer(2)]],
        texture2d<float, access::read> trail [[texture(0)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        constant float4 &prm [[buffer(11)]],
        uint2 gid [[thread_position_in_grid]]) {
        uint id = gid.x;
        if (id >= u.particleCount) { return; }
        float senseAngle = prm.x, senseDist = prm.y, turnAngle = prm.z, stepSize = prm.w;
        float W = float(trail.get_width()), H = float(trail.get_height());

        OllinParticle a = agents[id];
        float phi = a.seedA;
        float2 pos = a.position;

        float2 fwd = float2(cos(phi), sin(phi));
        float2 lft = float2(cos(phi + senseAngle), sin(phi + senseAngle));
        float2 rgt = float2(cos(phi - senseAngle), sin(phi - senseAngle));
        float F  = ollin_phys_sense(trail, pos + fwd * senseDist);
        float FL = ollin_phys_sense(trail, pos + lft * senseDist);
        float FR = ollin_phys_sense(trail, pos + rgt * senseDist);

        if (F > FL && F > FR) {
            // keep heading
        } else if (F < FL && F < FR) {
            float bit = hash12(float2(float(id), float(u.frameCount)));
            phi += (bit > 0.5) ? turnAngle : -turnAngle;   // random turn out of a dead end
        } else if (FL > FR) {
            phi += turnAngle;
        } else if (FR > FL) {
            phi -= turnAngle;
        }

        // Small motor noise. Load-bearing: with none, an agent in the empty region it
        // forages into (all three sensors read equal) keeps its heading exactly and
        // flies straight, and those coherent parallel escapes self-reinforce on the
        // square lattice into cardinal-axis spurs (diagonal ones stair-step and don't).
        // A per-step jitter turns the ballistic escape into a wander, so the foraging
        // front spreads evenly; the network's strong gradients swamp it, so veins stay
        // crisp.
        phi += (hash12(float2(float(id), float(u.frameCount) * 0.017 + 1.3)) - 0.5) * 0.7;

        fwd = float2(cos(phi), sin(phi));
        pos += fwd * stepSize;
        // Toroidal wrap in texel space.
        pos.x = fmod(fmod(pos.x, W) + W, W);
        pos.y = fmod(fmod(pos.y, H) + H, H);

        a.position = pos;
        a.seedA = phi;
        agents[id] = a;

        // Deposit at the landing texel (atomic fixed-point add avoids the write race).
        uint tx = uint(clamp(pos.x, 0.0, W - 1.0));
        uint ty = uint(clamp(pos.y, 0.0, H - 1.0));
        atomic_fetch_add_explicit(&deposit[ty * uint(W) + tx],
                                  uint(DEPOSIT * SCALE), memory_order_relaxed);
    }

    // Diffuse the previous trail, add this step's deposit, then decay. The blur is a
    // 3x3 Gaussian (separable 1-2-1) rather than a plain box mean: a box filter spreads
    // faster along the axes than the diagonals, and over many steps that channels the
    // network into cardinal-direction spurs; the Gaussian is near-isotropic.
    kernel void ollin_physarum_diffuse(
        texture2d<float, access::read>  src [[texture(0)]],
        texture2d<float, access::write> dst [[texture(1)]],
        device const uint *deposit [[buffer(2)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        constant float4 &prm [[buffer(11)]],
        uint2 gid [[thread_position_in_grid]]) {
        int W = int(src.get_width()), H = int(src.get_height());
        if (int(gid.x) >= W || int(gid.y) >= H) { return; }
        float evaporation = prm.x;
        float acc = 0.0;
        for (int dy = -1; dy <= 1; ++dy) {
            float wy = (dy == 0) ? 2.0 : 1.0;
            for (int dx = -1; dx <= 1; ++dx) {
                float wx = (dx == 0) ? 2.0 : 1.0;
                int x = ((int(gid.x) + dx) % W + W) % W;
                int y = ((int(gid.y) + dy) % H + H) % H;
                acc += src.read(uint2(x, y)).r * wx * wy;   // 1-2-1 weights, sum 16
            }
        }
        float blurred = acc / 16.0;
        float dep = float(deposit[gid.y * uint(W) + gid.x]) / SCALE;
        float v = (blurred + dep) * (1.0 - evaporation);
        dst.write(float4(v, 0, 0, 1), gid);
    }

    // Map trail strength to a warm bioluminescent glow (straight sRGB out).
    kernel void ollin_physarum_colorize(
        texture2d<float, access::read>  src [[texture(0)]],
        texture2d<float, access::write> dst [[texture(1)]],
        constant float4 &prm [[buffer(11)]],
        uint2 gid [[thread_position_in_grid]]) {
        float trail = src.read(gid).r;
        float t = 1.0 - exp(-trail * max(prm.x, 1e-3));
        float3 rgb = mix(float3(0.02, 0.01, 0.05), float3(0.95, 0.55, 0.15),
                         smoothstep(0.0, 0.55, t));
        rgb = mix(rgb, float3(1.0, 0.98, 0.9), smoothstep(0.55, 1.0, t));
        dst.write(float4(rgb, 1.0), gid);
    }
    """
}
