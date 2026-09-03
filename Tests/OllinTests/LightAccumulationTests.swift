import CoreGraphics
import Foundation
import Testing
import simd
import COllinShaders
@testable import Ollin

/// Light accumulation: the radiometric particle style, the running mean an
/// `Accumulator` keeps, the single-precision layers, the print filter, the camera a
/// kernel projects through, and the ball scatter. The CPU checks run everywhere;
/// the renders are Metal-gated and soft-skip without a GPU.
@Suite
@MainActor
struct LightAccumulationTests {

    // MARK: CPU

    /// `append(camera:aspect:)` writes the view then the projection, 128 bytes, as
    /// the shared `OllinCameraMatrices` a kernel reads.
    @Test func cameraParamsPackTheMatrices() {
        let camera = Camera3D.perspective(eye: Vector3(3, 4, 12), target: Vector3(0, 1, 0))
        var params = ComputeParams()
        params.append(camera: camera, aspect: 1.5)
        #expect(params.bytes.count == 128)
        let packed = params.bytes.withUnsafeBytes { $0.load(as: OllinCameraMatrices.self) }
        #expect(packed.view == camera.viewMatrix)
        #expect(packed.projection == camera.projectionMatrix(aspect: 1.5))
        #expect(camera.matrices(aspect: 1.5).view == camera.viewMatrix)
        // Anything appended after it lands past the matrices, so a kernel's struct
        // can begin with the camera and carry its own fields after.
        params.append(SIMD4<Float>(1, 2, 3, 4))
        #expect(params.bytes.count == 144)
    }

    /// Length sampling shares a pass's points by length times weight, at least
    /// one per line; per-line sampling gives every line the same count.
    @Test func lineSprayPointCounts() {
        let lines = [
            SprayLine(from: .zero, to: Vector3(1, 0, 0)),
            SprayLine(from: .zero, to: Vector3(0, 3, 0)),
            SprayLine(from: .zero, to: Vector3(0, 0, 1), weight: 2),
            SprayLine(from: Vector3(1, 1, 1), to: Vector3(1, 1, 1)),    // zero length
        ]
        #expect(LineSpray.pointCounts(for: lines, sampling: .perLine(25)) == [25, 25, 25, 25])
        // Weighted lengths 1, 3, 2, 0 over a hundred points: 16, 50, 33, and one.
        #expect(LineSpray.pointCounts(for: lines, sampling: .byLength(pointsPerPass: 100)) == [16, 50, 33, 1])
    }

    /// A spray line's optional end values default to the start's.
    @Test func sprayLineDefaults() {
        let line = SprayLine(from: .zero, to: Vector3(1, 0, 0), color: .orange, intensity: 3)
        #expect(line.endColor == .orange)
        #expect(line.endIntensity == 3)
        #expect(line.weight == 1)
        #expect(line.length == 1)
    }

    /// The develop filter is one fragment pass carrying the exposure and the
    /// ground as display components.
    @Test func developIsOnePass() {
        let pass = Filter.develop(exposure: 2, ground: Color(red: 0.1, green: 0.2, blue: 0.3))
            .singlePass(width: 8, height: 8, resolve: { $0 })
        #expect(pass?.fragment == "ollin_fx_develop")
        #expect(pass?.params.first == SIMD4<Float>(2, 0, 0, 0))
        #expect(pass?.params.last == SIMD4<Float>(0.1, 0.2, 0.3, 1))
    }

    // MARK: Metal-gated

    /// The `.light` style deposits each particle's area, wherever it lands: five
    /// thousand one-pixel discs at random positions sum to their area times
    /// their alpha, half-pixel discs to a quarter of that, and the default `.marks`
    /// style (perceptual coverage, for ink) lands well above the light sum.
    @Test(.enabled(if: Snapshot.hasMetal))
    func lightParticlesDepositTheirArea() throws {
        let count = 5000
        let alpha: Float = 0.25
        func total(size: Float, style: ParticleStyle) throws -> Double {
            let sketch = ParticleDepositSketch(count: count, size: size, alpha: alpha, style: style)
            let image = try #require(OllinApp.image(of: sketch, frame: 0))
            return linearSum(of: image)
        }
        let expected = Double(count) * Double.pi / 4 * Double(alpha)
        let onePixel = try total(size: 1, style: .light)
        let halfPixel = try total(size: 0.5, style: .light)
        let twoPixel = try total(size: 2, style: .light)
        let marks = try total(size: 1, style: .marks)
        #expect(abs(onePixel - expected) / expected < 0.08, "one-pixel light: \(onePixel) vs \(expected)")
        #expect(abs(halfPixel / onePixel - 0.25) < 0.05, "half-pixel light: \(halfPixel / onePixel)")
        #expect(abs(twoPixel / onePixel - 4) < 0.4, "two-pixel light: \(twoPixel / onePixel)")
        #expect(marks > onePixel * 1.3, "marks \(marks) should read brighter than light \(onePixel)")
    }

