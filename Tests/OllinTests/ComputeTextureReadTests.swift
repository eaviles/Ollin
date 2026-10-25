@testable import Ollin
import Foundation
import Testing

/// Kernels that read pictures (`compute(_:buffers:textures:count:params:)` and
/// `stepParticles(_:custom:textures:)`): a layer is read as drawn the same frame,
/// a filtered layer after its filter ran, a file as linear light, and a dispatch
/// recorded after a layer-reading one keeps its place behind it. The headless
/// drive renders every frame such a kernel runs in, so what it carries forward
/// was read from each frame's own layer.
@Suite(.serialized)
@MainActor
struct ComputeTextureReadTests {

    /// The layer flips white and black frame by frame, so a kernel that read the
    /// frame before, or read before the layer pass, reads the other color.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aKernelReadsTheLayerDrawnThisFrame() throws {
        for frame in [3, 4] {
            let sketch = LayerReadSketch()
            _ = try OllinApp.image(of: sketch, frame: frame)
            let out = try #require(sketch.readings.snapshot())
            let expected: Float = sketch.lastFrameCount % 2 == 1 ? 1 : 0
            #expect(abs(out[0].x - expected) < 0.01,
                    "frame \(frame) (frameCount \(sketch.lastFrameCount)) read \(out[0])")
        }
    }

    /// Each frame adds what it read to a running sum, so after frames 0 through 5
    /// (frame counts 1 through 6) the sum counts the three white frames. A warmup
    /// frame that only stepped the compute would have read no layer at all.
    @Test(.enabled(if: Snapshot.hasMetal))
    func everyFrameBeforeTheCapturedOneReadsItsOwnLayer() throws {
        let sketch = LayerReadSketch()
        _ = try OllinApp.image(of: sketch, frame: 5)
        let out = try #require(sketch.readings.snapshot())
        #expect(abs(out[0].y - 3) < 0.05, "the sum over six frames is \(out[0].y)")
    }

    /// A dispatch with no picture, recorded after one that reads a layer, runs
    /// after it, so it sees what the first one wrote this frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLaterDispatchKeepsItsPlaceBehindTheReader() throws {
        let sketch = LayerReadSketch()
        _ = try OllinApp.image(of: sketch, frame: 4)
        let out = try #require(sketch.readings.snapshot())
        #expect(sketch.lastFrameCount % 2 == 1)
        #expect(abs(out[0].z - 2) < 0.02, "the follower doubled \(out[0].x) to \(out[0].z)")
    }

    /// A blurred layer is read after its blur: across a hard white edge the
    /// reading at the edge sits between the two sides.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFilteredLayerIsReadAfterItsFilter() throws {
        let sketch = FilteredReadSketch()
        _ = try OllinApp.image(of: sketch, frame: 0)
        let out = try #require(sketch.readings.snapshot())
        #expect(out[0].x > 0.98, "far inside the white half read \(out[0].x)")
        #expect(out[1].x > 0.3 && out[1].x < 0.7, "the blurred edge read \(out[1].x)")
        #expect(out[2].x < 0.02, "far inside the black half read \(out[2].x)")
    }

    /// A picture made on the CPU is read as linear light: sRGB 0.5 is about 0.214.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPictureFromTheCPUReadsAsLinearLight() throws {
        let sketch = FileReadSketch()
        _ = try OllinApp.image(of: sketch, frame: 0)
        let out = try #require(sketch.readings.snapshot())
        let expected = Float(Color.srgbToLinear(0.5))
        #expect(abs(out[0].x - expected) < 0.01, "read \(out[0].x) against \(expected)")
        #expect(abs(out[0].w - 1) < 0.001)
    }

    /// The generated particle step reads its pictures with `picture(index, point)`,
    /// a layer as drawn this frame, and a slot no picture was handed to as clear.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aParticleStepReadsItsPictures() throws {
        let sketch = ParticlePictureSketch()
        _ = try OllinApp.image(of: sketch, frame: 1)
        let particles = try #require(sketch.dots.current.snapshot())
        // The left particle sits in the white half, the right one in the black.
        #expect(abs(particles[0].color.x - 1) < 0.01, "left read \(particles[0].color.x)")
        #expect(particles[1].color.x < 0.01, "right read \(particles[1].color.x)")
        // Slot 1 was never handed a picture.
        #expect(particles[0].color.y == 0 && particles[0].color.w == 0)
    }
}

