import CoreGraphics
import Foundation
import Metal
import Testing
import simd
@testable import Ollin

/// Compute-shader core: the GPU-free plumbing (param packing, source composition,
/// the hash key, ping-pong) runs everywhere; the real kernel run is Metal-gated and
/// soft-skips on a machine without a GPU (CI is fine — `Snapshot.hasMetal`).
@Suite
@MainActor
struct ComputeTests {

    // MARK: GPU-free plumbing

    @Test func paramsPackInOrder() {
        var p = ComputeParams()
        p.append(Float(1))
        p.append(SIMD2<Float>(2, 3))
        p.append(SIMD4<Float>(4, 5, 6, 7))
        // 1 + 2 + 4 floats = 7 floats = 28 bytes.
        #expect(p.bytes.count == 28)
        let floats = p.bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(floats == [1, 2, 3, 4, 5, 6, 7])
        #expect(ComputeParams().isEmpty)
    }

    @Test func composeSplicesPreludeAndTypes() {
        let composed = MetalRenderer.composeComputeSource("kernel void k() { /* MARKER */ }")
        // The stdlib preamble, the shared particle struct, a library helper, and the
        // user's own source all land in the composed kernel.
        #expect(composed.contains("#include <metal_stdlib>"))
        #expect(composed.contains("OllinParticle"))      // shared types header
        #expect(composed.contains("curlNoise"))          // shared shader library
        #expect(composed.contains("palette"))            // …the whole library, not a subset
        #expect(composed.contains("MARKER"))             // user source, last
        // User source comes after the spliced headers.
        #expect(composed.range(of: "MARKER")!.lowerBound > composed.range(of: "curlNoise")!.lowerBound)
    }

    @Test func fnvIsStableAndDistinct() {
        #expect(MetalRenderer.fnv1a("abc") == MetalRenderer.fnv1a("abc"))
        #expect(MetalRenderer.fnv1a("abc") != MetalRenderer.fnv1a("abd"))
        #expect(MetalRenderer.fnv1a("") == 0xcbf29ce484222325)   // the FNV offset basis
    }

