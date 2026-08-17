@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import Metal
import simd
import Testing

/// CPU checks on instanced mesh drawing (`drawMesh(_:instances:)`): what a draw
/// records, how a placement's matrix composes, and the recording gates. The
/// rendered result is pinned by the `instanced-mesh` snapshot; the pixel
/// equivalence of the instanced path with a loop of plain `drawMesh` calls gets
/// its own Metal-gated test at the bottom.
@Suite
@MainActor
struct MeshInstanceTests {

    private let box = Mesh.box(width: 2, height: 2, depth: 2)

    // MARK: Recording

    @Test func instancedDrawRecordsLocalVerticesAndOneBatch() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        drawer.drawMeshInstanced(box, instances: [
            MeshInstance(position: Vector3(1, 0, 0)),
            MeshInstance(position: Vector3(-1, 0, 0)),
        ])
        // One batch, explicit runs: the base mesh expanded once, two placements.
        #expect(drawer.batches.map(\.kind) == [.meshInstanced])
        let batch = drawer.batches[0]
        #expect(batch.instancedVertexCount == box.indices.count)
        #expect(batch.meshInstanceCount == 2)
        #expect(drawer.meshVertices.isEmpty)   // nothing on the per-frame mesh path
        // Base vertices stay LOCAL: the box's own corners, not the placements'.
        let xs = Set(drawer.instancedMeshVertices.map { $0.position.x })
        #expect(xs == [-1, 1])
    }

    @Test func placementsComposeWithTheTransformStack() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        drawer.translate(5, 0, 0)
        drawer.drawMeshInstanced(box, instances: [MeshInstance(position: Vector3(1, 2, 3))])
        // CTM times the instance's own matrix: the translation lands at (6, 2, 3).
        let m = drawer.meshInstances[0].model
        #expect(m.columns.3.x == 6 && m.columns.3.y == 2 && m.columns.3.z == 3)
    }

    @Test func placementMatrixMatchesTheEquivalentCallSequence() {
        // The documented contract: translate, then rotateX/rotateY/rotateZ, then
        // scale, exactly as the sketch calls would compose the model matrix.
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.translate(1, 2, 3)
        drawer.rotateX(0.3)
        drawer.rotateY(0.2)
        drawer.rotateZ(0.1)
        drawer.scale(2, 1, 0.5)
        let inst = MeshInstance(position: Vector3(1, 2, 3), rotation: Vector3(0.3, 0.2, 0.1),
                                scale: Vector3(2, 1, 0.5))
        #expect(inst.matrix == drawer.modelMatrix)
    }

    @Test func tintDefaultsToWhiteAndCarriesWhenSet() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        drawer.drawMeshInstanced(box, instances: [
            MeshInstance(),
            MeshInstance(color: Color(red: 1, green: 0.5, blue: 0, alpha: 0.5)),
        ])
        #expect(drawer.meshInstances[0].color == SIMD4<Float>(1, 1, 1, 1))
        #expect(drawer.meshInstances[1].color == SIMD4<Float>(1, 0.5, 0, 0.5))
    }

    // MARK: Gates

    @Test func needsACameraAndInstances() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.drawMeshInstanced(box, instances: [MeshInstance()])   // no camera
        #expect(drawer.batches.isEmpty)
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        drawer.drawMeshInstanced(box, instances: [])                 // no placements
        #expect(drawer.batches.isEmpty)
    }

    @Test func refusedInsideABatchRecording() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        _ = drawer.makeBatch {
            drawer.drawMeshInstanced(box, instances: [MeshInstance()])
        }
        #expect(drawer.instancedMeshVertices.isEmpty)
        #expect(drawer.meshInstances.isEmpty)
    }

    @Test func gpuResidentPlacementsRideTheBatchBuffer() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        let buffer = ComputeBuffer<OllinMeshInstance>(count: 32)
        drawer.drawMeshInstanced(box, instanceBuffer: buffer, count: 32)
        let batch = drawer.batches[0]
        #expect(batch.kind == .meshInstanced)
        #expect(batch.particleBuffer === buffer)
        #expect(batch.particleCount == 32)
        #expect(batch.meshInstanceCount == 0)
        #expect(batch.instancedVertexCount == box.indices.count)
    }
}

