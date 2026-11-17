import Testing
import Metal
import simd
import AppKit
import ImageIO
@testable import Ollin

/// A raymarched-3D-SDF micro-benchmark, **gated by `OLLIN_BENCH=1`** so the normal test suite
/// skips it. The fullscreen sphere-tracer runs in the main pass at the *drawable* resolution
/// (unlike the canvas-resolution effect layers), so this measures a representative field at the
/// live drawable across a sweep of camera-march step counts, prints the true per-frame GPU cost
/// (from command-buffer timestamps, vsync-independent), and recommends per-tier step budgets for
/// *this* GPU. This is the **full-resolution** cost the `.default`/`.detail` tiers pay; the
/// `.performance` tier's half-resolution lever is separate (bench an example set to it).
///
/// Run via `Scripts/benchmark.sh raymarch [resolution]`.
@Suite(.serialized)
struct RaymarchBenchmarkTests {

    /// A representative composed field: three spheres melting together by smooth-union (one
    /// orbiting fixed for determinism) with a sphere carved out, skewered by a rasterised bar so
    /// the depth-composite cost is included, the shape of `3D/RaymarchedSDF`. The quality is left
    /// at default (full resolution); the benchmark drives the step count through
    /// `raymarchStepsOverride`.
    final class BenchScene: Sketch {
        override func draw() {
            background(Color(hex: 0x0e1116))
            camera(.orbiting(target: .zero, radius: 5.5, azimuth: 0.6, elevation: 0.45,
                             fieldOfView: .pi / 4, near: 0.1, far: 40))
            directionalLight(.white, direction: Vector3(-0.6, 0.7, 0.5), intensity: 1.1, softness: 0.3)
            ambientLight(Color(white: 0.16))
            withState {
                material(.glossy); fill(Color(hex: 0xf2c14e)); rotateZ(0.3)
                drawBox(width: 4.4, height: 0.45, depth: 0.45)
            }
            material(.jade)
            let blob = SDF3D.sphere(radius: 1.05).colored(Color(hex: 0x39d0ff))
                .smoothUnion(SDF3D.sphere(radius: 0.85).at(0.9, 0.4, 0.7).colored(Color(hex: 0xff4f97)), k: 0.7)
                .smoothUnion(SDF3D.sphere(radius: 0.6).at(-1.1, 0.7, 0.4).colored(Color(hex: 0xb6ff5a)), k: 0.5)
                .smoothSubtract(SDF3D.sphere(radius: 0.7).at(0.2, 1.15, 0), k: 0.25)
            drawSDF3D(blob)
        }
    }

    /// A field of eight capsules beside a block, under a point light that casts: on
    /// a GPU that traces, the block's shadow on the field is traced, so the field
    /// marches through the build that carries the shadow rays.
    final class TracedShadowScene: Sketch {
        let block = Mesh.box(width: 0.9, height: 0.9, depth: 0.9)
        override func draw() {
            background(Color(hex: 0x0e1116))
            camera(.perspective(eye: Vector3(0, 0, 9), target: .zero, fieldOfView: .pi / 4))
            pointLight(.white, at: Vector3(-3, 4, 5), intensity: 1.6)
            ambientLight(Color(white: 0.16))
            castShadows()
            withState { translate(-2.2, 1.6, 1.5); fill(.white); drawMesh(block) }
            var field = SDF3D.line(from: Vector3(-1.5, -2, 0), to: Vector3(-1, -1, 0.4), radius: 0.35)
            for i in 1 ..< 8 {
                let t = Double(i)
                field = field.smoothUnion(
                    SDF3D.line(from: Vector3(sin(t * 2.1) * 1.6, t * 0.55 - 2, cos(t * 1.7) * 0.8),
                               to: Vector3(sin(t * 2.1 + 1) * 1.4, t * 0.55 - 1.4, cos(t * 1.7 + 1) * 0.8),
                               radius: 0.3), k: 0.25)
            }
            fill(Color(hex: 0x39d0ff))
            drawSDF3D(field)
        }
    }