    /// An inline kernel that includes no file is found by its own text, so only
    /// its first dispatch composes the shader library around it. The test for
    /// that key used to be the kernel's path, which an inline kernel always has
    /// (the Swift file it was written in), so no kernel ever matched and every
    /// dispatch of every frame composed the whole library and hashed it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anInlineKernelIsFoundWithoutComposingTheLibrary() throws {
        let inline = ComputeKernel(entry: "ollin_quick_probe", """
            kernel void ollin_quick_probe(uint i [[thread_position_in_grid]]) {}
            """)
        let including = ComputeKernel(entry: "ollin_quick_probe", """
            #include "neighbor.metal"
            kernel void ollin_quick_probe(uint i [[thread_position_in_grid]]) {}
            """)
        #expect(inline.quickHash != nil)
        #expect(including.quickHash == nil, "an included file can change under the kernel")

        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let first = try renderer.computePipeline(for: inline)
        #expect(renderer.quickComputePipelines.count == 1)
        let again = try renderer.computePipeline(for: inline)
        #expect(first === again)
    }

    @Test func pingPongSwaps() {
        let pp = PingPong<Float>(count: 8)
        let a = pp.read, b = pp.write
        #expect(a !== b)                 // two distinct buffers
        pp.swap()
        #expect(pp.read === b)           // the freshly written buffer is now current
        #expect(pp.write === a)
        pp.swap()
        #expect(pp.read === a)           // and back
    }

    @Test func seededBufferUploadsOnce() {
        // A seeded buffer reports its element count; an unseeded one is still sized.
        #expect(ComputeBuffer<Float>([1, 2, 3, 4]).count == 4)
        #expect(ComputeBuffer<Float>(count: 10).count == 10)
    }

    @Test func textureFormatLayout() {
        #expect(ComputeTextureFormat.rgba16Float.channels == 4)
        #expect(ComputeTextureFormat.rgba16Float.bytesPerPixel == 8)
        #expect(ComputeTextureFormat.rgba32Float.bytesPerPixel == 16)
        #expect(ComputeTextureFormat.rgba8Unorm.bytesPerPixel == 4)
        #expect(ComputeTextureFormat.r32Float.channels == 1)
        #expect(ComputeTextureFormat.r16Float.bytesPerPixel == 2)
    }

    @Test func computeTextureClampsSize() {
        // A degenerate size is clamped to 1×1 (never zero), like a blank Image.
        let t = ComputeTexture(width: 0, height: -5)
        #expect(t.width == 1 && t.height == 1)
        #expect(t.format == .rgba16Float)        // the default
    }

    @Test func pingPongTextureSwaps() {
        let pp = PingPongTexture(width: 8, height: 8)
        let a = pp.read, b = pp.write
        #expect(a !== b)                          // two distinct textures
        pp.swap()
        #expect(pp.read === b)                     // the freshly written texture is current
        #expect(pp.write === a)
        pp.swap()
        #expect(pp.read === a)                     // and back
    }

    @Test func kernelLoadsFromFile() throws {
        // A kernel can live in a .metal file (editor highlighting / checking) and load
        // by path. A missing file throws a `FileError` naming it, which
        // `FileErrorTests.aMissingFileIsMissingAndNamesItsPath` pins.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-test-\(UInt64(abs(42))).metal")
        try "kernel void k(uint i [[thread_position_in_grid]]) { /* FILE_MARKER */ }"
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try? ComputeKernel(entry: "k", contentsOf: url)
        #expect(loaded?.entry == "k")
        #expect(loaded?.source.contains("FILE_MARKER") == true)
    }

    // MARK: Metal-gated — the real kernel compiles, dispatches, and renders

    /// A 10k-particle kernel scatters white dots; rendering the frame must produce
    /// visible (non-black) pixels — proof the kernel compiled (with the prelude),
    /// dispatched, and fed the particle render path. A compile failure would leave
    /// the frame black, so a positive brightness is the end-to-end signal.
    @Test(.enabled(if: Snapshot.hasMetal))
    func kernelRendersParticles() throws {
        let sketch = ComputeProbeSketch()
        guard let image = OllinApp.image(of: sketch, frame: 1) else {
            Issue.record("render failed")
            return
        }
        #expect(maxLuma(of: image) > 0.2)   // the scattered dots lit the canvas
    }

    /// A compute kernel writes a `ComputeTexture` (one value per texel from `gid`);
    /// reading it back must show those values — proof the 2-D texture dispatch
    /// compiled, bound the write texture, and ran.
    @Test(.enabled(if: Snapshot.hasMetal))
    func textureKernelWrites() throws {
        let sketch = TextureProbeSketch()
        _ = OllinApp.image(of: sketch, frame: 0)        // runs the seed dispatch + render
        guard let data = sketch.field.snapshot() else {
            Issue.record("no snapshot — texture never realized")
            return
        }
        // The kernel wrote `gid.x + gid.y * 8` into each texel's red channel.
        #expect(data.count == 8 * 8)
        #expect(data[0] == 0)                            // (0,0)
        #expect(data[8 * 8 - 1] == Float(7 + 7 * 8))     // (7,7) = 63
        #expect(data[10] == Float(2 + 1 * 8))            // (2,1) = 10
    }

    /// A `Simulation` whose step adds 1 to the red channel each iteration must read
    /// back `frame + 1` after rendering frame `frame` — proof the ping-pong textures
    /// carry state forward and that the headless driver runs the compute on *every*
    /// frame, not just the captured one (the `stepCompute` path).
    @Test(.enabled(if: Snapshot.hasMetal))
    func simulationEvolvesAcrossFrames() throws {
        let sketch = SimProbeSketch()
        _ = OllinApp.image(of: sketch, frame: 5)        // 6 frames → 6 steps
        guard let data = sketch.sim.current.snapshot() else {
            Issue.record("no snapshot — simulation never realized")
            return
        }
        #expect(data.count == 4 * 4 * 4)                 // 4×4 texels × rgba
        #expect(data.allSatisfy { $0 == 6 })             // every channel stepped 6 times
    }

    /// The shader library's 3D `curlNoise` is a curl: its divergence vanishes
    /// while the flow itself has real size. The probe takes its differences at
    /// the curl's own step, where the two difference operators commute exactly
    /// and the residual is float rounding; a sign slipped in any component, or
    /// two partials paired wrongly, leaves a divergence of the flow's own order.
    /// (The value noise under it is only once differentiable, so a finer step
    /// reads its kinks at cell edges as divergence, which says nothing about
    /// the wiring.)
    @Test(.enabled(if: Snapshot.hasMetal))
    func shaderCurl3DIsDivergenceFree() throws {
        let sketch = CurlProbeSketch()
        _ = OllinApp.image(of: sketch, frame: 0)
        let readings = try #require(sketch.out.snapshot())
        let divergence = readings.map { Double(abs($0.x)) }
        let flows = readings.map { SIMD3<Double>(Double($0.y), Double($0.z), Double($0.w)) }
        let meanMagnitude = flows.map { simd_length($0) }.reduce(0, +) / Double(flows.count)
        let worst = divergence.max() ?? 0
        #expect(meanMagnitude > 0.1, "the flow has size: mean |curl| \(meanMagnitude)")
        #expect(worst < meanMagnitude * 1e-3, "largest divergence \(worst) against mean |curl| \(meanMagnitude)")
        let perAxis = flows.reduce(SIMD3<Double>.zero) { $0 + simd_abs($1) } / Double(flows.count)
        #expect(perAxis.x > 0.05 && perAxis.y > 0.05 && perAxis.z > 0.05, "every axis carries flow: \(perAxis)")
    }

    /// Peak luma across the image, 0…1 — enough to tell "something drew" from black.
    private func maxLuma(of image: CGImage) -> Double {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var peak: UInt8 = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            peak = max(peak, bytes[i], bytes[i + 1], bytes[i + 2])
        }
        return Double(peak) / 255
    }
}

