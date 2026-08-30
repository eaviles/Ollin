import Testing
import Metal
import simd
import AppKit
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
        sketch.setup()
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
