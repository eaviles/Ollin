@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import Metal
import simd
import Testing

/// CPU checks on the retained `MeshField` (place, the entry table, the
/// once-per-frame gate); the GPU behavior gets its Metal-gated suite below.
@Suite
@MainActor
struct MeshFieldTests {

    private let box = Mesh.box(width: 2, height: 2, depth: 2)

    @Test func placeBuildsEntriesAndCopies() {
        let field = MeshField()
        field.place(box, at: [MeshInstance(), MeshInstance(position: Vector3(3, 0, 0))])
        field.place(Mesh.sphere(radius: 1), at: [MeshInstance(position: Vector3(0, 2, 0))])
        #expect(field.entryCount == 2)
        #expect(field.copyCount == 3)
        let first = field.entries[0], second = field.entries[1]
        #expect(first.vertexStart == 0)
        #expect(Int(first.vertexCount) == box.indices.count)
        #expect(Int(second.vertexStart) == box.indices.count)
        #expect(first.copyStart == 0 && first.copyCount == 2)
        #expect(second.copyStart == 2 && second.copyCount == 1)
        // Compact regions tile the copy list exactly, so entries never collide.
        #expect(first.compactOffset == 0 && second.compactOffset == 2)
        // The box's local bounding sphere: corner distance sqrt(3).
        #expect(abs(first.radius - Float(3.0.squareRoot())) < 1e-4)
    }

    @Test func placementsKeepTheirMatricesAndTints() {
        let field = MeshField()
        field.place(box, at: [MeshInstance(position: Vector3(1, 2, 3),
                                           color: Color(red: 1, green: 0.5, blue: 0, alpha: 1))])
        let inst = field.instances[0]
        #expect(inst.model.columns.3.x == 1 && inst.model.columns.3.y == 2 && inst.model.columns.3.z == 3)
        #expect(inst.color == SIMD4<Float>(1, 0.5, 0, 1))
    }

    @Test func emptyPlacesAreIgnored() {
        let field = MeshField()
        field.place(box, at: [])
        field.place(Mesh(positions: [], indices: []), at: [MeshInstance()])
        #expect(field.isEmpty)
    }

    @Test func drawRecordsOneBatchOncePerFrame() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        let field = MeshField()
        field.place(box, at: [MeshInstance()])
        drawer.translate(5, 0, 0)
        drawer.drawMeshField(field)
        drawer.drawMeshField(field)   // second draw in one frame: skipped, noted
        let fieldBatches = drawer.batches.filter { $0.kind == .meshField }
        #expect(fieldBatches.count == 1)
        #expect(fieldBatches[0].field === field)
        // The draw-time CTM rides the batch, not the copies.
        #expect(fieldBatches[0].fieldTransform.columns.3.x == 5)
        #expect(field.instances[0].model.columns.3.x == 0)
    }

    @Test func refusedInsideABatchRecordingAndWithoutACamera() {
        let drawer = Drawer()
        drawer.beginFrame()
        let field = MeshField()
        field.place(box, at: [MeshInstance()])
        drawer.drawMeshField(field)                       // no camera
        #expect(drawer.batches.isEmpty)
        drawer.camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        _ = drawer.makeBatch { drawer.drawMeshField(field) }
        #expect(!drawer.batches.contains { $0.kind == .meshField })
    }
}

/// GPU behavior: the field renders like the equivalent instanced draws, and
/// culling changes NOTHING in the picture (a culled copy was off-screen by
/// definition), only the work.
@Suite(.serialized)
@MainActor
struct MeshFieldRenderTests {

    /// The culled field's frame, rendered once this run: both probes compare against it.
    private static var culledField: CGImage?