    /// A one-pixel light particle lands in the texel that holds it (a neighbor or
    /// three may share it under multisampling) and deposits its whole area.
    @Test(.enabled(if: Snapshot.hasMetal))
    func oneLightPixelLightsOnePixel() throws {
        let sketch = ParticleDepositSketch(count: 1, size: 1, alpha: 1, style: .light,
                                           fixed: SIMD2<Float>(100.3, 200.7))
        let image = try #require(OllinApp.image(of: sketch, frame: 0))
        let lit = litPixels(of: image)
        #expect(lit.count >= 1 && lit.count <= 4, "lit texels: \(lit.count)")
        #expect(lit.allSatisfy { abs($0.x - 100) <= 1 && abs($0.y - 200) <= 1 })
        let sum = lit.reduce(0.0) { $0 + $1.value }
        #expect(abs(sum - Double.pi / 4) < 0.08, "deposit \(sum)")
    }

    /// An accumulator hands back the mean: six passes of the same faint square read
    /// the same as one, the count matches, `passes:` divides, and a reset restarts.
    @Test(.enabled(if: Snapshot.hasMetal))
    func accumulatorHoldsTheMean() throws {
        let one = AccumulatorSketch()
        let first = try #require(OllinApp.image(of: one, frame: 0))
        #expect(abs(centerLinear(of: first) - 0.2) < 0.02)
        #expect(one.light.passes == 1)

        let six = AccumulatorSketch()
        let sixth = try #require(OllinApp.image(of: six, frame: 5))
        #expect(abs(centerLinear(of: sixth) - 0.2) < 0.02, "six passes should still read 0.2, not their sum")
        #expect(six.light.passes == 6)

        let doubled = AccumulatorSketch()
        doubled.passesPerBlock = 2
        let half = try #require(OllinApp.image(of: doubled, frame: 2))
        #expect(abs(centerLinear(of: half) - 0.1) < 0.02, "two passes per block halve the mean")

        // `frameCount` is 1 on the first draw, so frame 5 is the sixth draw and a
        // reset at the start of the third leaves the third through sixth: four.
        let restarted = AccumulatorSketch()
        restarted.resetAtFrame = 3
        _ = OllinApp.image(of: restarted, frame: 5)
        #expect(restarted.light.passes == 4)
    }

    /// A feedback layer summing a step under half float's spacing stalls at
    /// `.float16` and keeps climbing at `.float32`.
    @Test(.enabled(if: Snapshot.hasMetal))
    func singlePrecisionFeedbackKeepsAdding() throws {
        let half = FeedbackSumSketch(precision: .float16)
        let halfImage = try #require(OllinApp.image(of: half, frame: 199))
        let single = FeedbackSumSketch(precision: .float32)
        let singleImage = try #require(OllinApp.image(of: single, frame: 199))
        let stalled = centerLinear(of: halfImage)
        let climbed = centerLinear(of: singleImage)
        #expect(abs(stalled - 0.5) < 0.01, "half float should hold 0.5, read \(stalled)")
        #expect(abs(climbed - 0.54) < 0.01, "single float should reach 0.54, read \(climbed)")
    }

    /// The develop filter prints the reference recipe: exposure, Reinhard, then the
    /// ground added as a display value.
    @Test(.enabled(if: Snapshot.hasMetal))
    func developPrintsTheRecipe() throws {
        let sketch = DevelopSketch()
        let image = try #require(OllinApp.image(of: sketch, frame: 0))
        // Linear 0.5 × exposure 2 = 1 → 1 / (1 + 1) = 0.5, plus a 0.1 ground → 0.6 display.
        let byte = centerByte(of: image)
        #expect(abs(Double(byte) - 0.6 * 255) <= 2, "printed \(byte)")
    }