    /// What a marched field costs in a frame with a traced shadow, against the same
    /// frame with the shadow through its map: the number the field's pass count
    /// multiplies by when its fragment carries the shadow rays
    /// (`MetalRenderer.tracedShadowFieldCost`). Run via `Scripts/benchmark.sh raymarch`.
    @Test(.benchmark)
    @MainActor
    func fieldBesideATracedShadowBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        guard renderer.rayTracedShadows else { print("benchmark: this GPU traces no shadows"); return }
        let width = 540, height = 960
        let sketch = TracedShadowScene()
        sketch.setCanvasSize(width: Double(width), height: Double(height))
        try sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.raymarchQuality(.detail)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(width), Float(height))
        func time(traced: Bool) -> Double {
            renderer.tracesShadows = traced
            return renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                     width: width, height: height, iterations: 20)
        }
        print("\n=== Ollin field-beside-a-traced-shadow benchmark ===")
        var mapped: [Double] = [], traced: [Double] = []
        for _ in 0 ..< 3 {
            mapped.append(time(traced: false))
            traced.append(time(traced: true))
        }
        let m = mapped.sorted()[1], t = traced.sorted()[1]
        print(String(format: "shadow through its map (the build that traces nothing): %.2f ms", m))
        print(String(format: "shadow traced (the build that traces shadows alone):    %.2f ms", t))
        print(String(format: "ratio: %.2f   passes the field took: %d", m > 0 ? t / m : 0, renderer.lastFieldPasses))
        print("=== end ===\n")
    }

    /// What dividing a march costs by itself: a light field (the blob above) at
    /// 1080 by 1920 and full resolution, in one pass and in the counts a heavy field
    /// takes. The work is the same in each; what grows is a full-screen draw whose
    /// fragments mostly leave at once, and the target loaded and stored again.
    @Test(.benchmark)
    @MainActor
    func fieldPassOverheadBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        renderer.automaticQuality = .detail
        let width = 1080, height = 1920
        let sketch = BenchScene()
        sketch.setCanvasSize(width: Double(width), height: Double(height))
        try sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(width), Float(height))
        print("\n=== Ollin field-pass overhead benchmark (1080 by 1920, a light field) ===")
        print(" passes |  GPU ms")
        var single = 0.0
        for passes in [1, 2, 4, 8, 16] {
            renderer.fieldPassesOverride = passes
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: width, height: height, iterations: 12)
            if passes == 1 { single = ms }
            print(String(format: "  %5d | %7.2f%@", passes, ms,
                         passes > 1 ? String(format: "   (%.2f ms a pass more)", (ms - single) / Double(passes - 1)) : ""))
        }
        renderer.fieldPassesOverride = nil
        print("=== end ===\n")
    }

    /// One frame of a heavy field through the passes its work is divided into, at an
    /// export's quality: the check that closes *a heavy field in bounded passes*.
    /// Gated twice, since a miss here restarts the GPU: by `OLLIN_BENCH`, and by
    /// `OLLIN_HEAVY_FIELD` naming the rung (`64`, `126`, or `126-shadowed`). Each
    /// rung is one process and one frame; nothing is drawn again after a failure.
    @Test(.benchmark)
    @MainActor
    func heavyFieldInBoundedPasses() throws {
        guard let rung = ProcessInfo.processInfo.environment["OLLIN_HEAVY_FIELD"] else {
            print("benchmark: set OLLIN_HEAVY_FIELD to 64, 126, or 126-shadowed")
            return
        }
        final class Rung: Sketch {
            var parts = 64
            var shadowed = false
            var floored = false
            let floor = Mesh.plane(width: 30, depth: 30)
            override var canvasSize: CanvasSize { .size(1080, 1920) }
            override func draw() {
                background(Color(white: 0.06))
                camera(.perspective(eye: Vector3(0, 0, 15), target: .zero, fieldOfView: .pi / 5))
                directionalLight(.white, direction: Vector3(0.4, -0.7, -0.5), intensity: 1.1)
                ambientLight(Color(white: 0.2))
                if shadowed { castShadows() }
                if floored {
                    // A floor behind the field for its shadow to land on, so the field is
                    // marched from the light into the shadow map as well.
                    withState { translate(0, -4.6, 0); fill(Color(white: 0.8)); drawMesh(floor) }
                }
                fill(Color(red: 0.9, green: 0.55, blue: 0.25))
                drawSDF3D(FieldPassesTests.Heavy.field(parts))
            }
        }
        // The rungs: 64, 126, 126-shadowed, 126-shadowed-noskips, 126-shadowed-floor,
        // and 126-shadowed-onepass (the planned picture with no division at all).
        let sketch = Rung()
        sketch.parts = rung.hasPrefix("126") ? 126 : 64
        sketch.shadowed = rung.contains("shadowed")
        sketch.floored = rung.hasSuffix("floor")
        if rung.hasSuffix("noskips") { sketch.drawer.sdf3DSkipPolicy = .never }
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        renderer.automaticQuality = .detail   // an export's: the full step budget at full resolution
        if rung.hasSuffix("onepass") { renderer.fieldPassesOverride = 1 }
        print("\n=== Ollin heavy-field benchmark: \(sketch.parts) capsules\(sketch.shadowed ? " under a shadow" : ""), 1080 by 1920 ===")
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let start = Date()
        do {
            let image = try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer)
            let seconds = Date().timeIntervalSince(start)
            let nodes = sketch.drawer.sdf3DNodes
            print("instructions: \(SDF3D.strippingSkips(nodes).count), \(nodes.count) with skips")
            print("passes: \(renderer.lastFieldPasses) for the march, \(renderer.lastFieldShadowPasses) for the cast into the shadow map")
            print(String(format: "frame: %.2f s of clock, the first frame of a fresh renderer (pipelines included)", seconds))
            print(image == nil ? "the frame came back empty" : "the frame drew")
            if let image, let out = ProcessInfo.processInfo.environment["OLLIN_HEAVY_FIELD_OUT"] {
                let url = URL(fileURLWithPath: out) as CFURL
                if let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                    print("written: \(out)")
                }
            }
        } catch {
            print("the frame failed: \(error)")
        }
        print("=== end ===\n")
    }

    @Test(.benchmark)
    @MainActor
    func raymarchQualityBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let iters = 20

        // The fullscreen raymarch runs in the main pass at the *drawable* resolution, so tune the
        // step tiers against the default sketch's live drawable (its `.auto` window × backing
        // scale), like the shadow benchmark. OLLIN_BENCH_RES overrides.
        let canvasPt = Sketch.defaultSize.cgSize
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let windowPt = OllinApp.windowSize(fitting: canvasPt)
        let liveDrawable = Int((windowPt.height * scale).rounded())
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? liveDrawable

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        print("\n=== Ollin raymarch benchmark ===")
        print("Mac: \(ShadowBenchmarkTests.sysctl("hw.model") ?? "?") · \(ShadowBenchmarkTests.sysctl("machdep.cpu.brand_string") ?? "?") · \(gb(ProcessInfo.processInfo.physicalMemory)) RAM · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) · \(ShadowBenchmarkTests.gpuFamily(device)) · \(device.hasUnifiedMemory ? "unified" : "discrete") memory · \(gb(device.recommendedMaxWorkingSetSize)) working set")
        print("benchmark resolution: \(res)×\(res) px  (the default sketch's live drawable; the raymarch runs in the main pass at the drawable, not the canvas; set OLLIN_BENCH_RES to override)")
        print("note: this is the FULL-resolution cost the .default/.detail tiers pay; the .performance tier marches at half this resolution (~4× cheaper)\n")

        let sketch = BenchScene()
        sketch.setCanvasSize(width: Double(res), height: Double(res))
        try sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(res), Float(res))
        let budget60 = 1000.0 / 60, budget120 = 1000.0 / 120

        print(" steps |  GPU ms |  ~fps  | within")
        print("-------+---------+--------+--------")
        var best60 = 0, best120 = 0
        for n in [32, 48, 64, 96, 128, 192, 256] {
            renderer.raymarchStepsOverride = n
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: res, height: res, iterations: iters)
            let fps = ms > 0 ? 1000.0 / ms : 0
            let within = ms <= 0 ? "" : ms <= budget120 ? "120fps" : ms <= budget60 ? "60fps" : ""
            print(String(format: "  %4d | %7.2f | %6.0f | %@", n, ms, fps, within))
            if ms > 0 && ms <= budget60 { best60 = max(best60, n) }
            if ms > 0 && ms <= budget120 { best120 = max(best120, n) }
        }
        renderer.raymarchStepsOverride = nil

        print("\nmax full-res steps at ~60fps: \(best60)   at ~120fps: \(best120)   (\(res)×\(res))")
        let d = max(32, best60), p = max(16, d / 2), det = min(512, d * 2)
        print("suggested full-res tiers (.default ≈ the 60fps max, perf ≈ ½, detail ≈ 2×):")
        print("  .performance ≈ \(p)    .default ≈ \(d)    .detail ≈ \(det)")
        print("→ set these in MetalRenderer.resolveRaymarchSteps (the .performance tier also halves resolution).")
        print("=== end ===\n")
    }
}