    private func culledFieldFrame() throws -> CGImage {
        if let known = Self.culledField { return known }
        let image = try #require(OllinApp.image(of: FieldABSketch(mode: .field)))
        Self.culledField = image
        return image
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldMatchesTheEquivalentInstancedDraws() throws {
        let field = try culledFieldFrame()
        let instanced = try #require(OllinApp.image(of: FieldABSketch(mode: .instanced)))
        let diff = try #require(fieldImageDifference(field, instanced))
        #expect(diff.mean < 0.5,
                "field vs instanced mean difference \(diff.mean) (max \(diff.max))")
        #expect(diff.max <= 32,
                "field vs instanced max difference \(diff.max) (mean \(diff.mean))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func cullingChangesNothingInThePicture() throws {
        // The camera deliberately sees only part of the field, so culling has
        // real work to skip; the picture must not know the difference. Not a
        // pixel of it: an export compacts the visible copies in copy order, the
        // order the unculled field draws them in, so copies meeting at equal
        // depth resolve the same way in both.
        let culled = try culledFieldFrame()
        let unculled = try #require(OllinApp.image(of: FieldABSketch(mode: .fieldUnculled)))
        let diff = try #require(fieldImageDifference(culled, unculled))
        #expect(diff.max == 0,
                "culling changed the picture: max \(diff.max) (mean \(diff.mean))")
    }

    /// An export compacts each entry's visible copies in copy order. Read off
    /// the GPU rather than seen in pixels: order shows in a picture only where
    /// copies meet at exactly the same depth, and the small fixture above has
    /// none, while a few thousand copies racing one counter leave the live
    /// cull's arrival order plain in the buffer.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportCompactsEachEntryInCopyOrder() throws {
        let sketch = FieldOrderProbe()
        _ = try #require(OllinApp.image(of: sketch))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let gpu = try #require(sketch.field.gpuResources(for: device))
        // The compacted indices live in private storage, so copy them out.
        let queue = try #require(device.makeCommandQueue())
        let readable = try #require(device.makeBuffer(length: gpu.compacted.length,
                                                      options: .storageModeShared))
        let commands = try #require(queue.makeCommandBuffer())
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: gpu.compacted, sourceOffset: 0, to: readable, destinationOffset: 0,
                  size: gpu.compacted.length)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let counts = gpu.counts.contents().bindMemory(to: UInt32.self, capacity: gpu.entryCount)
        let compacted = readable.contents().bindMemory(to: UInt32.self,
                                                       capacity: gpu.compacted.length / 4)
        var drawn = 0
        for (e, entry) in sketch.field.entries.enumerated() {
            let n = Int(counts[e])
            drawn += n
            let slice = (0 ..< n).map { compacted[Int(entry.compactOffset) + $0] }
            #expect(slice == slice.sorted(), "entry \(e) is out of copy order")
            #expect(slice.allSatisfy { $0 >= entry.copyStart && $0 < entry.copyStart + entry.copyCount })
        }
        // The camera sees part of the field, so the test is of a real cull.
        #expect(drawn > 1_000 && drawn < sketch.field.copyCount)
    }

    /// The same field renders the same pixels every time it is exported. The
    /// live cull appends visible copies in whatever order the GPU's threads
    /// reach its counter, and copies meeting at equal depth draw the one that
    /// lands first, so the field example came out three different ways in four
    /// renders before an export compacted in copy order.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportedFieldRepeats() throws {
        let first = try culledFieldFrame()
        for _ in 0 ..< 3 {
            let again = try #require(OllinApp.image(of: FieldABSketch(mode: .field)))
            let diff = try #require(fieldImageDifference(first, again))
            #expect(diff.max == 0, "the field drew differently: max \(diff.max)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func fieldShadowPipelinesBuild() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        // The cube leg is unreachable on a ray-tracing dev machine (the point
        // caster traces instead), so build it here or a shader break hides.
        _ = try renderer.pipeline(.meshFieldShadow)
        _ = try renderer.pipeline(.meshFieldPointShadowMin)
        _ = try renderer.pipeline(.meshFieldPointShadowMax)
        _ = try renderer.pipeline(.meshField(.normal, depth: .depth32Float))
    }
}

/// The cost story, measured (`Scripts/benchmark.sh field`, OLLIN_BENCH=1): the
/// example's 240,000-copy plain under its low flying camera, GPU frame time
/// with culling on vs off, plus the CPU record cost of the one field draw.
@Suite(.serialized)
@MainActor
struct MeshFieldBenchmarkTests {