    /// A kernel projecting through the packed camera lands where the sketch's own
    /// `project(_:)` puts the point, through the multi-buffer dispatch.
    @Test(.enabled(if: Snapshot.hasMetal))
    func kernelProjectsLikeTheSketch() throws {
        let sketch = ProjectionSketch()
        _ = OllinApp.image(of: sketch, frame: 0)
        let particles = try #require(sketch.out.snapshot())
        for (i, world) in sketch.points.enumerated() {
            let expected = try #require(sketch.expected[i])
            let got = particles[i].position
            #expect(abs(Double(got.x) - expected.x) < 0.05 && abs(Double(got.y) - expected.y) < 0.05,
                    "point \(i): kernel \(got) vs sketch \(expected)")
        }
        // A point behind the camera is marked dead (size 0), not drawn somewhere.
        #expect(particles[sketch.points.count].size == 0)
    }

    /// `ballSample` is uniform over the ball: every draw inside it, a mean radius of
    /// three quarters, an eighth of the draws inside the half-radius ball, and no
    /// bias in any axis.
    @Test(.enabled(if: Snapshot.hasMetal))
    func ballSampleIsUniform() throws {
        let sketch = BallSampleSketch()
        _ = OllinApp.image(of: sketch, frame: 0)
        let samples = try #require(sketch.out.snapshot())
        let radii = samples.map { Double(simd_length(SIMD3($0.x, $0.y, $0.z))) }
        #expect(radii.allSatisfy { $0 <= 1.0001 })
        let meanRadius = radii.reduce(0, +) / Double(radii.count)
        #expect(abs(meanRadius - 0.75) < 0.02, "mean radius \(meanRadius)")
        let inner = Double(radii.filter { $0 < 0.5 }.count) / Double(radii.count)
        #expect(abs(inner - 0.125) < 0.02, "inside the half ball \(inner)")
        let mean = samples.reduce(SIMD3<Double>.zero) { $0 + SIMD3(Double($1.x), Double($1.y), Double($1.z)) }
            / Double(samples.count)
        #expect(abs(mean.x) < 0.03 && abs(mean.y) < 0.03 && abs(mean.z) < 0.03, "centroid \(mean)")
    }

    /// A line spray converges: a still scene through a still camera reads the same
    /// after twelve frames as after two, the pass count climbs, and moving the lens
    /// restarts it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func lineSprayConvergesAndResets() throws {
        let sketch = SpraySketch()
        let early = try #require(OllinApp.image(of: sketch, frame: 1))
        #expect(sketch.spray.passes == 2 * sketch.spray.passesPerFrame)
        let earlyMean = meanLinear(of: early)
        #expect(earlyMean > 0.001, "the spray should have drawn something: \(earlyMean)")

        let late = SpraySketch()
        let lateImage = try #require(OllinApp.image(of: late, frame: 11))
        #expect(late.spray.passes == 12 * late.spray.passesPerFrame)
        let lateMean = meanLinear(of: lateImage)
        #expect(abs(lateMean - earlyMean) / earlyMean < 0.1, "mean drifted: \(earlyMean) → \(lateMean)")

        // Six draws, the lens moved from the fourth on: the fourth, fifth, and
        // sixth are all the average holds.
        let moved = SpraySketch()
        moved.refocusAtFrame = 4
        _ = OllinApp.image(of: moved, frame: 5)
        #expect(moved.spray.passes == 3 * moved.spray.passesPerFrame, "a lens change restarts the average")
    }

    /// `exportSettle` draws a written frame several times with the clock held: a
    /// still counts N passes for its frame (and one for each run-up frame), the
    /// mean stays the mean, and a sequence settles every written frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func settledExportsDrawEachWrittenFrameSeveralTimes() throws {
        OllinApp.exportSettle = 6
        defer { OllinApp.exportSettle = 1 }

        let still = AccumulatorSketch()
        let image = try #require(OllinApp.image(of: still, frame: 0))
        #expect(still.light.passes == 6, "one advance plus five held draws")
        #expect(abs(centerLinear(of: image) - 0.2) < 0.02, "the mean is still the mean")

        let later = AccumulatorSketch()
        _ = OllinApp.image(of: later, frame: 2)
        #expect(later.light.passes == 8, "two run-up frames drawn once, the captured one six times")
        #expect(later.frameCount == 8)
        #expect(abs(later.time - 2.0 / 60) < 1e-9, "the clock held at the captured frame")

        let sequence = AccumulatorSketch()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-settle-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: directory) }
        OllinApp.exportSequence(sequence, to: directory, frames: 2, fps: 60)
        #expect(sequence.light.passes == 12, "every written frame settles")
        let written = (try? FileManager.default.contentsOfDirectory(atPath: directory))?
            .filter { $0.hasSuffix(".png") }.count
        #expect(written == 2)
    }

    // MARK: Support

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return bytes }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    private func linear(_ byte: UInt8) -> Double {
        let c = Double(byte) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// The sum of linear luminance over every pixel (the light the frame holds).
    private func linearSum(of image: CGImage) -> Double {
        let d = pixels(of: image)
        var sum = 0.0
        for i in stride(from: 0, to: d.count, by: 4) {
            sum += (linear(d[i]) + linear(d[i + 1]) + linear(d[i + 2])) / 3
        }
        return sum
    }

    private func meanLinear(of image: CGImage) -> Double {
        linearSum(of: image) / Double(image.width * image.height)
    }

    private func litPixels(of image: CGImage) -> [(x: Int, y: Int, value: Double)] {
        let d = pixels(of: image)
        var out: [(Int, Int, Double)] = []
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let i = (y * image.width + x) * 4
                if d[i] > 1 || d[i + 1] > 1 || d[i + 2] > 1 {
                    out.append((x, y, (linear(d[i]) + linear(d[i + 1]) + linear(d[i + 2])) / 3))
                }
            }
        }
        return out
    }

    private func centerByte(of image: CGImage) -> UInt8 {
        let d = pixels(of: image)
        let i = ((image.height / 2) * image.width + image.width / 2) * 4
        return d[i + 1]
    }

    private func centerLinear(of image: CGImage) -> Double { linear(centerByte(of: image)) }
}

