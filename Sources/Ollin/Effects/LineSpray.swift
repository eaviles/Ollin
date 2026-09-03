import Foundation
import simd
import COllinShaders

/// One line of light for a `LineSpray`: a segment in world space with a color at
/// each end, an intensity, and a weight. A pass scatters points along it, each
/// point carrying the line's share of light, so over many passes the line adds up
/// to exactly `color × intensity` however many points draw it.
public struct SprayLine: Sendable, Equatable {
    /// The segment's ends, world space.
    public var start: Vector3
    public var end: Vector3
    /// The tone at each end (an sRGB `Color`, linearized before it becomes light);
    /// `endColor` defaults to `color`.
    public var color: Color
    public var endColor: Color
    /// Light emitted per pass, in linear units, at each end: the multiplier that
    /// lets a line shine well past white. `endIntensity` defaults to `intensity`.
    public var intensity: Double
    public var endIntensity: Double
    /// Under length sampling, this line's share of the pass's points relative to
    /// its length (2 draws twice the points, at half the light each). Ignored by
    /// per-line sampling.
    public var weight: Double

    public init(from start: Vector3, to end: Vector3,
                color: Color = .white, endColor: Color? = nil,
                intensity: Double = 1, endIntensity: Double? = nil,
                weight: Double = 1) {
        self.start = start
        self.end = end
        self.color = color
        self.endColor = endColor ?? color
        self.intensity = intensity
        self.endIntensity = endIntensity ?? intensity
        self.weight = max(0, weight)
    }

    /// The segment's length in world units.
    public var length: Double { start.distance(to: end) }
}

/// The lens a `LineSpray` scatters through: how far the plane of focus sits, how
/// fast the blur grows away from it, and how the light fades with distance.
///
/// Every sample is pushed to a random spot inside a ball whose radius is
/// `strength × defocus^power`, never smaller than `minSize`, where `defocus` is
/// the sample's distance from the focal plane along the camera's axis. Summing
/// millions of those samples *is* the blur: a line on the focal plane stays
/// crisp, one far from it dissolves, and nothing is filtered afterward.
public struct Bokeh: Sendable, Equatable {
    /// Distance from the camera to the plane of focus, along the view axis, in
    /// world units.
    public var focalDistance: Double
    /// The ball's radius per unit of defocus (world units per world unit): the
    /// aperture, in effect. 0 turns the lens into a pinhole.
    public var strength: Double
    /// The smallest ball a sample scatters in, world units, so a line exactly in
    /// focus still has a body rather than a hairline.
    public var minSize: Double
    /// The exponent the defocus distance takes before `strength` scales it. 1
    /// grows the blur in proportion to distance; 1.5 keeps the region near focus
    /// crisper and lets far things dissolve faster.
    public var power: Double
    /// How fast light fades away from the focal plane: each sample's light is
    /// multiplied by `exp(-attenuation × defocus)`. 0 keeps every sample at full
    /// light.
    public var attenuation: Double

    public init(focalDistance: Double, strength: Double = 0.05, minSize: Double = 0.015,
                power: Double = 1, attenuation: Double = 0) {
        self.focalDistance = max(0, focalDistance)
        self.strength = max(0, strength)
        self.minSize = max(0, minSize)
        self.power = max(0, power)
        self.attenuation = max(0, attenuation)
    }
}

/// Lines of light rendered as depth of field: the sandpainting lens.
///
/// Give it an array of `SprayLine`s once. Each frame, `drawLineSpray` scatters a
/// pass of points along them on the GPU (a fresh spot on each line, then a fresh
/// spot in the bokeh ball around it, projected through the sketch's camera), adds
/// them as light into an `Accumulator`, and the running mean converges into a
/// photograph with a real lens: lines on the focal plane sharp, the rest
/// dissolved into bokeh, no blur filter anywhere. Print it with `developed`.
///
/// ```swift
/// var spray: LineSpray!
/// override func setup() {
///     spray = makeLineSpray(lines, sampling: .byLength(pointsPerPass: 50_000), passesPerFrame: 5)
///     spray.bokeh = Bokeh(focalDistance: 49, strength: 0.095)
/// }
/// override func draw() {
///     camera(.orbiting(radius: 49, azimuth: -0.46, elevation: -0.42, fieldOfView: 20 * .pi / 180))
///     drawLineSpray(spray)                                   // one frame of passes
///     drawImage(spray.developed(exposure: 500, ground: Color(hex: 0x151010)).image, 0, 0)
/// }
/// ```
///
/// Moving the camera or turning the lens restarts the average on its own: the
/// samples drawn before no longer describe the picture. `passes` says how far
/// the picture has converged.
///
/// Persistent, like the `Accumulator` it owns: create it once in `setup()` and
/// hold it.
@MainActor
public final class LineSpray {

