import Testing
import Metal
import simd
@testable import Ollin

/// A soft-shadow micro-benchmark — **gated by `OLLIN_BENCH=1`** so the normal test suite
/// skips it. It renders a representative shadow scene at a Retina-ish resolution across a
/// sweep of ray counts, prints the true per-frame GPU cost (from command-buffer timestamps,
/// so it's vsync-independent), and recommends per-tier ray counts for *this* GPU. Run it on
/// each machine (Intel / M-series) to tune `MetalRenderer.resolveShadowSamples`.
///
/// Run via `Scripts/benchmark-shadows.sh [resolution]`.
@Suite(.serialized)
struct ShadowBenchmarkTests {

    /// A point light over a ring of pillars + a sphere on a floor — the `3D/PointShadow`
    /// scene, the worst case for shadow cost (lots of lit floor whose rays traverse the
    /// whole structure). A fixed camera azimuth keeps the measurement deterministic.
    final class BenchScene: Sketch {
        override func draw() {
            background(.black)
            camera(.orbiting(target: Vector3(0, 1, 0), radius: 15,
                             azimuth: 0.5, elevation: 0.55, fieldOfView: .pi / 4.6))
            ambientLight(Color(white: 0.08))
            pointLight(.white, at: Vector3(0, 6, 0), intensity: 1.7)
            castShadows()
            withState { fill(Color(white: 0.82)); drawPlane(width: 30, depth: 30) }
            for i in 0..<9 {
                let a = Double(i) / 9 * .tau
                withState {
                    translate(cos(a) * 3.6, 1.1, sin(a) * 3.6)
                    fill(Color(hue: Double(i) / 9, saturation: 0.55, brightness: 0.95))
                    drawBox(width: 1, height: 2.2, depth: 1)
                }
            }
            withState { translate(1.5, 0.9, 0.4); fill(.cyan); drawSphere(radius: 0.9) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_BENCH"] != nil))
    @MainActor
    func shadowQualityBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let rt = device.supportsRaytracing && device.supportsRaytracingFromRender
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "2160") ?? 2160
        let iters = 30

        print("\n=== Ollin shadow benchmark ===")
        print("GPU: \(device.name)")
        print("ray tracing: supportsRaytracing=\(device.supportsRaytracing), fromRender=\(device.supportsRaytracingFromRender), hardware-RT(apple9+)=\(device.supportsFamily(.apple9))")
        print("shadow path: \(rt ? "RAY-TRACED — the quality tiers apply" : "mid-point CUBE fallback — tiers inert (no rays)")")
        print("resolution: \(res)×\(res)  (a ~Retina full-window proxy; set OLLIN_BENCH_RES to your real drawable)\n")

        let sketch = BenchScene()
        sketch.setCanvasSize(width: Double(res), height: Double(res))
        sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        let viewport = SIMD2<Float>(Float(res), Float(res))
        let budget60 = 1000.0 / 60, budget120 = 1000.0 / 120

        if !rt {
            sketch.performDraw()
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: res, height: res, iterations: iters)
            print(String(format: "cube shadow path: %.2f ms  (~%.0f fps)", ms, ms > 0 ? 1000 / ms : 0))
            print("(quality tiers don't apply on this GPU — no ray tracing.)")
            print("=== end ===\n")
            return
        }

        print(" rays |  GPU ms |  ~fps  | within")
        print("------+---------+--------+--------")
        var best60 = 0, best120 = 0
        for n in [1, 2, 4, 8, 16, 32, 64] {
            sketch.shadowSamples(n)
            sketch.performDraw()
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: res, height: res, iterations: iters)
            let fps = ms > 0 ? 1000.0 / ms : 0
            let within = ms <= 0 ? "" : ms <= budget120 ? "120fps" : ms <= budget60 ? "60fps" : ""
            print(String(format: "  %3d | %7.2f | %6.0f | %@", n, ms, fps, within))
            if ms > 0 && ms <= budget60 { best60 = max(best60, n) }
            if ms > 0 && ms <= budget120 { best120 = max(best120, n) }
        }
        print("\nmax rays at ~60fps: \(best60)   at ~120fps: \(best120)   (\(res)×\(res))")
        let d = max(2, best60), p = max(1, d / 2), det = min(64, d * 2)
        print("suggested tiers for this GPU class (.default ≈ the 60fps max, perf = ½, detail = 2×):")
        print("  .performance ≈ \(p)    .default ≈ \(d)    .detail ≈ \(det)")
        print("→ set these in MetalRenderer.resolveShadowSamples for this GPU bucket.")
        print("=== end ===\n")
    }
}
