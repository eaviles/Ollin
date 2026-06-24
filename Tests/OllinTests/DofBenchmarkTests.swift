import Testing
import Metal
import simd
import AppKit
@testable import Ollin

/// A depth-of-field micro-benchmark — **gated by `OLLIN_BENCH=1`** so the normal test suite
/// skips it. It renders the `Effects/Defocus` scene (an orb field through a `.defocus` combine)
/// at the canvas resolution the layer actually runs at live, across a sweep of bokeh tap
/// counts, prints the true per-frame GPU cost (from command-buffer timestamps, so it's
/// vsync-independent), and recommends per-tier tap counts for *this* GPU. Run it on each
/// machine to tune `MetalRenderer.resolveDofTaps`.
///
/// Run via `Scripts/benchmark.sh dof [resolution]`.
@Suite(.serialized)
struct DofBenchmarkTests {

    /// The `Effects/Defocus` scene: an orb field drawn into a layer, defocused by a matching
    /// per-orb depth map — the realistic cost of the effect. The `.defocus` quality is
    /// irrelevant here; the benchmark drives the tap count through `dofTapsOverride`.
    final class BenchScene: Sketch {
        struct Orb { let depth, x, y, hue: Double }
        lazy var orbs: [Orb] = {
            seed(7)
            return (0 ..< 48).map { _ in
                Orb(depth: random(1), x: random(1), y: random(1), hue: random(1))
            }.sorted { $0.depth > $1.depth }
        }()
        func radius(_ orb: Orb) -> Double { 26 + (1 - orb.depth) * 96 }

        override func draw() {
            compose {
                layer {
                    background(Color(white: 0.05))
                    noStroke()
                    for orb in orbs {
                        fill(Color(hue: orb.hue, saturation: 0.7, brightness: 0.45 + 0.55 * (1 - orb.depth)))
                        drawCircle(orb.x * width, orb.y * height, radius(orb))
                    }
                }
                .defocused(by: aside {
                    background(.white)
                    noStroke()
                    for orb in orbs { fill(Color(white: orb.depth)); drawCircle(orb.x * width, orb.y * height, radius(orb)) }
                }, focus: 0.5, range: 0.07, maxBlur: 36)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_BENCH"] != nil))
    @MainActor
    func dofQualityBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let iters = 30

        // The `.defocus` combine runs at the layer's pixel size, which is the sketch's
        // *canvas* (full-canvas `renderTarget` at scale 1) — not the window drawable. So the
        // live DoF cost is at the canvas resolution; tune the tier defaults against that.
        // OLLIN_BENCH_RES overrides.
        let canvas = Int(Sketch.defaultSize.cgSize.width)
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? canvas

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let hw = device.supportsFamily(.apple9)
        print("\n=== Ollin depth-of-field benchmark ===")
        print("Mac: \(ShadowBenchmarkTests.sysctl("hw.model") ?? "?") · \(ShadowBenchmarkTests.sysctl("machdep.cpu.brand_string") ?? "?") · \(gb(ProcessInfo.processInfo.physicalMemory)) RAM · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) · \(ShadowBenchmarkTests.gpuFamily(device)) · \(device.hasUnifiedMemory ? "unified" : "discrete") memory · \(gb(device.recommendedMaxWorkingSetSize)) working set")
        print("tier bucket: \(hw ? "dedicated-RT (Apple9+) — the hw column of resolveDofTaps" : "software-RT (M1/M2) — the non-hw column of resolveDofTaps")")
        print("benchmark resolution: \(res)×\(res) px  (the `.defocus` layer's canvas size; set OLLIN_BENCH_RES to override)\n")

        let sketch = BenchScene()
        sketch.setCanvasSize(width: Double(res), height: Double(res))
        sketch.setup()
        sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let viewport = SIMD2<Float>(Float(res), Float(res))
        let budget60 = 1000.0 / 60, budget120 = 1000.0 / 120

        print(" taps |  GPU ms |  ~fps  | within")
        print("------+---------+--------+--------")
        var best60 = 0, best120 = 0
        for n in [16, 32, 64, 96, 128, 192, 256, 384, 512] {
            renderer.dofTapsOverride = n
            let ms = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                       width: res, height: res, iterations: iters)
            let fps = ms > 0 ? 1000.0 / ms : 0
            let within = ms <= 0 ? "" : ms <= budget120 ? "120fps" : ms <= budget60 ? "60fps" : ""
            print(String(format: "  %3d | %7.2f | %6.0f | %@", n, ms, fps, within))
            if ms > 0 && ms <= budget60 { best60 = max(best60, n) }
            if ms > 0 && ms <= budget120 { best120 = max(best120, n) }
        }
        renderer.dofTapsOverride = nil

        print("\nmax taps at ~60fps: \(best60)   at ~120fps: \(best120)   (\(res)×\(res))")
        let d = max(32, best60), p = max(16, d / 2), det = min(512, d * 2)
        print("suggested tiers for this GPU bucket (.default ≈ the 60fps max, perf ≈ ½, detail ≈ 2×):")
        print("  .performance ≈ \(p)    .default ≈ \(d)    .detail ≈ \(det)")
        print("→ set these in MetalRenderer.resolveDofTaps for the \(hw ? "hw" : "non-hw") column.")
        print("=== end ===\n")
    }
}