    @Test(.benchmark)
    func fieldCostCulledVsUnculled() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let res = 1080
        let viewport = SIMD2<Float>(Float(res), Float(res))

        func measure(culling: Bool) -> (gpuMs: Double, cpuMs: Double, copies: Int) {
            let sketch = FieldBenchScene()
            sketch.setCanvasSize(width: Double(res), height: Double(res))
            sketch.setup()
            sketch.fieldCulling = culling
            sketch.advance(time: 1, deltaTime: 1 / 60, frameRate: 60)
            sketch.performDraw()
            let start = ContinuousClock.now
            for _ in 0 ..< 30 { sketch.performDraw() }
            let cpu = Double((ContinuousClock.now - start) / .milliseconds(1)) / 30
            let gpu = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                        width: res, height: res, iterations: 20)
            return (gpu, cpu, sketch.copies)
        }

        let culled = measure(culling: true)
        let unculled = measure(culling: false)
        print("\n=== Ollin mesh-field benchmark (\(culled.copies) copies, \(res)² px, lit + shadows + fog) ===")
        print(String(format: "culling on:  GPU %7.2f ms · CPU record %5.2f ms/frame", culled.gpuMs, culled.cpuMs))
        print(String(format: "culling off: GPU %7.2f ms · CPU record %5.2f ms/frame", unculled.gpuMs, unculled.cpuMs))
        print(String(format: "GPU win from culling: %.1fx", unculled.gpuMs / max(culled.gpuMs, 0.0001)))
        print("=== end ===\n")
    }
}

/// The benchmark's world: the example's five-mesh 240,000-copy plain under its
/// low flying camera, so the numbers measure what the example's parameter toggles.
@MainActor
private final class FieldBenchScene: Sketch {
    var fieldCulling = true
    private(set) var copies = 0
    private let field = MeshField()

    override func setup() {
        seed(4_242)
        let reach = 280.0
        func scatter(_ count: Int, make: (Double, Double) -> MeshInstance) -> [MeshInstance] {
            var list: [MeshInstance] = []
            list.reserveCapacity(count)
            for _ in 0 ..< count { list.append(make(random(-reach, reach), random(-reach, reach))) }
            return list
        }
        field.place(Mesh.box(width: 0.5, height: 0.35, depth: 0.5), at: scatter(90_000) { x, z in
            MeshInstance(position: Vector3(x, 0.17, z), scale: random(0.5, 1.6))
        })
        field.place(Mesh.sphere(radius: 0.3, segments: 10, rings: 6), at: scatter(80_000) { x, z in
            MeshInstance(position: Vector3(x, 0.24, z))
        })
        field.place(Mesh.cone(radius: 0.55, height: 2.2, segments: 10), at: scatter(50_000) { x, z in
            MeshInstance(position: Vector3(x, 1.1, z), scale: Vector3(1, random(0.7, 1.8), 1))
        })
        field.place(Mesh.sphere(radius: 0.7, segments: 12, rings: 8), at: scatter(15_000) { x, z in
            MeshInstance(position: Vector3(x, 0.45, z))
        })
        field.place(Mesh.box(width: 0.45, height: 3.2, depth: 0.3), at: scatter(5_000) { x, z in
            MeshInstance(position: Vector3(x, 1.6, z))
        })
        copies = field.copyCount
    }

    override func draw() {
        background(Color(hex: 0x0D1017))
        field.isCullingEnabled = fieldCulling
        let t = time * 0.05
        camera(Camera3D(eye: Vector3(cos(t * .tau) * 130, 4.2, sin(t * .tau) * 130),
                        target: Vector3(cos(t * .tau + 0.12) * 128, 1.4, sin(t * .tau + 0.12) * 128),
                        far: 110))
        ambientLight(Color(white: 0.16))
        directionalLight(Color(white: 1), direction: Vector3(-0.45, -0.8, -0.4), intensity: 1)
        castShadows()
        fog(Color(hex: 0x0D1017), density: 0.042)
        withState {
            fill(Color(white: 0.32))
            drawPlane(width: 580, depth: 580)
        }
        drawMeshField(field)
    }
}