/// GPU equivalence: the instanced path renders the same picture as a loop of
/// plain `drawMesh` calls over the same placements, lit, tinted, non-uniformly
/// scaled, and casting into the directional shadow map. The two paths compute
/// world positions and normals in a different order (CPU bake vs per-vertex GPU
/// placement, inverse-transpose vs adjugate normals), so the comparison carries
/// a small tolerance rather than demanding equal bytes.
@Suite(.serialized)
@MainActor
struct MeshInstanceRenderTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func instancedFieldMatchesThePerMeshLoop() throws {
        let instanced = try #require(OllinApp.image(of: InstancedABSketch(instanced: true)))
        let looped = try #require(OllinApp.image(of: InstancedABSketch(instanced: false)))
        let diff = try #require(imageDifference(instanced, looped))
        #expect(diff.mean < 0.5,
                "instanced vs per-mesh mean difference \(diff.mean) (max \(diff.max))")
        #expect(diff.max <= 32,
                "instanced vs per-mesh max difference \(diff.max) (mean \(diff.mean))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func instancedShadowPipelinesBuild() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        // The cube (point) leg only runs on a device without ray tracing, so on
        // an RT machine nothing else would ever compile these; building them
        // here keeps a shader break from hiding until it reaches such a device.
        _ = try renderer.pipeline(.meshInstancedShadow)
        _ = try renderer.pipeline(.meshInstancedPointShadowMin)
        _ = try renderer.pipeline(.meshInstancedPointShadowMax)
        _ = try renderer.pipeline(.meshInstanced(.normal, depth: .depth32Float))
    }
}

/// The cost story, measured (`Scripts/benchmark.sh`, OLLIN_BENCH=1): a
/// 12,000-pillar field recorded per frame, instanced vs one `drawMesh` per
/// copy, CPU record time and GPU frame time side by side.
@Suite(.serialized)
@MainActor
struct MeshInstanceBenchmarkTests {

    @Test(.benchmark)
    func fieldCostInstancedVsLooped() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let res = 1080
        let viewport = SIMD2<Float>(Float(res), Float(res))
        let frames = 30

        func measure(instanced: Bool) -> (cpuMs: Double, gpuMs: Double, copies: Int) {
            let sketch = InstancedBenchScene(instanced: instanced)
            sketch.setCanvasSize(width: Double(res), height: Double(res))
            sketch.setup()
            var t = 1.0
            sketch.advance(time: t, deltaTime: 1 / 60, frameRate: 60)
            sketch.performDraw()   // warm the arrays
            let start = ContinuousClock.now
            for _ in 0 ..< frames {
                t += 1 / 60
                sketch.advance(time: t, deltaTime: 1 / 60, frameRate: 60)
                sketch.performDraw()
            }
            let cpu = Double((ContinuousClock.now - start) / .milliseconds(1)) / Double(frames)
            let gpu = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                        width: res, height: res,
                                                        iterations: frames)
            return (cpu, gpu, sketch.copies)
        }

        let inst = measure(instanced: true)
        let loop = measure(instanced: false)
        print("\n=== Ollin instanced-mesh benchmark (\(inst.copies) copies, \(res)² px, lit + shadows) ===")
        print(String(format: "instanced: CPU record %6.2f ms/frame · GPU %6.2f ms", inst.cpuMs, inst.gpuMs))
        print(String(format: "per-mesh:  CPU record %6.2f ms/frame · GPU %6.2f ms", loop.cpuMs, loop.gpuMs))
        print(String(format: "CPU record win: %.0fx", loop.cpuMs / max(inst.cpuMs, 0.0001)))
        print("=== end ===\n")
    }
}

/// The benchmark's field: the example's 12,000-pillar wave at 1080², rebuilt
/// per frame on both paths, so the numbers measure exactly what the example's
/// knob toggles.
@MainActor
private final class InstancedBenchScene: Sketch {
    private let instanced: Bool
    private(set) var copies = 0
    private var seats: [(x: Double, z: Double, r: Double, a: Double)] = []

    init(instanced: Bool) {
        self.instanced = instanced
        super.init()
    }

    required init() {
        self.instanced = true
        super.init()
    }

    override func setup() {
        seed(90_210)
        var r = 1.4
        while r < 10.5 {
            let count = Int(r * 50)
            for i in 0 ..< count {
                let a = Double(i) / Double(count) * .tau + random(-0.02, 0.02)
                let rr = r + random(-0.06, 0.06)
                seats.append((cos(a) * rr, sin(a) * rr, rr, a))
            }
            r += 0.22
        }
        copies = seats.count
    }

