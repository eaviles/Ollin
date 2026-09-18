import Testing
import Metal
import simd
import COllinShaders
@testable import Ollin

/// What the light grid buys, **gated by `OLLIN_BENCH=1`** so the normal suite skips
/// it. It renders one courtyard of lamps at a sweep of lamp counts, twice per count:
/// once with the grid culling and once with every tile taking every light, which is
/// brute-force forward lighting through the same shading code. Both numbers come out
/// of one process, alternating, because a per-process figure drifts by tens of
/// percent and an A against a B measured in another run says nothing.
///
/// The picture is identical either way (`ManyLightsTests` renders both and compares
/// the bytes), so the difference in the two columns is the whole cost of shading
/// lights that could not arrive.
///
/// Run via `Scripts/benchmark.sh lights [resolution]`.
@Suite(.serialized)
struct ManyLightsBenchmarkTests {

    /// A courtyard of blocks under `lamps` point lights, each reaching `reach`. The
    /// lamps sit on a grid over the whole floor, so at every count they are spread
    /// rather than piled: a pile would cull to the same list a brute force walks and
    /// the sweep would measure nothing.
    final class BenchScene: Sketch {
        var lamps = 64
        var reach = 11.0

        override func draw() {
            background(.black)
            ambientLight(Color(white: 0.02))
            camera(.perspective(eye: Vector3(0, 31, 46), target: Vector3(0, 1.5, 0),
                                fieldOfView: .pi / 4.2))
            let side = Int(Double(lamps).squareRoot().rounded(.up))
            for i in 0..<lamps {
                let x = (Double(i % side) / Double(max(side - 1, 1)) - 0.5) * 50
                let z = (Double(i / side) / Double(max(side - 1, 1)) - 0.5) * 50
                pointLight(Color(hue: Double(i) / Double(lamps), saturation: 0.8, brightness: 1),
                           at: Vector3(x, 2.4, z), intensity: 1.7, reach: reach)
            }
            fill(Color(white: 0.52))
            withState {
                translate(0, -0.05, 0)
                drawBox(width: 130, height: 0.1, depth: 130)
            }
            fill(Color(white: 0.64))
            for row in stride(from: -25.0, through: 25.0, by: 5.0) {
                for column in stride(from: -25.0, through: 25.0, by: 5.0) {
                    withState {
                        translate(column, 1.2, row)
                        drawBox(width: 2.6, height: 2.4, depth: 2.6)
                    }
                }
            }
        }
    }

    @Test(.benchmark)
    @MainActor
    func lightGridBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let iters = 30
        let canvas = Int(Sketch.defaultSize.cgSize.width)
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? canvas

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        print("\n=== Ollin light-grid benchmark ===")
        print("Mac: \(ShadowBenchmarkTests.sysctl("hw.model") ?? "?") · \(ShadowBenchmarkTests.sysctl("machdep.cpu.brand_string") ?? "?") · \(gb(ProcessInfo.processInfo.physicalMemory)) RAM · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) · \(ShadowBenchmarkTests.gpuFamily(device)) · \(device.hasUnifiedMemory ? "unified" : "discrete") memory")
        print("benchmark resolution: \(res)×\(res) px  (set OLLIN_BENCH_RES to override)\n")

        let viewport = SIMD2<Float>(Float(res), Float(res))
        print("  lamps |  culled |   every | saved")
        print("--------+---------+---------+-------")
        for lamps in [8, 16, 32, 64, 128] {
            var times: [Bool: Double] = [:]
            // Alternate inside the one process: the same scene, the same renderer, the
            // two lists.
            for culls in [true, false] {
                let sketch = BenchScene()
                sketch.lamps = lamps
                sketch.setCanvasSize(width: Double(res), height: Double(res))
                sketch.setup()
                sketch.drawer.cullsLightTiles = culls
                sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
                sketch.performDraw()
                times[culls] = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                                 width: res, height: res,
                                                                 iterations: iters)
            }
            let culled = times[true] ?? 0, every = times[false] ?? 0
            let saved = every > 0 ? (1 - culled / every) * 100 : 0
            print(String(format: "  %5d | %7.2f | %7.2f | %4.0f%%", lamps, culled, every, saved))
        }
        print("\n(a frame of \(Int(OLLIN_MAX_LIGHTS)) lights or fewer never builds a grid at all,")
        print(" so the first row is the inline path measured against itself.)")
        print("=== end ===\n")
    }
}

/// What per-batch lighting costs, and what it buys, **gated by `OLLIN_BENCH=1`**.
/// A hall of rooms, each with its own lamps, drawn two ways at the same geometry and
/// the same total lamp count: as one light set holding every lamp (what a frame could
/// do before), and as one set per room. Both numbers come out of one process,
/// alternating, because a per-process figure drifts by tens of percent.
///
/// There are two effects pulling opposite ways, which is why this is worth measuring
/// rather than guessing. Splitting costs batches: a room's meshes cannot merge with
/// the next room's, so each set is its own run with its own uniform, and past the
/// inline count each is its own tile cull. Splitting also saves shading: a room's
/// surfaces pay for its own lamps rather than every lamp in the hall.
///
/// Run via `Scripts/benchmark.sh lightsets [resolution]`.
@Suite(.serialized)
struct LightSetBenchmarkTests {

