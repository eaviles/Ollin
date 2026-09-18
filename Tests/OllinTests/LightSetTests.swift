import CoreGraphics
import Foundation
import Metal
import Testing
import simd
import COllinShaders
@testable import Ollin

/// Per-batch lighting: a frame can hold more than one light set, and a mesh shades
/// against the set that was in force when it was drawn.
///
/// Two things have to hold at once, and they pull against each other. A frame that
/// sets its lamps the way every sketch always has must be the picture it always was,
/// which means it records *no* scoped set and every batch reads the frame's own,
/// since that is what the whole committed 3D reference set was recorded against. And
/// a frame that scopes a set must keep the two apart: the interesting law here
/// renders a two-set scene and then each set alone, and demands that the shared
/// frame's pixels match the solo ones, so a lamp leaking from one set into the other
/// could not pass.
@Suite
struct LightSetTests {

    private func freshDrawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        return d
    }

    private let box = Mesh.box(width: 1, height: 1, depth: 1)

    /// A lamp that is easy to tell from another by color alone.
    private func lamp(_ color: Color, at x: Double) -> Light {
        .point(color, at: Vector3(x, 2, 2), intensity: 2)
    }

    private func meshBatches(_ d: Drawer) -> [GeometryBatch] {
        d.batches.filter { $0.kind == .mesh3D }
    }

    // MARK: The frame's own set

    @Test func anOrdinaryLitFrameRecordsNoScopedSet() {
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        d.drawMesh(box)
        d.drawMesh(box)
        #expect(d.lightSets.isEmpty)
        #expect(meshBatches(d).allSatisfy { $0.lightSet == 0 })
    }

    @Test func anUnlitFrameRecordsNoScopedSetEither() {
        let d = freshDrawer()
        d.noLights()
        d.drawMesh(box)
        #expect(d.lightSets.isEmpty)
        #expect(meshBatches(d).allSatisfy { $0.lightSet == 0 })
    }

    @Test func aStateBlockThatTouchesNoLampKeepsTheFramesSet() {
        // withState is used constantly for transforms; a block that says nothing
        // about lamps must not split the batch or make a set.
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        d.pushState()
        d.translate(Vector2(1, 0))
        d.drawMesh(box)
        d.popState()
        #expect(d.lightSets.isEmpty)
        #expect(meshBatches(d).allSatisfy { $0.lightSet == 0 })
    }

    @Test func theFramesRigStillReachesAMeshDrawnBeforeIt() {
        // The frame's own set keeps accumulating over the whole draw, which is the
        // behavior every existing sketch was written against: a lamp added after a
        // mesh still lights it. Only a *scoped* set is a snapshot.
        let d = freshDrawer()
        d.drawMesh(box)
        d.addLight(lamp(.white, at: 0))
        d.addLight(lamp(.red, at: 1))
        #expect(d.makeLighting(set: 0).lightCount == 2)
        #expect(meshBatches(d).allSatisfy { $0.lightSet == 0 })
    }

    // MARK: A scoped set

    @Test func aScopedSetHoldsOnlyItsOwnLamps() {
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        d.pushState()
        d.noLights()
        d.addLight(lamp(.red, at: -2))
        d.drawMesh(box)
        d.popState()
        #expect(d.lightSets.count == 1)
        let scoped = d.makeLighting(set: 1)
        #expect(scoped.lightCount == 1)
        #expect(scoped.lights.0.color.x > scoped.lights.0.color.z)   // the red lamp
        // And the frame's own set never learned about it.
        #expect(d.makeLighting(set: 0).lightCount == 1)
    }

    @Test func aScopedSetBreaksTheBatch() {
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        d.drawMesh(box)                       // the frame's set
        d.pushState()
        d.noLights()
        d.addLight(lamp(.red, at: -2))
        d.drawMesh(box)                       // its own
        d.popState()
        d.drawMesh(box)                       // the frame's again
        let sets = meshBatches(d).map(\.lightSet)
        #expect(sets == [0, 1, 0])
    }

    @Test func twoSetsAreTwoSets() {
        let d = freshDrawer()
        for (color, x) in [(Color.red, -2.0), (Color.blue, 2.0)] {
            d.pushState()
            d.noLights()
            d.addLight(lamp(color, at: x))
            d.drawMesh(box)
            d.popState()
        }
        #expect(d.lightSets.count == 2)
        #expect(meshBatches(d).map(\.lightSet) == [1, 2])
    }

    @Test func twoBlocksUnderTheSameLampsShareOneSet() {
        // A set is a value, so an identical one is found rather than appended, and a
        // loop that scopes the same rig per body costs one uniform, not many.
        let d = freshDrawer()
        for _ in 0..<5 {
            d.pushState()
            d.noLights()
            d.addLight(lamp(.red, at: -2))
            d.drawMesh(box)
            d.popState()
        }
        #expect(d.lightSets.count == 1)
        #expect(meshBatches(d).allSatisfy { $0.lightSet == 1 })
    }

    @Test func anUnlitScopeGoesFlatWhileTheFrameStaysLit() {
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        d.pushState()
        d.noLights()
        d.drawMesh(box)
        d.popState()
        #expect(d.lightSets.count == 1)
        #expect(d.makeLighting(set: 1).enabled == 0)
        #expect(d.makeLighting(set: 0).enabled == 1)
    }

    @Test func aScopedAmbientIsItsOwn() {
        let d = freshDrawer()
        d.ambientLight(Color(white: 0.1))
        d.pushState()
        d.noLights()
        d.ambientLight(Color(white: 0.8))
        d.drawMesh(box)
        d.popState()
        let inner = d.makeLighting(set: 1).ambient.x
        let outer = d.makeLighting(set: 0).ambient.x
        #expect(inner > outer + 0.3, "the scope's ambient read \(inner), the frame's \(outer)")
    }

    @Test func aScopedSetWithNoLampsOfItsOwnPicksUpNoneOfTheFrames() {
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        d.pushState()
        d.noLights()
        d.drawMesh(box)
        d.popState()
        #expect(d.makeLighting(set: 1).lightCount == 0)
    }

    @Test func aCameraRelativeLampResolvesInsideAScope() {
        let d = freshDrawer()
        d.pushState()
        d.noLights()
        d.addLight(.headlight(.white))
        d.drawMesh(box)
        d.popState()
        // A headlight is stored camera-relative and resolved against the camera; the
        // eye is at +z looking at the origin, so the direction *to* the light is +z.
        let l = d.makeLighting(set: 1).lights.0
        #expect(l.direction.z > 0.9, "the headlight resolved to \(l.direction)")
    }

    // MARK: Casting

    @Test func theFramesSetOwnsTheCasters() {
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(-1, -1, -0.5)))
        d.castShadows()
        d.pushState()
        d.noLights()
        d.addLight(lamp(.red, at: -2))
        d.drawMesh(box)
        d.popState()
        d.drawMesh(box)
        #expect(d.makeLighting(set: 0).shadowCasterCount > 0)
        // A scoped set names no caster: the maps were rendered from the frame's own
        // lamps, and a slot pointing into another set's light list would sample a
        // projection that has nothing to do with it.
        #expect(d.makeLighting(set: 1).shadowCasterCount == 0)
        #expect(d.makeLighting(set: 1).shadowLight == -1)
    }

    // MARK: Bookkeeping

    @Test func beginFrameClearsTheSets() {
        let d = freshDrawer()
        d.pushState()
        d.noLights()
        d.addLight(lamp(.red, at: -2))
        d.drawMesh(box)
        d.popState()
        #expect(d.lightSets.count == 1)
        d.beginFrame()
        #expect(d.lightSets.isEmpty)
    }

    @Test func pastTheCapTheExtrasDrawUnderTheFrames() {
        let d = freshDrawer()
        d.addLight(lamp(.white, at: 0))
        // One more distinct set than a frame holds.
        for i in 0 ... Drawer.maxScopedLightSets {
            d.pushState()
            d.noLights()
            d.addLight(lamp(.red, at: Double(i)))
            d.drawMesh(box)
            d.popState()
        }
        #expect(d.lightSets.count == Drawer.maxScopedLightSets)
        let sets = meshBatches(d).map(\.lightSet)
        #expect(sets.count == Drawer.maxScopedLightSets + 1)
        #expect(sets.last == 0, "the set past the cap should fall back to the frame's")
    }

    @Test func aTwoDimensionalFrameBuildsNoSetAtAll() {
        // The lit kinds are the only ones that ask, so a 2D sketch inside a
        // withState block never touches the light-set machinery.
        let d = freshDrawer()
        d.pushState()
        d.noLights()
        d.drawCircle(0, 0, 10)
        d.popState()
        #expect(d.lightSets.isEmpty)
    }

    // MARK: The scope calls on Sketch

    @Test @MainActor func withLightsClearsBeforeItAdds() {
        // The step that is easy to forget by hand: without the clear the lamps would
        // *add* to the frame's rig, which is not what the call says.
        let s = TwoRooms()
        s.drawer.beginFrame()
        s.drawer.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        s.directionalLight(.white, direction: Vector3(0, -1, 0))
        s.withLights([.point(.red, at: Vector3(-2, 2, 2))]) { s.drawMesh(Mesh.box(width: 1, height: 1, depth: 1)) }
        #expect(s.drawer.makeLighting(set: 1).lightCount == 1)
    }

    @Test @MainActor func withoutLightsGoesFlat() {
        let s = TwoRooms()
        s.drawer.beginFrame()
        s.drawer.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        s.directionalLight(.white, direction: Vector3(0, -1, 0))
        s.withoutLights { s.drawMesh(Mesh.box(width: 1, height: 1, depth: 1)) }
        #expect(s.drawer.makeLighting(set: 1).enabled == 0)
        #expect(s.drawer.makeLighting(set: 0).enabled == 1)
    }

    @Test @MainActor func aPresetScopesToo() {
        let s = TwoRooms()
        s.drawer.beginFrame()
        s.drawer.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        s.withLights(.noir) { s.drawMesh(Mesh.box(width: 1, height: 1, depth: 1)) }
        #expect(s.drawer.makeLighting(set: 1).lightCount
                == Int32(LightingPreset.noir.lights.count))
    }
}

