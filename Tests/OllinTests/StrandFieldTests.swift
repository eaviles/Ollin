@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import simd
import Testing

/// CPU checks on `StrandField` (`drawStrands`): the derived tiling, the
/// recorder gates. The GPU behavior gets its Metal-gated suite below.
@Suite
@MainActor
struct StrandFieldTests {

    @Test func tilingDerivesFromCountAndArea() {
        let field = StrandField(width: 30, depth: 30, count: 90_000)
        let t = field.tiling
        // ~96 blades per tile: tile area ~= area * 96 / count.
        let expectedEdge = (30.0 * 30.0 * 96.0 / 90_000.0).squareRoot()
        #expect(abs(t.tileEdge - expectedEdge) < 1e-9)
        #expect(t.tilesX == Int((30 / expectedEdge).rounded(.up)))
        #expect(field.bladeCount == t.tilesX * t.tilesZ * 96)
    }

    @Test func recorderGates() {
        let drawer = Drawer()
        drawer.beginFrame()
        let field = StrandField(width: 10, depth: 10, count: 1_000)
        drawer.drawStrands(field)                     // no camera: no-op
        #expect(drawer.batches.isEmpty)
        drawer.camera(Camera3D(eye: Vector3(0, 2, 8), target: .zero))
        _ = drawer.makeBatch { drawer.drawStrands(field) }   // refused in a batch
        #expect(drawer.batches.isEmpty)
        drawer.translate(3, 0, 0)
        drawer.drawStrands(field)
        drawer.drawStrands(field)                     // stateless: twice is two patches
        let strands = drawer.batches.filter { $0.kind == .strands }
        #expect(strands.count == 2)
        #expect(strands[0].fieldTransform.columns.3.x == 3)
        #expect(strands[0].strandField != nil)
    }
}

/// GPU behavior: the pipeline builds from the runtime-compiled library, the
/// picture is deterministic frame to frame, and tile culling changes nothing
/// (a culled tile was outside the view by definition).
@Suite(.serialized)
@MainActor
struct StrandFieldRenderTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func strandPipelineBuilds() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        _ = try renderer.pipeline(.strands(.normal, depth: .depth32Float))
    }

    // The two below draw, so they want a GPU that can be driven through a mesh
    // pipeline, not merely one that builds the pipeline. `strandPipelineBuilds`
    // keeps the plain Metal gate because building is all it asks for.
    @Test(.enabled(if: Snapshot.hasMeshShaders))
    func aFieldRendersDeterministically() throws {
        let first = try #require(OllinApp.image(of: StrandABSketch(culling: true)))
        let second = try #require(OllinApp.image(of: StrandABSketch(culling: true)))
        let diff = try #require(strandImageDifference(first, second))
        #expect(diff.max == 0, "same field, same frame, different pixels (max \(diff.max))")
    }

    @Test(.enabled(if: Snapshot.hasMeshShaders))
    func tileCullingChangesNothingInThePicture() throws {
        let culled = try #require(OllinApp.image(of: StrandABSketch(culling: true)))
        let unculled = try #require(OllinApp.image(of: StrandABSketch(culling: false)))
        let diff = try #require(strandImageDifference(culled, unculled))
        #expect(diff.mean < 0.05,
                "tile culling changed the picture: mean \(diff.mean) (max \(diff.max))")
        #expect(diff.max <= 8,
                "tile culling changed the picture: max \(diff.max) (mean \(diff.mean))")
    }
}

/// The cost story, measured (`Scripts/benchmark.sh strands`, OLLIN_BENCH=1):
/// the example's 500,000-blade meadow under its low circling camera, GPU frame
/// time with distance-graded detail on vs off (tile culling on for both).
@Suite(.serialized)
@MainActor
struct StrandBenchmarkTests {

    @Test(.benchmark)
    func meadowCostDetailGradedVsFull() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let res = 1080
        let viewport = SIMD2<Float>(Float(res), Float(res))