    override func draw() {
        background(Color(hex: 0x0E1016))
        camera(Camera3D(eye: Vector3(10, 9, 12), target: Vector3(0, 0.9, 0)))
        ambientLight(Color(white: 0.14))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()
        withState {
            fill(Color(white: 0.78))
            drawPlane(width: 26, depth: 26)
        }
        specular(0.25)
        shininess(36)
        fill(Color(white: 0.8))
        let pillar = Mesh.box(width: 0.11, height: 1, depth: 0.11)
        func height(_ s: (x: Double, z: Double, r: Double, a: Double)) -> Double {
            0.25 + (sin(s.r * 1.15 - time * 1.6) * 0.5 + 0.5) * 2
        }
        if instanced {
            var placements: [MeshInstance] = []
            placements.reserveCapacity(seats.count)
            for s in seats {
                let h = height(s)
                placements.append(MeshInstance(position: Vector3(s.x, h / 2, s.z),
                                               scale: Vector3(1, h, 1)))
            }
            drawMesh(pillar, instances: placements)
        } else {
            for s in seats {
                let h = height(s)
                withState {
                    translate(s.x, h / 2, s.z)
                    scale(1, h, 1)
                    drawMesh(pillar)
                }
            }
        }
    }
}

/// One fixture, two paths: a small pillar field with rotations, non-uniform
/// scales, and per-copy tints, over a floor, lit and shadowed, drawn either as
/// one instanced call or as one `drawMesh` per copy.
@MainActor
private final class InstancedABSketch: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let instanced: Bool

    init(instanced: Bool) {
        self.instanced = instanced
        super.init()
    }

    required init() {
        self.instanced = true
        super.init()
    }

    override func draw() {
        background(Color(hex: 0x101218))
        camera(Camera3D(eye: Vector3(6, 6, 9), target: Vector3(0, 0.8, 0)))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()

        withState {
            fill(Color(white: 0.8))
            drawPlane(width: 14, depth: 14)
        }

        specular(0.3)
        shininess(32)
        fill(Color(hex: 0xB8C4E8))

        let pillar = Mesh.box(width: 0.5, height: 1, depth: 0.5)
        var placements: [MeshInstance] = []
        for i in 0 ..< 40 {
            let a = Double(i) / 40 * .tau
            let r = 1.4 + Double(i % 5) * 0.55
            let h = 0.6 + Double((i * 7) % 11) * 0.22
            placements.append(MeshInstance(
                position: Vector3(cos(a) * r, h / 2, sin(a) * r),
                rotation: Vector3(0, a, 0),
                scale: Vector3(1, h, 0.7),
                color: Color(red: 0.6 + 0.4 * cos(a), green: 0.7, blue: 1, alpha: 1)))
        }

        if instanced {
            drawMesh(pillar, instances: placements)
        } else {
            // The per-copy tint multiplies the surface color on the instanced
            // path; the loop reproduces that by baking the product into `fill`.
            let base = Color(hex: 0xB8C4E8)
            for p in placements {
                withState {
                    translate(p.position.x, p.position.y, p.position.z)
                    rotateY(p.rotation.y)
                    scale(p.scale.x, p.scale.y, p.scale.z)
                    if let c = p.color {
                        fill(Color(red: base.red * c.red, green: base.green * c.green,
                                   blue: base.blue * c.blue, alpha: base.alpha * c.alpha))
                    }
                    drawMesh(pillar)
                }
            }
        }
    }
}

/// Mean and max per-channel byte difference between two same-size images, both
/// drawn into tightly-packed RGBA8 so the comparison ignores each `CGImage`'s
/// own sample layout.
@MainActor
private func imageDifference(_ a: CGImage, _ b: CGImage) -> (mean: Double, max: Int)? {
    func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: ptr, count: w * h * 4))
    }
    guard a.width == b.width, a.height == b.height,
          let ab = rgba(a), let bb = rgba(b) else { return nil }
    var total = 0, worst = 0
    for i in ab.indices {
        let d = abs(Int(ab[i]) - Int(bb[i]))
        total += d
        worst = Swift.max(worst, d)
    }
    return (Double(total) / Double(ab.count), worst)
}