/// Two boxes side by side, each under its own lamp. `mode` renders the pair, or one
/// box alone under its own set, which is how the leak law compares them.
final class TwoRooms: Sketch {
    enum Mode { case both, leftAlone, rightAlone, leftOnTheFrame }
    var mode = Mode.both

    static let warm = Color(red: 1, green: 0.55, blue: 0.2)
    static let cool = Color(red: 0.2, green: 0.55, blue: 1)

    static func make(_ mode: Mode) -> TwoRooms {
        let s = TwoRooms()
        s.mode = mode
        return s
    }

    override var canvasSize: CanvasSize { .square(200) }

    /// The pixel each box's face lands on.
    static let leftProbe = (60, 100)
    static let rightProbe = (140, 100)

    private func lamp(_ color: Color, at x: Double) -> Light {
        .point(color, at: Vector3(x, 1, 3), intensity: 3, reach: 6)
    }

    private func drawBoxes(left: Bool, right: Bool) {
        fill(Color(white: 0.85))
        specular(0)
        if left { withState { translate(-1.1, 0, 0); drawBox(width: 1.4, height: 1.4, depth: 1.4) } }
        if right { withState { translate(1.1, 0, 0); drawBox(width: 1.4, height: 1.4, depth: 1.4) } }
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 5), target: .zero, fieldOfView: .pi / 4))
        noLights()
        switch mode {
        case .both:
            withLights([lamp(TwoRooms.warm, at: -1.1)]) { drawBoxes(left: true, right: false) }
            withLights([lamp(TwoRooms.cool, at: 1.1)]) { drawBoxes(left: false, right: true) }
        case .leftAlone:
            withLights([lamp(TwoRooms.warm, at: -1.1)]) { drawBoxes(left: true, right: false) }
        case .rightAlone:
            withLights([lamp(TwoRooms.cool, at: 1.1)]) { drawBoxes(left: false, right: true) }
        case .leftOnTheFrame:
            // The same lamp and the same box, set the old per-frame way: the scoped
            // path and the frame path must resolve to one picture.
            addLight(lamp(TwoRooms.warm, at: -1.1))
            drawBoxes(left: true, right: false)
        }
    }
}