        func measure(detail: Bool) -> (gpuMs: Double, blades: Int) {
            let sketch = StrandBenchScene()
            sketch.setCanvasSize(width: Double(res), height: Double(res))
            sketch.setup()
            sketch.detail = detail
            sketch.advance(time: 1, deltaTime: 1 / 60, frameRate: 60)
            sketch.performDraw()
            let gpu = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                        width: res, height: res, iterations: 20)
            return (gpu, sketch.blades)
        }

        let graded = measure(detail: true)
        let full = measure(detail: false)
        print("\n=== Ollin strands benchmark (\(graded.blades) blades, \(res)² px, lit + shadows + fog) ===")
        print(String(format: "detail graded: GPU %6.2f ms", graded.gpuMs))
        print(String(format: "full detail:   GPU %6.2f ms", full.gpuMs))
        print(String(format: "win from distance grading: %.2fx", full.gpuMs / max(graded.gpuMs, 0.0001)))
        print("=== end ===\n")
    }
}

/// The benchmark's meadow: the example's field and camera, so the numbers
/// measure what the example's parameter toggles.
@MainActor
private final class StrandBenchScene: Sketch {
    var detail = true
    private(set) var blades = 0
    private var meadow = StrandField(width: 90, depth: 90, count: 500_000)

    override func setup() {
        meadow.bladeHeight = 0.7
        meadow.heightVariance = 0.45
        meadow.bladeWidth = 0.045
        meadow.lean = 0.34
        meadow.swayAmplitude = 0.14
        meadow.detailNear = 10
        meadow.detailFar = 42
        blades = meadow.bladeCount
    }

    override func draw() {
        background(Color(hex: 0x11141B))
        meadow.isLevelOfDetailEnabled = detail
        let t = time * 0.04
        camera(Camera3D(eye: Vector3(cos(t * .tau) * 26, 2.6, sin(t * .tau) * 26),
                        target: Vector3(cos(t * .tau + 0.16) * 24, 0.9, sin(t * .tau + 0.16) * 24),
                        far: 80))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.75, -0.4), intensity: 1)
        castShadows()
        fog(Color(hex: 0x11141B), density: 0.03)
        withState {
            fill(Color(hue: 0.29, saturation: 0.35, brightness: 0.16))
            drawPlane(width: 200, depth: 200)
        }
        drawStrands(meadow)
    }
}

/// The fixture: a meadow patch framed so a good share of it is off-screen,
/// lit, with a solid casting a shadow the blades receive. No time (frame 0),
/// so the sway is at its phase-zero pose and runs deterministically.
@MainActor
private final class StrandABSketch: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let culling: Bool

    init(culling: Bool) {
        self.culling = culling
        super.init()
    }

    required init() {
        self.culling = true
        super.init()
    }

    override func draw() {
        background(Color(hex: 0x101218))
        camera(Camera3D(eye: Vector3(5, 2.4, 5), target: Vector3(1.5, 0.3, 0)))
        ambientLight(Color(white: 0.18))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()
        withState {
            fill(Color(hue: 0.3, saturation: 0.25, brightness: 0.3))
            drawPlane(width: 30, depth: 30)
        }
        withState {
            translate(1.2, 0.75, -0.6)
            fill(Color(hue: 0.08, saturation: 0.4, brightness: 0.7))
            drawBox(width: 1.2, height: 1.5, depth: 1.2)
        }
        var meadow = StrandField(width: 16, depth: 16, count: 60_000)
        meadow.bladeHeight = 0.55
        meadow.swayAmplitude = 0.08
        meadow.isCullingEnabled = culling
        drawStrands(meadow)
    }
}

/// Mean and max per-channel byte difference between two same-size images.
@MainActor
private func strandImageDifference(_ a: CGImage, _ b: CGImage) -> (mean: Double, max: Int)? {
    func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: ptr, count: w * h * 4))
    }
    guard a.width == b.width, a.height == b.height,
          let ab = rgba(a), let bb = rgba(b) else { return nil }
    var total = 0, worst = 0
    for i in ab.indices {
        let d = abs(Int(ab[i]) - Int(bb[i]))
        total += d
        worst = Swift.max(worst, d)
    }
    return (Double(total) / Double(ab.count), worst)
}