// MARK: - Probe sketches

/// Draws `count` white particles at seeded random positions (or one at `fixed`)
/// in the given style, additively over black.
@MainActor
private final class ParticleDepositSketch: Sketch {
    var buffer: ComputeBuffer<OllinParticle>!
    var style: ParticleStyle = .marks
    override var canvasSize: CanvasSize { .square(512) }

    convenience init(count: Int, size: Float, alpha: Float, style: ParticleStyle, fixed: SIMD2<Float>? = nil) {
        self.init()
        var state: UInt32 = 12345
        func next() -> Float {
            state = state &* 1664525 &+ 1013904223
            return Float(state >> 8) / Float(1 << 24)
        }
        var particles: [OllinParticle] = []
        for _ in 0 ..< count {
            let position = fixed ?? SIMD2<Float>(16 + next() * 480, 16 + next() * 480)
            particles.append(OllinParticle(position: position, velocity: .zero,
                                           color: SIMD4(1, 1, 1, alpha), size: size,
                                           life: 1, seedA: 0, seedB: 0))
        }
        buffer = ComputeBuffer(particles)
        self.style = style
    }

    override func draw() {
        background(.black)
        blendMode(.add)
        drawParticles(buffer, style: style)
    }
}

/// Adds a 20% white square into an accumulator every frame and shows the mean.
@MainActor
private final class AccumulatorSketch: Sketch {
    var light: Accumulator!
    var passesPerBlock = 1
    var resetAtFrame: Int? = nil
    override var canvasSize: CanvasSize { .square(64) }

    override func setup() { light = makeAccumulator() }

    override func draw() {
        background(.black)
        if let resetAtFrame, frameCount == resetAtFrame { light.reset() }
        withAccumulator(light, passes: passesPerBlock) {
            blendMode(.add)
            noStroke()
            fill(Color(white: 1, alpha: 0.2))
            drawRect(0, 0, width, height)
        }
        drawImage(light.image, 0, 0)
    }
}

/// A feedback layer seeded at linear 0.5 that adds 0.0002 every frame.
@MainActor
private final class FeedbackSumSketch: Sketch {
    var precision: LayerPrecision = .float16
    var sum: Feedback!
    override var canvasSize: CanvasSize { .square(32) }

    convenience init(precision: LayerPrecision) {
        self.init()
        self.precision = precision
    }

    override func setup() { sum = makeFeedback(precision: precision) }