/// Rendered probes for the claim the whole slice rests on: a mesh shades against its
/// own set and nothing else. Pixel comparisons rather than a committed snapshot,
/// because the claim is a *relation* between renders (shared against solo), which no
/// single reference image can state.
@Suite(.serialized)
@MainActor
struct LightSetRenderProbes {

    private func rgba(_ sketch: Sketch) throws -> (data: [UInt8], width: Int) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w)
    }

    private func pixel(_ p: (data: [UInt8], width: Int),
                       _ at: (Int, Int)) -> (r: Int, g: Int, b: Int) {
        let i = (at.1 * p.width + at.0) * 4
        return (Int(p.data[i]), Int(p.data[i + 1]), Int(p.data[i + 2]))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachMeshReadsOnlyItsOwnLamps() throws {
        let both = try rgba(TwoRooms.make(.both))
        let left = try rgba(TwoRooms.make(.leftAlone))
        let right = try rgba(TwoRooms.make(.rightAlone))
        // Each box first has to be *lit*, or the law would pass on two black frames.
        let bl = pixel(both, TwoRooms.leftProbe), br = pixel(both, TwoRooms.rightProbe)
        #expect(bl.r > 40, "the warm box read \(bl)")
        #expect(br.b > 40, "the cool box read \(br)")
        // And each one is warm or cool, not the average of the two.
        #expect(bl.r > bl.b + 20, "the warm box should be warmer than it is cool: \(bl)")
        #expect(br.b > br.r + 20, "the cool box should be cooler than it is warm: \(br)")
        // The law itself: sharing the frame changes neither box by a byte. A lamp
        // leaking across the sets would move one of these.
        #expect(bl == pixel(left, TwoRooms.leftProbe),
                "the warm box moved when the cool one joined: \(bl) against \(pixel(left, TwoRooms.leftProbe))")
        #expect(br == pixel(right, TwoRooms.rightProbe),
                "the cool box moved when the warm one joined: \(br) against \(pixel(right, TwoRooms.rightProbe))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aScopedSetRendersWhatTheFramesSetWould() throws {
        // One lamp over one box, scoped and unscoped: the same picture, pixel for
        // pixel. This is what says the scoped path resolves its uniform the same way
        // the frame's own does rather than by some second recipe.
        let scoped = try rgba(TwoRooms.make(.leftAlone))
        let framed = try rgba(TwoRooms.make(.leftOnTheFrame))
        #expect(scoped.data == framed.data)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anUnlitBodyStandsBesideALitOne() throws {
        let pair = try rgba(LitAndUnlit.make(.pair))
        let litAlone = try rgba(LitAndUnlit.make(.litAlone))
        let flatAlone = try rgba(LitAndUnlit.make(.unlitOnTheFrame))
        let lit = pixel(pair, LitAndUnlit.litProbe)
        let flat = pixel(pair, LitAndUnlit.flatProbe)
        // The unlit box comes out in its own fill color, undimmed by the lamp's
        // grazing angle, so the two boxes look nothing alike.
        #expect(flat.r > 150, "the unlit box should read its bright fill, got \(flat)")
        #expect(flat.r > lit.r + 25, "the two boxes read alike: lit \(lit), flat \(flat)")
        // The laws: the unlit scope left its lit neighbor untouched, and it rendered
        // exactly what a frame-level `noLights()` renders.
        #expect(lit == pixel(litAlone, LitAndUnlit.litProbe),
                "the lit box moved when the flat one joined: \(lit) against \(pixel(litAlone, LitAndUnlit.litProbe))")
        #expect(flat == pixel(flatAlone, LitAndUnlit.flatProbe),
                "the scoped unlit box differs from a frame-level unlit one: \(flat) against \(pixel(flatAlone, LitAndUnlit.flatProbe))")
    }
}

