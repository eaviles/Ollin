import Testing
import Metal
import simd
import AppKit
@testable import Ollin

/// A screen-space-reflections micro-benchmark, **gated by `OLLIN_BENCH=1`** so the normal test
/// suite skips it. It renders the `3D/ScreenSpaceReflections` scene (a glossy floor + scattered
/// objects, reflected through a `.screenSpaceReflections` combine) at the canvas resolution the
/// effect runs at live, across a sweep of march step counts (the per-pixel ray reach, one pixel
/// per step), prints the true per-frame GPU cost (command-buffer timestamps, vsync-independent),
/// and recommends per-tier step counts for *this* GPU. Run on each machine to tune
/// `MetalRenderer.resolveSSRSteps`.
///
/// Run via `Scripts/benchmark.sh ssr [resolution]`.
@Suite(.serialized)
struct SSRBenchmarkTests {

    /// The `3D/ScreenSpaceReflections` scene: a glossy floor under a loose scatter of spheres +
    /// a cube, reflected by `.screenSpaceReflections` reading its own depth (the realistic cost
    /// of the effect). The quality tier is irrelevant here; the benchmark drives the step count
    /// through `ssrStepsOverride`. A fixed camera azimuth keeps it deterministic.
    final class BenchScene: Sketch {
        override func draw() {
            let scene = renderTarget()
            withTarget(scene) {
                background(Color(hex: 0x06080d))
                camera(.orbiting(target: Vector3(0, 0.7, 0), radius: 10,
                                 azimuth: 0.5, elevation: 0.4,
                                 fieldOfView: .pi / 4, near: 2, far: 24))
                ambientLight(Color(white: 0.3))
                directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 0.95)
                withState {
                    fill(Color(white: 0.05)); translate(0, -0.05, 0)
                    drawBox(width: 40, height: 0.1, depth: 40)
                }
                let spheres: [(x: Double, z: Double, hue: Double)] = [
                    (-3.8, 1.5, 0.02), (3.6, 2.0, 0.33), (-1.0, -3.5, 0.58), (5.2, -2.5, 0.85),
                ]
                for s in spheres {
                    withState {
                        translate(s.x, 1.0, s.z)
                        fill(Color(hue: s.hue, saturation: 0.75, brightness: 1.0))
                        drawSphere(radius: 1.0)
                    }
                }
                withState {
                    fill(Color(hex: 0xeef0fa)); translate(-4.5, 0.7, -3.0); rotateY(0.6)
                    drawBox(width: 1.4, height: 1.4, depth: 1.4)
                }
            }
            drawImage(scene.combined(with: scene.depth,
                                     .screenSpaceReflections(intensity: 0.9, roughness: 0.15,
                                                             fresnel: 0.8)).image, 0, 0)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_BENCH"] != nil))
    @MainActor
    func ssrQualityBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let iters = 30

        // The `.screenSpaceReflections` combine runs at its layer's pixel size, the sketch's
        // canvas (a full-canvas `renderTarget` at scale 1). Tune the tier defaults against the
        // canvas resolution; OLLIN_BENCH_RES overrides.
        let canvas = Int(Sketch.defaultSize.cgSize.width)
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? canvas

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        print("\n=== Ollin screen-space-reflections benchmark ===")
        print("Mac: \(ShadowBenchmarkTests.sysctl("hw.model") ?? "?") · \(ShadowBenchmarkTests.sysctl("machdep.cpu.brand_string") ?? "?") · \(gb(ProcessInfo.processInfo.physicalMemory)) RAM · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) · \(ShadowBenchmarkTests.gpuFamily(device)) · \(device.hasUnifiedMemory ? "unified" : "discrete") memory · \(gb(device.recommendedMaxWorkingSetSize)) working set")
        print("benchmark resolution: \(res)×\(res) px  (the `.screenSpaceReflections` layer's canvas size; set OLLIN_BENCH_RES to override)\n")

        let sketch = BenchScene()
        sketch.setCanvasSize(width: Double(res), height: Double(res))
        sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(res), Float(res))
        let budget60 = 1000.0 / 60, budget120 = 1000.0 / 120

        print("  steps  |  GPU ms |  ~fps  | within")
        print("---------+---------+--------+--------")
        var best60 = 0, best120 = 0
        for n in [64, 128, 192, 256, 384, 512, 768] {
            renderer.ssrStepsOverride = n
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: res, height: res, iterations: iters)
            let fps = ms > 0 ? 1000.0 / ms : 0
            let within = ms <= 0 ? "" : ms <= budget120 ? "120fps" : ms <= budget60 ? "60fps" : ""
            print(String(format: "  %5d  | %7.2f | %6.0f | %@", n, ms, fps, within))
            if ms > 0 && ms <= budget60 { best60 = max(best60, n) }
            if ms > 0 && ms <= budget120 { best120 = max(best120, n) }
        }
        renderer.ssrStepsOverride = nil

        print("\nmax steps at ~60fps: \(best60)   at ~120fps: \(best120)   (\(res)×\(res))")
        let d = max(64, best60), p = max(32, best120 > 0 ? best120 : d / 2), det = min(1024, d * 2)
        print("suggested tiers (.default ≈ the 60fps max, perf ≈ 120fps max, detail ≈ 2×):")
        print("  .performance ≈ \(p)    .default ≈ \(d)    .detail ≈ \(det)")
        print("→ set these in MetalRenderer.resolveSSRSteps.")
        print("=== end ===\n")
    }
}
