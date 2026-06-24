import Testing
import Metal
import simd
import AppKit
@testable import Ollin

/// An ambient-occlusion micro-benchmark, **gated by `OLLIN_BENCH=1`** so the normal test
/// suite skips it. It renders the `3D/AmbientOcclusion` scene (a packed block field grounded
/// by its own depth buffer through an `.ambientOcclusion` combine) at the canvas resolution
/// the effect actually runs at live, across a sweep of hemisphere sample counts, prints the
/// true per-frame GPU cost (from command-buffer timestamps, so it's vsync-independent), and
/// recommends per-tier sample counts for *this* GPU. Run it on each machine to tune
/// `MetalRenderer.resolveSSAOSamples`.
///
/// Run via `Scripts/benchmark.sh ssao [resolution]`.
@Suite(.serialized)
struct SSAOBenchmarkTests {

    /// The `3D/AmbientOcclusion` scene: a 6×6 block field on a ground plane, drawn into a
    /// depth-capturing target and occluded by `.ambientOcclusion` reading its own depth, the
    /// realistic cost of the effect. The quality tier is irrelevant here; the benchmark drives
    /// the sample count through `ssaoSamplesOverride`. A fixed camera azimuth keeps it
    /// deterministic.
    final class BenchScene: Sketch {
        override func draw() {
            let scene = renderTarget()
            withTarget(scene) {
                background(Color(hex: 0x121318))
                camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 9,
                                 azimuth: 0.6, elevation: 0.5,
                                 fieldOfView: .pi / 4, near: 3, far: 18))
                ambientLight(Color(white: 0.55))
                directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 0.7)
                withState {
                    fill(Color(white: 0.8)); translate(0, -0.2, 0)
                    drawBox(width: 16, height: 0.4, depth: 16)
                }
                let n = 6, cell = 1.1, box = 0.86
                for ix in 0 ..< n {
                    for iz in 0 ..< n {
                        let fx = Double(ix) - Double(n - 1) / 2
                        let fz = Double(iz) - Double(n - 1) / 2
                        let h = 0.5 + 1.6 * noise(Double(ix) * 0.6, Double(iz) * 0.6)
                        withState {
                            translate(fx * cell, h / 2, fz * cell)
                            fill(Color(hue: 0.07 + 0.5 * noise(fx, fz), saturation: 0.4, brightness: 0.95))
                            drawBox(width: box, height: h, depth: box)
                        }
                    }
                }
            }
            let ao = scene.combined(with: scene.depth,
                                    .ambientOcclusion(radius: 0.5, intensity: 1.0))
            drawImage(ao.image, 0, 0)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_BENCH"] != nil))
    @MainActor
    func ssaoQualityBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let iters = 30

        // The `.ambientOcclusion` combine runs at its layer's pixel size, which is the
        // sketch's *canvas* (a full-canvas `renderTarget` at scale 1), not the window
        // drawable. So tune the tier defaults against the canvas resolution. OLLIN_BENCH_RES
        // overrides.
        let canvas = Int(Sketch.defaultSize.cgSize.width)
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? canvas

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let hw = device.supportsFamily(.apple9)
        print("\n=== Ollin ambient-occlusion benchmark ===")
        print("Mac: \(ShadowBenchmarkTests.sysctl("hw.model") ?? "?") · \(ShadowBenchmarkTests.sysctl("machdep.cpu.brand_string") ?? "?") · \(gb(ProcessInfo.processInfo.physicalMemory)) RAM · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) · \(ShadowBenchmarkTests.gpuFamily(device)) · \(device.hasUnifiedMemory ? "unified" : "discrete") memory · \(gb(device.recommendedMaxWorkingSetSize)) working set")
        print("tier bucket: \(hw ? "Apple9+ (M3/A17 and up)" : "software-RT (M1/M2)"); resolveSSAOSamples is hardware-independent today, this sweep says whether it should scale")
        print("benchmark resolution: \(res)×\(res) px  (the `.ambientOcclusion` layer's canvas size; set OLLIN_BENCH_RES to override)\n")

        let sketch = BenchScene()
        sketch.setCanvasSize(width: Double(res), height: Double(res))
        sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(res), Float(res))
        let budget60 = 1000.0 / 60, budget120 = 1000.0 / 120

        print(" samples |  GPU ms |  ~fps  | within")
        print("---------+---------+--------+--------")
        var best60 = 0, best120 = 0
        for n in [8, 16, 24, 32, 48, 64, 96, 128] {
            renderer.ssaoSamplesOverride = n
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: res, height: res, iterations: iters)
            let fps = ms > 0 ? 1000.0 / ms : 0
            let within = ms <= 0 ? "" : ms <= budget120 ? "120fps" : ms <= budget60 ? "60fps" : ""
            print(String(format: "  %5d  | %7.2f | %6.0f | %@", n, ms, fps, within))
            if ms > 0 && ms <= budget60 { best60 = max(best60, n) }
            if ms > 0 && ms <= budget120 { best120 = max(best120, n) }
        }
        renderer.ssaoSamplesOverride = nil

        print("\nmax samples at ~60fps: \(best60)   at ~120fps: \(best120)   (\(res)×\(res))")
        let d = max(16, best60), p = max(8, d / 2), det = min(256, d * 2)
        print("suggested tiers for this GPU bucket (.default ≈ the 60fps max, perf ≈ ½, detail ≈ 2×):")
        print("  .performance ≈ \(p)    .default ≈ \(d)    .detail ≈ \(det)")
        print("→ set these in MetalRenderer.resolveSSAOSamples (make it hardware-relative if the columns differ).")
        print("=== end ===\n")
    }
}