/// A lit box beside an unlit one, in one frame, plus each alone for the comparison.
/// The lamp grazes the front faces (the direction *to* it is mostly +y), so a lit
/// face reads far darker than the flat fill and the two looks cannot be confused.
final class LitAndUnlit: Sketch {
    enum Mode { case pair, litAlone, unlitOnTheFrame }
    var mode = Mode.pair

    static func make(_ mode: Mode) -> LitAndUnlit {
        let s = LitAndUnlit()
        s.mode = mode
        return s
    }

    override var canvasSize: CanvasSize { .square(200) }
    static let litProbe = (60, 100)
    static let flatProbe = (140, 100)

    private func box(at x: Double) {
        withState { translate(x, 0, 0); drawBox(width: 1.4, height: 1.4, depth: 1.4) }
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: Vector3(0, 0, 5), target: .zero, fieldOfView: .pi / 4))
        fill(Color(white: 0.9))
        specular(0)
        switch mode {
        case .pair:
            noLights()
            ambientLight(Color(white: 0.05))
            directionalLight(.white, direction: Vector3(0.2, -1, -0.25))
            box(at: -1.1)
            withoutLights { box(at: 1.1) }
        case .litAlone:
            noLights()
            ambientLight(Color(white: 0.05))
            directionalLight(.white, direction: Vector3(0.2, -1, -0.25))
            box(at: -1.1)
        case .unlitOnTheFrame:
            noLights()
            box(at: 1.1)
        }
    }
}

