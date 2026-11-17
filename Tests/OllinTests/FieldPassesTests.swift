@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import Metal
import Testing
import simd

/// A field whose march is too much work for one draw is drawn in several render
/// passes, each shading its share of the pixels (`MetalRenderer.fieldPasses`). The
/// GPU checks its progress through a pass tile by tile, so what has to be bounded is
/// what one pass asks of one tile, and that is the pixels of the tile times the
/// reads each makes times the instructions each read walks, at any resolution.
///
/// Nothing here puts a heavy field on the GPU. The count that picks the passes is
/// arithmetic, the work of the heavy field is counted by the twin of the fragment's
/// march on the CPU, and the pictures compared are of a light field drawn in passes
/// it does not need.
@Suite
@MainActor
struct FieldPassesTests {

    // MARK: The count

    @Test
    func theTileBudgetPicksThePassCount() {
        // A blob of nine instructions at the live budgets: one pass, as it always was.
        #expect(MetalRenderer.fieldPasses(walkWeight: 9, readsPerPixel: 128 + 6) == 1)
        // Sixteen capsules at an export's budgets (31 instructions, 198 reads): 6.3
        // million instructions a tile if every pixel took every step, one pass.
        #expect(MetalRenderer.fieldPasses(walkWeight: 31, readsPerPixel: 198) == 1)
        // Sixty-four capsules there: 127 * 198 * 1024 is 25.7 million, four.
        #expect(MetalRenderer.fieldPasses(walkWeight: 127, readsPerPixel: 198) == 4)
        // The same blob of nine in a frame that traces, on a GPU that traces in
        // software: twenty times the cost a read, so the passes follow.
        #expect(MetalRenderer.fieldPasses(walkWeight: 9, readsPerPixel: 134,
                                          costFactor: MetalRenderer.tracedFieldCost) == 4)
        // Beside a traced shadow alone the fragment carries only the shadow rays,
        // and the same blob is one pass again.
        #expect(MetalRenderer.fieldPasses(walkWeight: 9, readsPerPixel: 134,
                                          costFactor: MetalRenderer.tracedShadowFieldCost) == 1)
        // Never fewer than one, never more than a tile has blocks to share out.
        #expect(MetalRenderer.maxFieldPasses == 16)
        #expect(MetalRenderer.fieldPasses(walkWeight: 0, readsPerPixel: 0) == 1)
        #expect(MetalRenderer.fieldPasses(walkWeight: 100_000, readsPerPixel: 600) == MetalRenderer.maxFieldPasses)
        // More work never takes fewer passes.
        var last = 0
        for weight in stride(from: 1, through: 4_000, by: 37) {
            let passes = MetalRenderer.fieldPasses(walkWeight: weight, readsPerPixel: 270)
            #expect(passes >= last)
            #expect(Double(weight) * 270 * 1024 / Double(passes) <= Double(MetalRenderer.fieldTileBudget)
                    || passes == MetalRenderer.maxFieldPasses)
            last = passes
        }
    }

    @Test
    func aPixelsReadsAreItsMarchItsShadowsAndItsNormal() {
        var lighting = OllinLighting()
        let steps = SIMD2<Float>(192, 72)
        #expect(MetalRenderer.fieldReadsPerPixel(steps: steps, lighting: lighting, traces: false) == 198)
        lighting.enabled = 1
        lighting.shadowCasterCount = 2
        #expect(MetalRenderer.fieldReadsPerPixel(steps: steps, lighting: lighting, traces: false) == 198 + 144)
        #expect(MetalRenderer.fieldReadsPerPixel(steps: steps, lighting: lighting, traces: true) == 198 + 144 + 196)
    }

    /// The build a field marches through decides what each read costs: nothing extra
    /// where nothing traces, a little beside a traced shadow, and twenty times with
    /// the traced reflection paths compiled in, on a GPU that traces in software.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldIsCostedByTheBuildItMarchesThrough() throws {
        final class Empty: Sketch {}
        let renderer = try OllinApp.headlessRenderer(for: Empty())
        guard renderer.rayTracedShadows, !renderer.hasHardwareRayTracing else {
            #expect(renderer.fieldCostFactor(traces: true, reflects: true) == 1)
            return
        }
        #expect(renderer.fieldCostFactor(traces: false, reflects: false) == 1)
        #expect(renderer.fieldCostFactor(traces: true, reflects: false) == MetalRenderer.tracedShadowFieldCost)
        #expect(renderer.fieldCostFactor(traces: true, reflects: true) == MetalRenderer.tracedFieldCost)
        renderer.usesUntracedPipelines = false
        #expect(renderer.fieldCostFactor(traces: false, reflects: false) == MetalRenderer.tracedFieldCost)
    }

    @Test
    func aWalksWeightCountsWhatItCanRead() {
        var plain: [SDFNode3D] = []
        _ = FieldSkipTests.capsules(16, seed: 3).flatten(defaultFill: .white, into: &plain)
        #expect(SDF3D.walkWeight(plain[...]) == 31)
        // A voxelized scope reads its child up to nine times.
        var blocks: [SDFNode3D] = []
        _ = FieldSkipTests.capsules(16, seed: 3).voxelized(size: 0.2).flatten(defaultFill: .white, into: &blocks)
        #expect(SDF3D.walkWeight(blocks[...]) == 31 * 9 + 2)
        // A fractal leaf weighs its iterations.
        var bulb: [SDFNode3D] = []
        _ = SDF3D.mandelbulb(iterations: 8).flatten(defaultFill: .white, into: &bulb)
        #expect(SDF3D.walkWeight(bulb[...]) == 49)
        // The skips are instructions too: the count is of a walk that takes none.
        var skipping: [SDFNode3D] = []
        _ = FieldSkipTests.capsules(64, seed: 11).flatten(defaultFill: .white, skips: true, into: &skipping)
        #expect(SDF3D.walkWeight(skipping[...]) == skipping.count)
    }

    // MARK: The heavy field, counted and never drawn

    /// The picture this slice was planned on: a field of 126 capsules under a
    /// casting light, upright at 1080 by 1920.
    final class Heavy: Sketch {
        static let fieldOfView = Double.pi / 5
        static let light = Vector3(0.4, -0.7, -0.5)
        override var canvasSize: CanvasSize { .size(1080, 1920) }
        override func draw() {
            background(Color(white: 0.06))
            camera(.perspective(eye: Vector3(0, 0, 15), target: .zero, fieldOfView: Self.fieldOfView))
            directionalLight(.white, direction: Self.light, intensity: 1.1)
            ambientLight(Color(white: 0.2))
            castShadows()
            fill(Color(red: 0.9, green: 0.55, blue: 0.25))
            drawSDF3D(Self.field(126))
        }
        static func field(_ count: Int) -> SDF3D {
            var dice = FieldSkipTests.Dice(state: 126)
            func capsule() -> SDF3D {
                let a = Vector3(dice.signed(2.1), dice.signed(3.9), dice.signed(1.6))
                let b = a + dice.point(0.7)
                return SDF3D.line(from: a, to: b, radius: 0.14 + Double(dice.next()) * 0.1)
            }
            var field = capsule()
            for _ in 1 ..< count { field = field.smoothUnion(capsule(), k: 0.15) }
            return field
        }
    }

    /// The instructions each 32-pixel tile of the frame reads, counted by marching
    /// one pixel in every `stride` each way and scaling up.
    private func tileWork(of sketch: Sketch, program: [SDFNode3D], stride step: Int) throws -> [Int] {
        let group = try #require(sketch.drawer.sdf3DGroups.first)
        let width = Int(sketch.width), height = Int(sketch.height)
        let budget = MetalRenderer.raymarchBudget(.tier(.default), automatic: .detail)
        let toLight = (Heavy.light * -1).normalized
        let march = FieldTwin.March(
            group: group, steps: (Int(budget.march), Int(budget.shadow)),
            pixel: Float(tan(Heavy.fieldOfView / 2) / Double(height)),
            casters: [SIMD3(Float(toLight.x), Float(toLight.y), Float(toLight.z))])
        let across = (width + 31) / 32, down = (height + 31) / 32
        var tiles = [Int](repeating: 0, count: across * down)
        var twin = FieldTwin(program)
        for y in Swift.stride(from: step / 2, to: height, by: step) {
            for x in Swift.stride(from: step / 2, to: width, by: step) {
                let ray = try #require(sketch.cameraRay(through: Vector2(Double(x) + 0.5, Double(y) + 0.5)))
                let before = twin.reads
                try twin.marchPixel(origin: SIMD3(Float(ray.origin.x), Float(ray.origin.y), Float(ray.origin.z)),
                                    direction: SIMD3(Float(ray.direction.x), Float(ray.direction.y),
                                                     Float(ray.direction.z)), march)
                tiles[(y / 32) * across + x / 32] += (twin.reads - before) * step * step
            }
        }
        return tiles
    }

    @Test
    func noPassOfTheHeavyFieldAsksATileForMoreThanTheBudget() throws {
        let sketch = Heavy()
        sketch.setCanvasSize(width: 1080, height: 1920)
        try sketch.runSetup()
        sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        let nodes = sketch.drawer.sdf3DNodes
        #expect(nodes.contains { $0.kind == 9 }, "the heavy field was written with no skip")

        var lighting = OllinLighting()
        lighting.enabled = 1
        lighting.shadowCasterCount = 1
        let budget = MetalRenderer.raymarchBudget(.tier(.default), automatic: .detail)
        let reads = MetalRenderer.fieldReadsPerPixel(
            steps: SIMD2(Float(budget.march), Float(budget.shadow)), lighting: lighting, traces: false)
        let passes = MetalRenderer.fieldPasses(
            walkWeight: MetalRenderer.walkWeight(of: sketch.drawer.sdf3DGroups, in: nodes), readsPerPixel: reads)
        #expect(passes > 1, "the heavy field was given one pass")

        let skipped = try tileWork(of: sketch, program: nodes, stride: 24)
        let whole = try tileWork(of: sketch, program: SDF3D.strippingSkips(nodes), stride: 24)
        let busiest = try #require(skipped.max()), busiestWhole = try #require(whole.max())
        let million = { (n: Int) in String(format: "%.1f", Double(n) / 1e6) }
        print("Ollin: the heavy field, \(SDF3D.strippingSkips(nodes).count) instructions and \(nodes.count) with skips, "
              + "\(reads) reads a pixel at the most: its busiest tile reads \(million(busiestWhole)) million "
              + "instructions in one pass without skips and \(million(busiest)) million with them; in "
              + "\(passes) passes, about \(million(Int(Double(busiest) * Double((16 + passes - 1) / passes) / 16 * 1.6))) million a pass, against a budget of "
              + "\(million(MetalRenderer.fieldTileBudget)) million. The whole frame: "
              + "\(million(whole.reduce(0, +))) million without skips, \(million(skipped.reduce(0, +))) million with.")
        // A pass shades its share of a tile's sixteen blocks, and the pixels beside a
        // shaded block are kept busy with it: up to six tenths more, by measurement.
        let blocks = (16 + passes - 1) / passes
        let share = Double(busiest) * Double(blocks) / 16 * 1.6
        #expect(share <= Double(MetalRenderer.fieldTileBudget),
                "a pass asks its busiest tile for \(Int(share)) instructions")
        // The count that picks the passes is a bound: no tile reads more than it allows for.
        #expect(busiestWhole <= reads * (SDF3D.strippingSkips(nodes).count) * MetalRenderer.fieldTilePixels)
        #expect(busiest < busiestWhole, "the skips saved the busiest tile nothing")
    }

    // MARK: The same picture in several passes

    /// A light field and a block on a floor under a casting directional light: the
    /// field marches from the camera and again from the light, into the shadow map.
    final class Light: Sketch {
        var reducedMarch = false
        override var canvasSize: CanvasSize { .size(220, 160) }
        let block = Mesh.box(width: 1.1, height: 1.1, depth: 1.1)
        let floor = Mesh.plane(width: 12, depth: 12)
        override func draw() {
            background(Color(white: 0.1))
            camera(.perspective(eye: Vector3(0, 3.5, 6), target: Vector3(0, 0.4, 0), fieldOfView: .pi / 4))
            directionalLight(.white, direction: Vector3(0.45, -0.7, -0.55), intensity: 1)
            ambientLight(Color(white: 0.2))
            castShadows()
            fill(Color(white: 0.8))
            material(.glossy)
            drawMesh(floor)
            withState { translate(-1.5, 0.55, 0); drawMesh(block) }
            if reducedMarch { raymarchQuality(.performance) }
            withState {
                translate(1.1, 0.8, 0)
                if reducedMarch { scale(2.4) }
                fill(Color(red: 0.9, green: 0.4, blue: 0.2))
                drawSDF3D(SDF3D.sphere(radius: 0.55)
                    .smoothUnion(SDF3D.box(size: 0.7).at(0.5, 0.3, 0).colored(Color(red: 0.2, green: 0.5, blue: 0.9)), k: 0.25)
                    .smoothUnion(SDF3D.torus(radius: 0.5, tube: 0.15).at(-0.3, 0.5, 0.2), k: 0.1))
            }
        }
    }

    private func render(passes: Int?, reducedMarch: Bool = false) throws
        -> (image: CGImage, march: Int, shadow: Int) {
        let sketch = Light()
        sketch.reducedMarch = reducedMarch
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        // An export's quality: the full step budget at full resolution, where a field
        // in one pass is marched inside the canvas's own pass and a field in several
        // goes through a target of its own and is composited.
        renderer.automaticQuality = .detail
        renderer.fieldPassesOverride = passes
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let image = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
        return (image, renderer.lastFieldPasses, renderer.lastFieldShadowPasses)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFieldDrawnInSeveralPassesIsThePictureOfOne() throws {
        let one = try render(passes: 1)
        #expect(one.march == 1 && one.shadow == 1, "asked for one pass, drew \(one.march) and \(one.shadow)")
        for count in [2, 5, 9, 16] {
            let several = try render(passes: count)
            #expect(several.march == count && several.shadow == count,
                    "asked for \(count) passes, marched in \(several.march) and cast in \(several.shadow)")
            let difference = try #require(imageDifference(one.image, several.image))
            #expect(difference.max <= 1,
                    "\(count) passes: the picture is off by up to \(difference.max) levels (mean \(difference.mean))")
        }
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: data, count: w * h * 4))
    }

    /// Each pass shades its own share of the field and nothing else: drawn one at a
    /// time, the passes' pixels do not overlap, each holds about its part of them,
    /// and together they are the pixels of the whole. A pass that shaded everything
    /// would draw the same picture and bound nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func eachPassShadesItsShareOfThePixels() throws {
        let passes = 4
        func inked(_ shown: Int?) throws -> [Bool] {
            let sketch = Light()
            let renderer = try OllinApp.headlessRenderer(for: sketch)
            renderer.automaticQuality = .detail
            renderer.fieldPassesOverride = passes
            renderer.fieldPassShown = shown
            OllinApp.isRenderingHeadless = true
            defer { OllinApp.isRenderingHeadless = false }
            let image = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
            let pixels = try #require(Self.rgba(image))
            // The field is the only orange or blue thing in a gray scene.
            return stride(from: 0, to: pixels.count, by: 4).map {
                abs(Int(pixels[$0]) - Int(pixels[$0 + 2])) > 40
            }
        }
        let whole = try inked(nil)
        let total = whole.filter { $0 }.count
        #expect(total > 600, "the field covers \(total) pixels")
        var seen = [Int](repeating: 0, count: whole.count)
        for shown in 0 ..< passes {
            let share = try inked(shown)
            let count = share.filter { $0 }.count
            // A share is whole 8-pixel blocks, so on a field a few dozen blocks
            // across it is near a quarter and never most of it.
            #expect(count > total / 10 && count < total / 2,
                    "pass \(shown + 1) of \(passes) shaded \(count) of the field's \(total) pixels")
            for i in share.indices where share[i] { seen[i] += 1 }
        }
        #expect(!seen.contains { $0 > 1 }, "two passes shaded the same pixel")
        let missed = whole.indices.filter { whole[$0] && seen[$0] == 0 }.count
        #expect(missed == 0, "\(missed) pixels of the field were in no pass")
    }

    /// At a reduced march the single pass and the several go through the same
    /// target and the same composite, so there the pictures agree to the byte.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theReducedMarchInSeveralPassesIsTheSameToTheByte() throws {
        let one = try render(passes: 1, reducedMarch: true)
        let several = try render(passes: 6, reducedMarch: true)
        #expect(several.march == 6)
        let difference = try #require(imageDifference(one.image, several.image))
        #expect(difference.max == 0, "the passes moved the reduced march (mean \(difference.mean), most \(difference.max))")
    }

    // MARK: The page

    /// A field with skips goes to the page without them: the same field, in the
    /// length the page's block of instructions holds, and with its instructions in
    /// the same places on every frame while the parts move.
    final class Moving: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.black)
            camera(.perspective(eye: Vector3(0, 0, 12), target: .zero, fieldOfView: .pi / 4))
            directionalLight(.white, direction: Vector3(0.4, -0.7, -0.5), intensity: 1)
            var dice = FieldSkipTests.Dice(state: 9)
            var field = SDF3D.sphere(radius: 0.4)
            for i in 1 ..< 40 {
                let home = dice.point(3)
                let drift = Vector3(sin(time * 3 + Double(i)), cos(time * 2 + Double(i)), 0) * 1.5
                field = field.smoothUnion(SDF3D.sphere(radius: 0.3).at(home + drift), k: 0.2)
            }
            drawSDF3D(field)
        }
    }

    @Test
    func thePageCarriesTheProgramWithoutItsSkips() throws {
        let sketch = Moving()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 4, fps: 10)
        #expect(sketch.drawer.sdf3DNodes.contains { $0.kind == 9 }, "the Mac's program carries no skip")
        // Forty spheres, thirty-nine of them moved into place and joined: a move, the
        // sphere, the way back, and the union, four instructions a part.
        let own = 39 * 4 + 1
        #expect(SDF3D.strippingSkips(sketch.drawer.sdf3DNodes).count == own)
        #expect(sketch.drawer.sdf3DNodes.count > own)
        for frame in recording.frames {
            let g = frame.graph
            #expect(g.fieldCount == 1 && g.node3DCount == own)
            for node in 0 ..< g.node3DCount {
                #expect(frame.vector[g.node3DOffset + node * WebNode3D.floats] != 9, "a skip went to the page")
            }
            #expect(frame.vector[g.fieldOffset + 29] == Float(own))
        }
        #expect(WebTrack(recording).stable, "the page's cast changed as the parts moved")
    }
}
