import Testing
import Metal
import simd
import AppKit
@testable import Ollin

/// A soft-shadow micro-benchmark — **gated by `OLLIN_BENCH=1`** so the normal test suite
/// skips it. It renders a representative shadow scene at a Retina-ish resolution across a
/// sweep of ray counts, prints the true per-frame GPU cost (from command-buffer timestamps,
/// so it's vsync-independent), and recommends per-tier ray counts for *this* GPU. Run it on
/// each machine (Intel / M-series) to tune `MetalRenderer.resolveShadowSamples`.
///
/// Run via `Scripts/benchmark.sh shadows [resolution]`.
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

    /// Read a sysctl string value (e.g. `hw.model`, `machdep.cpu.brand_string`).
    static func sysctl(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// The GPU's highest Metal feature family — Apple9+ (M3/A17) is the dedicated-RT tell.
    static func gpuFamily(_ d: MTLDevice) -> String {
        if d.supportsFamily(.apple9) { return "Apple9 (M3/A17 and up)" }
        if d.supportsFamily(.apple8) { return "Apple8 (M2/A15–A16)" }
        if d.supportsFamily(.apple7) { return "Apple7 (M1/A14)" }
        if d.supportsFamily(.mac2)   { return "Mac2 (Intel/AMD)" }
        return "unknown family"
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_BENCH"] != nil))
    @MainActor
    func shadowQualityBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let rt = device.supportsRaytracing && device.supportsRaytracingFromRender
        let iters = 30

        // The render resolution a *default sketch* actually uses live: its `.auto` window
        // (the largest clean fraction of the default 1080² canvas that fits the screen)
        // times the display's backing scale. The live path rasterises at that drawable, not
        // at the canvas (`--export` is the one that renders at the 1080² canvas), so this is
        // the size the quality-tier defaults should be tuned against. OLLIN_BENCH_RES overrides.
        let canvasPt = Sketch.defaultSize.cgSize
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let windowPt = OllinApp.windowSize(fitting: canvasPt)
        let liveDrawable = Int((windowPt.height * scale).rounded())
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? liveDrawable

        var displayLine = "main display: none detected (headless)"
        if let screen = NSScreen.screens.first {
            let pt = screen.frame.size, s = screen.backingScaleFactor
            displayLine = "main display: \(Int(pt.width))×\(Int(pt.height)) pt @ \(s)× = \(Int((pt.width * s).rounded()))×\(Int((pt.height * s).rounded())) px"
        }

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        print("\n=== Ollin shadow benchmark ===")
        print("Mac: \(Self.sysctl("hw.model") ?? "?") · \(Self.sysctl("machdep.cpu.brand_string") ?? "?") · \(gb(ProcessInfo.processInfo.physicalMemory)) RAM · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) · \(Self.gpuFamily(device)) · \(device.hasUnifiedMemory ? "unified" : "discrete") memory · \(gb(device.recommendedMaxWorkingSetSize)) working set\(device.isLowPower ? " · low-power" : "")")
        print("ray tracing: supportsRaytracing=\(device.supportsRaytracing), fromRender=\(device.supportsRaytracingFromRender), hardware-RT(apple9+)=\(device.supportsFamily(.apple9))")
        print("shadow path: \(rt ? "RAY-TRACED — the quality tiers apply" : "mid-point CUBE fallback — tiers inert (no rays)")")
        print(displayLine)
        print("default sketch: \(Int(canvasPt.width))² canvas → .auto window \(Int(windowPt.width))×\(Int(windowPt.height)) pt @ \(scale)× = \(liveDrawable)² px live drawable  (--export renders at the \(Int(canvasPt.width))² canvas instead)")
        print("benchmark resolution: \(res)×\(res) px  (the default sketch's live drawable; set OLLIN_BENCH_RES to override)\n")

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