/// Thousands of small copies in two entries, the camera seeing about half of
/// them: enough copies that the live cull's threads reach its counter out of
/// order.
@MainActor
private final class FieldOrderProbe: Sketch {
    override var canvasSize: CanvasSize { .square(128) }
    let field = MeshField()

    override func setup() {
        var cubes: [MeshInstance] = [], balls: [MeshInstance] = []
        for i in 0 ..< 4_000 {
            let p = Vector3(Double(i % 80) * 0.5 - 20, 0, Double(i / 80) * 0.5 - 12.5)
            if i % 2 == 0 { cubes.append(MeshInstance(position: p, scale: 0.2)) }
            else { balls.append(MeshInstance(position: p, scale: 0.2)) }
        }
        field.place(Mesh.box(width: 1, height: 1, depth: 1), at: cubes)
        field.place(Mesh.sphere(radius: 0.5, segments: 6, rings: 4), at: balls)
    }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 30, 0.01), target: .zero))
        drawMeshField(field)
    }
}

/// One fixture, three paths: the same three-mesh world drawn as a retained
/// culled field, as the same field with culling off, or as per-entry instanced
/// draws. Lit, shadowed, and framed so part of the world sits outside the view.
@MainActor
private final class FieldABSketch: Sketch {
    enum Mode { case field, fieldUnculled, instanced }
    override var canvasSize: CanvasSize { .square(256) }
    private let mode: Mode
    private let field = MeshField()
    private var world: [(mesh: Mesh, copies: [MeshInstance])] = []

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    required init() {
        self.mode = .field
        super.init()
    }

    override func setup() {
        var boxes: [MeshInstance] = [], spheres: [MeshInstance] = [], cones: [MeshInstance] = []
        for i in 0 ..< 60 {
            let a = Double(i) / 60 * .tau
            let r = 2.0 + Double(i % 7) * 1.1
            let p = Vector3(cos(a) * r, 0.4, sin(a) * r)
            let tint = Color(red: 0.5 + 0.5 * cos(a), green: 0.7, blue: 1, alpha: 1)
            switch i % 3 {
            case 0: boxes.append(MeshInstance(position: p, rotation: Vector3(0, a, 0),
                                              scale: Vector3(1, 1 + Double(i % 4) * 0.4, 0.8),
                                              color: tint))
            case 1: spheres.append(MeshInstance(position: p, scale: 0.6, color: tint))
            default: cones.append(MeshInstance(position: p, rotation: Vector3(0, a, 0), color: tint))
            }
        }
        world = [(Mesh.box(width: 0.8, height: 0.8, depth: 0.8), boxes),
                 (Mesh.sphere(radius: 0.6), spheres),
                 (Mesh.cone(radius: 0.5, height: 1.1), cones)]
        for (mesh, copies) in world { field.place(mesh, at: copies) }
        field.isCullingEnabled = (mode != .fieldUnculled)
    }

    override func draw() {
        background(Color(hex: 0x101218))
        // Close in and aimed off-center: a good share of the ring is off-screen.
        camera(Camera3D(eye: Vector3(6, 3, 6), target: Vector3(2, 0.4, 0)))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()
        withState {
            fill(Color(white: 0.8))
            drawPlane(width: 24, depth: 24)
        }
        specular(0.3)
        specularSharpness(32)
        switch mode {
        case .field, .fieldUnculled:
            drawMeshField(field)
        case .instanced:
            fill(.white)   // the field bakes no fill; white keeps the two equal
            for (mesh, copies) in world { drawMesh(mesh, instances: copies) }
        }
    }
}

/// Mean and max per-channel byte difference between two same-size images.
@MainActor
private func fieldImageDifference(_ a: CGImage, _ b: CGImage) -> (mean: Double, max: Int)? {
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