    /// How a pass distributes its points over the lines.
    public enum Sampling: Sendable, Equatable {
        /// Every line gets the same number of points per pass, whatever its length.
        case perLine(Int)
        /// A pass's `pointsPerPass` points are shared out by length (times each
        /// line's `weight`), at least one per line, so a long line is drawn as
        /// densely as a short one.
        case byLength(pointsPerPass: Int)
    }

    /// The lens. Changing it restarts the average.
    public var bokeh: Bokeh

    /// The diameter, in canvas points, each sample's light spreads over. The total
    /// light is the same at any size (a wider point is dimmer), so this softens
    /// the grain without changing the exposure. 1 is the reference's one-pixel
    /// point and the cheapest to draw.
    public var pointSize: Double = 1

    /// Passes drawn per frame: more converge faster and cost proportionally.
    public var passesPerFrame: Int

    /// The lines, as given.
    public private(set) var lines: [SprayLine]

    /// How the points are shared out.
    public let sampling: Sampling

    /// The running mean the passes converge into.
    public let accumulator: Accumulator

    /// Passes accumulated so far (`accumulator.passes`).
    public var passes: Int { accumulator.passes }

    /// The running mean as an `Image`, linear light: the picture before printing.
    public var image: Image { accumulator.image }

    /// The mean printed: scaled by `exposure`, rolled off through the Reinhard
    /// curve, and laid on `ground` (see `Filter.develop(exposure:ground:)`).
    public func developed(exposure: Double, ground: Color = .black) -> RenderTarget {
        accumulator.developed(exposure: exposure, ground: ground)
    }

    /// Start the average over. Called for you when the camera, the lens, the
    /// lines, or the point size change.
    public func reset() { accumulator.reset() }

    /// Replace the lines (a scene that moves between frames). Restarts the average.
    public func setLines(_ lines: [SprayLine]) {
        self.lines = lines
        rebuild()
        reset()
    }

    // The GPU side: the line records, one line index per point, and the points.
    private var lineBuffer: ComputeBuffer<OllinSprayLine>?
    private var pointLines: ComputeBuffer<UInt32>?
    private var pointsPerPass = 0
    private var points: PingPong<OllinParticle>?
    private var pointsAllocated = 0
    private var lastSignature: Signature?

    /// What a pass depends on; a change to any of it restarts the average.
    private struct Signature: Equatable {
        var camera: Camera3D
        var bokeh: Bokeh
        var pointSize: Double
        var width: Int, height: Int
        var lines: Int
    }

    init(lines: [SprayLine], sampling: Sampling, passesPerFrame: Int, bokeh: Bokeh,
         accumulator: Accumulator) {
        self.lines = lines
        self.sampling = sampling
        self.passesPerFrame = max(1, passesPerFrame)
        self.bokeh = bokeh
        self.accumulator = accumulator
        rebuild()
    }

    /// Lay the lines out for the GPU: each line's record with its share, and the
    /// point-to-line table a thread reads to find its line.
    private func rebuild() {
        guard !lines.isEmpty else {
            lineBuffer = nil; pointLines = nil; pointsPerPass = 0
            return
        }
        let counts = LineSpray.pointCounts(for: lines, sampling: sampling)
        var records: [OllinSprayLine] = []
        records.reserveCapacity(lines.count)
        var table: [UInt32] = []
        table.reserveCapacity(counts.reduce(0, +))
        for (i, line) in lines.enumerated() {
            let n = counts[i]
            let a = line.color.linearRGBA, b = line.endColor.linearRGBA
            records.append(OllinSprayLine(
                start: SIMD4<Float>(Float(line.start.x), Float(line.start.y), Float(line.start.z),
                                    1 / Float(n)),
                end: SIMD4<Float>(Float(line.end.x), Float(line.end.y), Float(line.end.z), 0),
                startColor: SIMD4<Float>(a.x, a.y, a.z, 0) * Float(line.intensity),
                endColor: SIMD4<Float>(b.x, b.y, b.z, 0) * Float(line.endIntensity)))
            table.append(contentsOf: repeatElement(UInt32(i), count: n))
        }
        lineBuffer = ComputeBuffer(records)
        pointLines = ComputeBuffer(table)
        pointsPerPass = table.count
    }