/// The reading kernel: sample the layer at the canvas center into `x`, add it to
/// the running sum in `y`. The follower writes twice `x` into `z`.
private let layerReader = ComputeKernel(entry: "probe_read_layer", """
    kernel void probe_read_layer(device float4 *out [[buffer(0)]],
                                 constant OllinComputeUniforms &u [[buffer(10)]],
                                 texture2d<float> layer [[texture(0)]],
                                 sampler s [[sampler(0)]],
                                 uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        float v = layer.sample(s, float2(0.5), level(0)).r;
        out[id].x = v;
        out[id].y += v;
    }
""")

private let follower = ComputeKernel(entry: "probe_follow", """
    kernel void probe_follow(device float4 *out [[buffer(0)]],
                             constant OllinComputeUniforms &u [[buffer(10)]],
                             uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        out[id].z = out[id].x * 2.0;
    }
""")

/// A layer white on odd frames and black on even ones, read by a kernel and
/// then by a follower that binds no picture.
@MainActor
private final class LayerReadSketch: Sketch {
    override var canvasSize: CanvasSize { .square(32) }
    let readings = ComputeBuffer<SIMD4<Float>>(count: 1)
    private(set) var lastFrameCount = 0

    override func draw() {
        lastFrameCount = frameCount
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) { background(frameCount % 2 == 1 ? .white : .black) }
        compute(layerReader, buffers: [readings], textures: [layer.image])
        compute(follower, buffers: [readings])
    }
}

/// Reads a blurred layer at three points across a hard edge.
@MainActor
private final class FilteredReadSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    let readings = ComputeBuffer<SIMD4<Float>>(count: 3)
    private let reader = ComputeKernel(entry: "probe_read_row", """
        kernel void probe_read_row(device float4 *out [[buffer(0)]],
                                   constant OllinComputeUniforms &u [[buffer(10)]],
                                   texture2d<float> layer [[texture(0)]],
                                   sampler s [[sampler(0)]],
                                   uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            float x = id == 0 ? 0.05 : (id == 1 ? 0.5 : 0.95);
            out[id] = layer.sample(s, float2(x, 0.5), level(0));
        }
    """)

    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            background(.black)
            noStroke(); fill(.white)
            drawRect(0, 0, width / 2, height)
        }
        let blurred = layer.filtered(.gaussianBlur(radius: 4)).image
        compute(reader, buffers: [readings], textures: [blurred])
    }
}

/// Reads a one-pixel picture made on the CPU in sRGB middle gray.
@MainActor
private final class FileReadSketch: Sketch {
    override var canvasSize: CanvasSize { .square(16) }
    let readings = ComputeBuffer<SIMD4<Float>>(count: 1)
    private let gray = Image(width: 1, height: 1, color: Color(white: 0.5))
    private let reader = ComputeKernel(entry: "probe_read_picture", """
        kernel void probe_read_picture(device float4 *out [[buffer(0)]],
                                       texture2d<float> picture [[texture(0)]],
                                       sampler s [[sampler(0)]],
                                       uint id [[thread_position_in_grid]]) {
            if (id > 0) { return; }
            out[0] = picture.sample(s, float2(0.5), level(0));
        }
    """)

    override func draw() {
        background(.black)
        compute(reader, buffers: [readings], textures: [gray])
    }
}

/// Two particles held at the left and right quarter of a canvas whose layer
/// is white on the left half, each taking the layer's color at its place into
/// red and the empty second slot into green and alpha.
@MainActor
private final class ParticlePictureSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    lazy var dots = Particles(count: 2, step: """
        position = float2(id == 0 ? 0.25 : 0.75, 0.5) * u.resolution;
        float4 seen = picture(0, position);
        float4 empty = picture(1, position);
        color = float4(seen.r, empty.r, 0.0, empty.a);
        size = 1.0;
        life = 1.0;
    """)

    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            background(.black)
            noStroke(); fill(.white)
            drawRect(0, 0, width / 2, height)
        }
        stepParticles(dots, textures: [layer.image])
    }
}