    /// `rooms` rooms in a row, each a box on a strip of floor with `lampsPerRoom`
    /// point lights over it. `split` draws each room under its own light set; with it
    /// off every lamp goes into the frame's one set, which is what a frame held
    /// before per-batch lighting. The two draw the same geometry and the same lamps.
    final class RoomsScene: Sketch {
        var rooms = 8
        var lampsPerRoom = 2
        var split = true

        private func lamps(of room: Int) -> [Light] {
            let x = (Double(room) / Double(max(rooms - 1, 1)) - 0.5) * 60
            return (0..<lampsPerRoom).map { k in
                .point(Color(hue: Double(room) / Double(rooms), saturation: 0.7, brightness: 1),
                       at: Vector3(x, 3 + Double(k) * 0.6, Double(k) * 2 - 1),
                       intensity: 1.7)
            }
        }

        private func room(_ index: Int) {
            let x = (Double(index) / Double(max(rooms - 1, 1)) - 0.5) * 60
            fill(Color(white: 0.55))
            withState { translate(x, -0.05, 0); drawBox(width: 7, height: 0.1, depth: 12) }
            fill(Color(white: 0.7))
            for k in 0..<4 {
                withState {
                    translate(x + Double(k % 2) * 2 - 1, 1.1, Double(k / 2) * 4 - 2)
                    drawBox(width: 1.8, height: 2.0, depth: 1.8)
                }
            }
        }

        override func draw() {
            background(.black)
            camera(.perspective(eye: Vector3(0, 26, 40), target: Vector3(0, 1.5, 0),
                                fieldOfView: .pi / 4.2))
            noLights()
            ambientLight(Color(white: 0.02))
            if split {
                for i in 0..<rooms {
                    withLights(lamps(of: i), ambient: Color(white: 0.02)) { room(i) }
                }
            } else {
                for i in 0..<rooms { for lamp in lamps(of: i) { addLight(lamp) } }
                for i in 0..<rooms { room(i) }
            }
        }
    }

    @Test(.benchmark)
    @MainActor
    func lightSetBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("benchmark: no Metal device"); return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let iters = 30
        let canvas = Int(Sketch.defaultSize.cgSize.width)
        let res = Int(ProcessInfo.processInfo.environment["OLLIN_BENCH_RES"] ?? "") ?? canvas

        func gb(_ bytes: UInt64) -> String { String(format: "%.0f GB", Double(bytes) / 1_073_741_824) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        print("\n=== Ollin per-batch lighting benchmark ===")
        print("Mac: \(ShadowBenchmarkTests.sysctl("hw.model") ?? "?") - \(ShadowBenchmarkTests.sysctl("machdep.cpu.brand_string") ?? "?") - \(gb(ProcessInfo.processInfo.physicalMemory)) RAM - macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        print("GPU: \(device.name) - \(ShadowBenchmarkTests.gpuFamily(device)) - \(device.hasUnifiedMemory ? "unified" : "discrete") memory")
        print("benchmark resolution: \(res)x\(res) px  (set OLLIN_BENCH_RES to override)\n")

        let viewport = SIMD2<Float>(Float(res), Float(res))
        print("  rooms | lamps | one set | per room | change | batches")
        print("--------+-------+---------+----------+--------+--------")
        for (rooms, perRoom) in [(2, 2), (4, 2), (8, 2), (4, 4), (8, 8)] {
            var times: [Bool: Double] = [:]
            var batches: [Bool: Int] = [:]
            for split in [false, true] {
                let sketch = RoomsScene()
                sketch.rooms = rooms
                sketch.lampsPerRoom = perRoom
                sketch.split = split
                sketch.setCanvasSize(width: Double(res), height: Double(res))
                sketch.setup()
                sketch.advance(time: 1, deltaTime: 1.0 / 60, frameRate: 60)
                sketch.performDraw()
                batches[split] = sketch.drawer.batches.count
                times[split] = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                                 width: res, height: res,
                                                                 iterations: iters)
            }
            let one = times[false] ?? 0, many = times[true] ?? 0
            let change = one > 0 ? (many / one - 1) * 100 : 0
            print(String(format: "  %5d | %5d | %7.2f | %8.2f | %+5.0f%% | %d vs %d",
                         rooms, rooms * perRoom, one, many, change,
                         batches[false] ?? 0, batches[true] ?? 0))
        }
        print("\n(one set: every lamp in the hall lights every surface. per room: each")
        print(" room's surfaces read its own lamps alone, which is a different picture")
        print(" as well as a different cost.)")
        print("=== end ===\n")
    }
}