/// A minimal sketch driving the compute path: a kernel scatters white dots, drawn
/// as particles. The canvas is small because the dots scatter over whatever
/// resolution it has and the test reads only the brightest pixel.
@MainActor
private final class ComputeProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }
    private lazy var dots = Particles(count: 10_000, step: """
        position = float2(hash12(float2(float(id), 1.0)),
                          hash12(float2(float(id), 2.0))) * u.resolution;
        size = 8.0;
        color = float4(1.0, 1.0, 1.0, 1.0);
        life = 1.0;
    """)

    override func draw() {
        background(.black)
        stepParticles(dots)
        drawParticles(dots)
    }
}

/// Drives the texture-compute path: a kernel writes `gid.x + gid.y * width` into an
/// 8×8 single-channel float texture, which `textureKernelWrites` reads back.
@MainActor
private final class TextureProbeSketch: Sketch {
    // The dispatch covers the texture, not the canvas, so the canvas stays small.
    override var canvasSize: CanvasSize { .square(64) }
    let field = ComputeTexture(width: 8, height: 8, format: .r32Float)
    private let seed = ComputeKernel(entry: "probe_seed", """
        kernel void probe_seed(texture2d<float, access::write> dst [[texture(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
            dst.write(float4(float(gid.x + gid.y * dst.get_width()), 0, 0, 0), gid);
        }
    """)

    override func draw() {
        background(.black)
        compute(seed, writing: field)
    }
}

/// Drives the `Simulation` ping-pong path: each step adds 1 to every channel, so the
/// field's value equals the number of steps run — what `simulationEvolvesAcrossFrames`
/// reads back.
@MainActor
private final class SimProbeSketch: Sketch {
    // The steps cover the field, not the canvas, so the canvas stays small.
    override var canvasSize: CanvasSize { .square(64) }
    let sim = Simulation(width: 4, height: 4, step: "result = value + float4(1.0);")
    override func draw() {
        background(.black)
        stepSimulation(sim)
    }
}

/// Reads the shader library's 3D curl at a spread of points: x is the flow's
/// divergence by central differences at the curl's own step (0.1), and yzw
/// the flow itself.
@MainActor
private final class CurlProbeSketch: Sketch {
    let out = ComputeBuffer<SIMD4<Float>>(count: 1024)
    override var canvasSize: CanvasSize { .square(16) }
    private let kernel = ComputeKernel(entry: "curl_probe", """
        kernel void curl_probe(device float4 *out [[buffer(0)]],
                               constant OllinComputeUniforms &u [[buffer(10)]],
                               uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            float3 p = float3(float(id) * 0.37 + 0.13, float(id % 29) * 0.61 + 0.43, float(id % 17) * 0.29 + 0.77);
            const float d = 0.1;   // the step curlNoise itself differences at
            float3 c = curlNoise(p);
            float dx = curlNoise(p + float3(d, 0, 0)).x - curlNoise(p - float3(d, 0, 0)).x;
            float dy = curlNoise(p + float3(0, d, 0)).y - curlNoise(p - float3(0, d, 0)).y;
            float dz = curlNoise(p + float3(0, 0, d)).z - curlNoise(p - float3(0, 0, d)).z;
            float divergence = (dx + dy + dz) / (2.0 * d);
            out[id] = float4(divergence, c.x, c.y, c.z);
        }
    """)
    override func draw() {
        background(.black)
        compute(kernel, over: out)
    }
}