    override func draw() {
        background(.black)
        withFeedback(sum) { previous in
            if frameCount == 1 {
                background(Color(white: 0.7354))     // sRGB 0.7354 is linear 0.5
            } else {
                drawImage(previous, 0, 0)
            }
            blendMode(.add)
            noStroke()
            fill(Color(white: 1, alpha: 0.0002))
            drawRect(0, 0, width, height)
        }
        drawImage(sum.image, 0, 0)
    }
}

/// A layer at linear 0.5 printed at exposure 2 on a 0.1 ground.
@MainActor
private final class DevelopSketch: Sketch {
    override var canvasSize: CanvasSize { .square(32) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) { background(Color(white: 0.7354)) }
        let printed = layer.filtered(.develop(exposure: 2, ground: Color(white: 0.1)))
        drawImage(printed.image, 0, 0)
    }
}

/// A kernel projecting five world points (and one behind the camera) through the
/// packed camera, over the multi-buffer dispatch: a `SIMD4<Float>` list in, an
/// `OllinParticle` list out.
@MainActor
private final class ProjectionSketch: Sketch {
    let points = [Vector3(0, 0, 0), Vector3(1, 0.5, -2), Vector3(-2, 1, 1),
                  Vector3(0.3, -1.2, 2), Vector3(2, 2, -3)]
    var expected: [Vector2?] = []
    var world: ComputeBuffer<SIMD4<Float>>!
    var out: ComputeBuffer<OllinParticle>!
    override var canvasSize: CanvasSize { .size(320, 200) }

    private let kernel = ComputeKernel(entry: "project_probe", """
        kernel void project_probe(device const float4 *world [[buffer(0)]],
                                  device OllinParticle *out [[buffer(1)]],
                                  constant OllinComputeUniforms &u [[buffer(10)]],
                                  constant OllinCameraMatrices &camera [[buffer(11)]],
                                  uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            float4 screen = ollin_project(camera, world[id].xyz, u.resolution);
            OllinParticle p;
            p.position = screen.xy;
            p.velocity = float2(screen.z, screen.w);
            p.color = float4(1.0);
            p.size = screen.w > 0.0 ? 1.0 : 0.0;
            p.life = 1.0; p.seedA = 0.0; p.seedB = 0.0;
            out[id] = p;
        }
    """)

    required init() {
        super.init()
        var list = points.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 1) }
        list.append(SIMD4<Float>(0, 0, 20, 1))   // behind a camera at z = 10 looking at the origin
        world = ComputeBuffer(list)
        out = ComputeBuffer(count: list.count)
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(3, 2, 10), target: .zero, fieldOfView: .pi / 4))
        expected = points.map { project($0) }
        compute(kernel, buffers: [world, out], params: cameraParams())
    }
}

/// Fills a buffer with `ballSample` draws.
@MainActor
private final class BallSampleSketch: Sketch {
    let out = ComputeBuffer<SIMD4<Float>>(count: 16384)
    override var canvasSize: CanvasSize { .square(16) }
    private let kernel = ComputeKernel(entry: "ball_probe", """
        kernel void ball_probe(device float4 *out [[buffer(0)]],
                               constant OllinComputeUniforms &u [[buffer(10)]],
                               uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            out[id] = float4(ballSample(float3(float(id), 0.37, 1.9)), 0.0);
        }
    """)
    override func draw() {
        background(.black)
        compute(kernel, over: out)
    }
}

/// A small spray of a few bright lines through a still camera.
@MainActor
private final class SpraySketch: Sketch {
    var spray: LineSpray!
    var refocusAtFrame: Int? = nil
    override var canvasSize: CanvasSize { .square(96) }

    override func setup() {
        var lines: [SprayLine] = []
        for i in 0 ..< 12 {
            let a = Double(i) / 12 * .tau
            lines.append(SprayLine(from: Vector3(cos(a) * 2, sin(a) * 2, 0),
                                   to: Vector3(cos(a + 0.5) * 2, sin(a + 0.5) * 2, 0.5),
                                   intensity: 0.4))
        }
        spray = makeLineSpray(lines, sampling: .perLine(200), passesPerFrame: 3,
                              bokeh: Bokeh(focalDistance: 8, strength: 0.05, minSize: 0.02))
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 8), target: .zero, fieldOfView: .pi / 4))
        if let refocusAtFrame, frameCount >= refocusAtFrame {
            spray.bokeh = Bokeh(focalDistance: 6, strength: 0.05, minSize: 0.02)
        }
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: 40).image, 0, 0)
    }
}