/// The second question the per-batch note asked: a set with more lamps than the
/// inline array holds is its own light list, so it is its own tile cull. These drive
/// the shipped cull kernel and read back what each set's tiles kept.
@Suite(.serialized)
@MainActor
struct LightSetCullTests {

    /// Cull every set of a drawer and read back one set's tile lists.
    private func tileLists(of drawer: Drawer, set: Int,
                           width: Int = 256, height: Int = 256) throws -> [[Int]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        guard let queue = device.makeCommandQueue(),
              let cb = queue.makeCommandBuffer() else { return [] }
        _ = renderer.encodeLightCull(drawer, into: cb, renderWidth: width, renderHeight: height,
                                     frameIndex: nil)
        cb.commit()
        cb.waitUntilCompleted()
        return renderer.lightTileLists(set: set)
    }

    /// `count` lamps in a row along x, each reaching only a little way, so which
    /// tiles list which lamp is a fact about where the lamp is.
    private func lamps(_ count: Int, color: Color, y: Double) -> [Light] {
        (0..<count).map { i in
            .point(color, at: Vector3(Double(i) - Double(count - 1) / 2, y, 0),
                   intensity: 2, reach: 1.5)
        }
    }

    private func scene(sets: [[Light]]) -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(.perspective(eye: Vector3(0, 0, 14), target: .zero, fieldOfView: .pi / 4))
        for lights in sets {
            d.pushState()
            d.noLights()
            for light in lights { d.addLight(light) }
            d.drawMesh(Mesh.box(width: 1, height: 1, depth: 1))
            d.popState()
        }
        return d
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachSetPastTheInlineCountGetsItsOwnGrid() throws {
        let many = Int(OLLIN_MAX_LIGHTS) + 6
        // Two sets of the same size, one row high and one row low, so their tiles
        // cannot coincide.
        let d = scene(sets: [lamps(many, color: .red, y: 3), lamps(many, color: .blue, y: -3)])
        let a = try tileLists(of: d, set: 1)
        let b = try tileLists(of: d, set: 2)
        #expect(!a.isEmpty)
        #expect(a.count == b.count)
        // Both culled something, and they culled different things: the rows are at
        // different heights, so the tiles that list a lamp differ.
        #expect(a.contains { !$0.isEmpty })
        #expect(b.contains { !$0.isEmpty })
        #expect(a != b, "two sets at different heights produced identical tile lists")
        // Nothing is dropped: every lamp of a set reaches some tile of that set.
        for (name, lists) in [("set 1", a), ("set 2", b)] {
            let reached = Set(lists.flatMap { $0 })
            #expect(reached.count == many, "\(name) listed \(reached.count) of \(many) lamps")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSetOnTheInlinePathCullsNothing() throws {
        // Eight lamps or fewer is the inline path, which is byte-identical to what
        // it always was: no grid at all for that set.
        let d = scene(sets: [lamps(4, color: .red, y: 3)])
        #expect(try tileLists(of: d, set: 1).isEmpty)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFramesOwnSetStillCullsOnItsOwn() throws {
        let many = Int(OLLIN_MAX_LIGHTS) + 6
        let d = Drawer()
        d.beginFrame()
        d.camera(.perspective(eye: Vector3(0, 0, 14), target: .zero, fieldOfView: .pi / 4))
        for light in lamps(many, color: .red, y: 0) { d.addLight(light) }
        d.drawMesh(Mesh.box(width: 1, height: 1, depth: 1))
        let lists = try tileLists(of: d, set: 0)
        #expect(lists.contains { !$0.isEmpty })
    }
}