    /// Points per line for one pass: the same for every line, or shared by length.
    static func pointCounts(for lines: [SprayLine], sampling: Sampling) -> [Int] {
        switch sampling {
        case .perLine(let n):
            return Array(repeating: max(1, n), count: lines.count)
        case .byLength(let total):
            let weighted = lines.map { $0.length * $0.weight }
            let sum = weighted.reduce(0, +)
            guard sum > 0 else { return Array(repeating: 1, count: lines.count) }
            let perUnit = Double(max(1, total)) / sum
            return weighted.map { max(1, Int((perUnit * $0).rounded(.down))) }
        }
    }

    /// The scatter kernel: one thread per point per pass. Reads its line, picks a
    /// spot along it and a spot in the bokeh ball around that spot in camera
    /// space, fades by attenuation, projects through the camera, and writes the
    /// particle the light path draws.
    static let kernel = ComputeKernel(entry: "ollin_line_spray", """
        struct OllinSprayParams {
            OllinCameraMatrices camera;
            float4 lens;   // x focal distance, y strength, z minimum size, w power
            float4 misc;   // x attenuation, y point size, z points per pass, w seed
        };

        kernel void ollin_line_spray(device const OllinSprayLine *lines [[buffer(0)]],
                                     device const uint *lineOf [[buffer(1)]],
                                     device OllinParticle *out [[buffer(2)]],
                                     constant OllinComputeUniforms &u [[buffer(10)]],
                                     constant OllinSprayParams &p [[buffer(11)]],
                                     uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            uint perPass = max(uint(p.misc.z), 1u);
            OllinSprayLine line = lines[lineOf[id % perPass]];

            // Fresh randomness per point per frame, from small seed parts.
            float3 seed = float3(float(id & 4095u), float(id >> 12u), p.misc.w);
            float t = hash13(seed);
            float3 world = mix(line.start.xyz, line.end.xyz, t);
            float3 light = mix(line.startColor.xyz, line.endColor.xyz, t) * line.start.w;

            // Into camera space; the defocus is measured along the view axis.
            float3 eye = (p.camera.view * float4(world, 1.0)).xyz;
            float defocus = abs(-eye.z - p.lens.x);
            float radius = max(pow(defocus, p.lens.w) * p.lens.y, p.lens.z);
            eye += ballSample(seed + float3(7.3, 1.9, 4.1)) * radius;
            light *= exp(-defocus * p.misc.x);

            float4 screen = ollin_project_eye(p.camera, eye, u.resolution);
            OllinParticle o;
            o.velocity = float2(0.0);
            o.life = 1.0;
            o.seedA = 0.0;
            o.seedB = 0.0;
            if (screen.w <= 0.0) {          // behind the camera: draw nothing
                o.position = float2(-16.0);
                o.size = 0.0;
                o.color = float4(0.0);
                out[id] = o;
                return;
            }
            // A point's whole light lands in its disc: alpha spreads it over the
            // disc's area in canvas points, so the exposure is the same at any size.
            float size = max(p.misc.y, 1e-3);
            o.position = screen.xy;
            o.size = size;
            o.color = float4(light, 1.27323954474 / (size * size));
            out[id] = o;
        }
        """)

    /// One frame: reset if anything the picture depends on changed, scatter
    /// `passesPerFrame` passes of points, and add them into the accumulator.
    func record(into drawer: Drawer, camera: Camera3D, width: Double, height: Double, seed: Float) {
        guard let lineBuffer, let pointLines, pointsPerPass > 0 else { return }
        let signature = Signature(camera: camera, bokeh: bokeh, pointSize: pointSize,
                                  width: Int(width), height: Int(height), lines: lines.count)
        if signature != lastSignature {
            lastSignature = signature
            accumulator.reset()
        }
        let count = pointsPerPass * passesPerFrame
        if points == nil || pointsAllocated != count {
            points = PingPong(count: count)
            pointsAllocated = count
        }
        guard let points else { return }

        var params = ComputeParams()
        params.append(camera: camera, aspect: height > 0 ? width / height : 1)
        params.append(SIMD4<Float>(Float(bokeh.focalDistance), Float(bokeh.strength),
                                   Float(bokeh.minSize), Float(bokeh.power)))
        params.append(SIMD4<Float>(Float(bokeh.attenuation), Float(pointSize),
                                   Float(pointsPerPass), seed))
        let write = points.write
        drawer.recordDispatch(RecordedDispatch(
            kernel: LineSpray.kernel, threadCount: count,
            buffers: [lineBuffer, pointLines, write], params: params.bytes))
        points.advance()
        drawer.withAccumulator(accumulator, passes: passesPerFrame) {
            drawer.blendMode(.add)
            drawer.recordParticles(write, count: count, style: .light)
        }
    }
}
