import CoreGraphics
import Foundation
import Metal
import Testing
import simd
import COllinShaders
@testable import Ollin

/// Many lights: `Light.reach` and the per-tile light grid that lets a frame carry
/// more than `OLLIN_MAX_LIGHTS`.
///
/// Two things have to hold at once. A frame of eight lights or fewer must be the
/// picture it always was, down to the byte, because the inline path is what every
/// committed 3D reference was recorded against. And a frame past that must be the
/// picture brute-force forward lighting would draw, because the grid is only allowed
/// to decide *which* lights a tile lists, never how one of them shades. The second
/// is the test worth most here: it renders the same scene culled and unculled and
/// compares the two, so a cull that wrongly dropped a light could not pass.
@Suite(.serialized)
@MainActor
struct ManyLightsTests {

    // MARK: - Scenes

    /// A courtyard of lamps: a floor, a few blocks, and `count` point lights on a
    /// grid, each reaching only as far as `reach`. `culls` is the internal switch the
    /// correctness test flips; with it off every tile lists every light, which is
    /// brute-force forward lighting through the same shading code.
    final class LampScene: Sketch {
        var count = 24
        var reach: Double? = 7
        var culls = true

        override var canvasSize: CanvasSize { .square(200) }

        override func setup() { drawer.cullsLightTiles = culls }

        override func draw() {
            background(.black)
            ambientLight(Color(white: 0.02))
            camera(.perspective(eye: Vector3(0, 26, 26), target: .zero, fieldOfView: .pi / 4))
            let side = Int(Double(count).squareRoot().rounded(.up))
            for i in 0..<count {
                let x = Double(i % side) - Double(side - 1) / 2
                let z = Double(i / side) - Double(side - 1) / 2
                pointLight(Color(hue: Double(i) / Double(count), saturation: 0.8, brightness: 1),
                           at: Vector3(x * 6, 2.5, z * 6), intensity: 1.6, reach: reach)
            }
            fill(Color(white: 0.7))
            withState {
                translate(0, -0.1, 0)
                drawBox(width: 80, height: 0.2, depth: 80)
            }
        }
    }

    /// One red lamp over a wide floor, seen from straight above so a pixel's distance
    /// from the lamp is its distance on the floor. What the reach window is measured
    /// against.
    final class OneLampScene: Sketch {
        var reach: Double? = 8

        override var canvasSize: CanvasSize { .square(200) }

        override func draw() {
            background(.black)
            camera(.perspective(eye: Vector3(0, 40, 0.001), target: .zero, fieldOfView: .pi / 4))
            pointLight(.red, at: Vector3(0, 1.5, 0), intensity: 1, reach: reach)
            fill(.white)
            withState {
                translate(0, -0.1, 0)
                drawBox(width: 120, height: 0.2, depth: 120)
            }
        }
    }

    // MARK: - Helpers

    private func rgba(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    private func pixel(_ data: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// Run the shipped cull kernel over a drawer's lights and read back what each
    /// tile kept. The real kernel, driven exactly as a frame drives it.
    private func tileLists(of drawer: Drawer, width: Int = 256, height: Int = 256,
                           culls: Bool = true) throws -> [[Int]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        drawer.cullsLightTiles = culls
        guard let queue = device.makeCommandQueue(),
              let cb = queue.makeCommandBuffer() else { return [] }
        _ = renderer.encodeLightCull(drawer, into: cb, renderWidth: width, renderHeight: height,
                                     frameIndex: nil)
        cb.commit()
        cb.waitUntilCompleted()
        return renderer.lightTileLists()
    }

    /// A drawer holding a camera and a light set, for the cull to chew on.
    private func drawer(camera: Camera3D, lights: [Light]) -> Drawer {
        let d = Drawer()
        d.camera(camera)
        for light in lights { d.addLight(light) }
        return d
    }

    // MARK: - The inline path is untouched

    /// The committed `mesh-lighting` reference was recorded before any of this
    /// existed, so an exact match is the proof that a frame of eight lights or fewer
    /// renders the same bytes it always did. A mean of zero is every byte equal.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anEightLightSceneIsByteForByteWhatItWas() throws {
        let diff = try Snapshot.meanDifference(of: MeshLightingScene(), against: "mesh-lighting")
        #expect(diff == 0, "the inline lighting path moved by \(diff)")
    }

    /// A light with no reach packs a zero, and zero is the unbounded model: the
    /// window is exactly 1 everywhere, so nothing about the old shading changes.
    @Test func aLightWithNoReachPacksZero() {
        let d = Drawer()
        d.addLight(.point(.white, at: Vector3(1, 2, 3)))
        d.addLight(.point(.white, at: Vector3(1, 2, 3), reach: 12))
        d.addLight(.spot(.white, at: .zero, direction: .unitY, reach: 5))
        d.addLight(.directional(.white, direction: Vector3(0, -1, 0)))
        let packed = d.packedLights()
        #expect(packed[0].position.w == 0)
        #expect(packed[1].position.w == 12)
        #expect(packed[2].position.w == 5)
        #expect(packed[3].position.w == 0)   // a directional has no position to measure from
    }

    /// A reach is clamped at zero rather than going negative, and `reaching(nil)`
    /// puts a light back to unbounded.
    @Test func reachIsNeverNegativeAndCanBeTakenBack() {
        #expect(Light.point(.white, at: .zero, reach: -4).reach == 0)
        #expect(Light.point(.white, at: .zero, reach: 9).reaching(nil).reach == nil)
        #expect(Light.point(.white, at: .zero).reaching(3).reach == 3)
    }

    /// The frame's light set stops at `OLLIN_MAX_SCENE_LIGHTS`, the way the decal
    /// cap does: the list buffer is tiles times this, so it cannot be unbounded.
    @Test func aFrameStopsAtTheLightCeiling() {
        let d = Drawer()
        for i in 0..<(Int(OLLIN_MAX_SCENE_LIGHTS) + 40) {
            d.addLight(.point(.white, at: Vector3(Double(i), 0, 0), reach: 1))
        }
        #expect(d.packedLights().count == Int(OLLIN_MAX_SCENE_LIGHTS))
    }

    // MARK: - The grid decides only which lights a tile lists

    /// The invariant this whole slice rests on: the same sixty-four-lamp courtyard rendered
    /// with the grid culling and with every tile taking every light must be the same
    /// picture, byte for byte. A cull that dropped a light that reaches a pixel would
    /// show up here and nowhere else.
    @Test(.enabled(if: Snapshot.hasMetal))
    func cullingIsTheSamePictureAsShadingEveryLamp() throws {
        let culled = LampScene(); culled.count = 64; culled.culls = true
        let plain = LampScene(); plain.count = 64; plain.culls = false
        guard let a = OllinApp.image(of: culled), let b = OllinApp.image(of: plain) else {
            Issue.record("headless render failed"); return
        }
        let x = rgba(of: a), y = rgba(of: b)
        #expect(x.count == y.count)
        var worst = 0
        for i in x.indices { worst = max(worst, abs(Int(x[i]) - Int(y[i]))) }
        #expect(worst == 0, "the culled frame differs from the brute-force one by \(worst)")
    }

    /// And it is a picture: sixty-four lamps really are all shading, so the courtyard
    /// under them is not the black an eight-light frame would leave past the first
    /// eight lamps' pools.
    @Test(.enabled(if: Snapshot.hasMetal))
    func everyLampInTheFrameShades() throws {
        let many = LampScene(); many.count = 64
        let few = LampScene(); few.count = 8
        guard let a = OllinApp.image(of: many), let b = OllinApp.image(of: few) else {
            Issue.record("headless render failed"); return
        }
        func litChannels(_ bytes: [UInt8]) -> Int {
            var n = 0
            for i in bytes.indices where i % 4 != 3 && bytes[i] > 24 { n += 1 }
            return n
        }
        let litMany = litChannels(rgba(of: a)), litFew = litChannels(rgba(of: b))
        #expect(litMany > litFew * 2, "sixty-four lamps lit \(litMany) channels, eight lit \(litFew)")
    }

    /// A full-canvas render target draws the canvas's own camera view at the canvas's
    /// own pixel size, so the frame's grid is the right grid for it and a scene drawn
    /// there carries all its lamps. Which matters, because drawing 3D into a target
    /// and then filtering it is the ordinary way to put an effect over a scene.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFullCanvasRenderTargetCarriesEveryLamp() throws {
        final class LayeredScene: Sketch {
            var lamps = 64
            override var canvasSize: CanvasSize { .square(200) }
            override func draw() {
                let scene = makeRenderTarget()
                withTarget(scene) {
                    background(.black)
                    ambientLight(Color(white: 0.02))
                    camera(.perspective(eye: Vector3(0, 26, 26), target: .zero,
                                        fieldOfView: .pi / 4))
                    let side = Int(Double(lamps).squareRoot().rounded(.up))
                    for i in 0..<lamps {
                        let x = Double(i % side) - Double(side - 1) / 2
                        let z = Double(i / side) - Double(side - 1) / 2
                        pointLight(Color(hue: Double(i) / Double(lamps), saturation: 0.8, brightness: 1),
                                   at: Vector3(x * 6, 2.5, z * 6), intensity: 1.6, reach: 7)
                    }
                    fill(Color(white: 0.7))
                    withState {
                        translate(0, -0.1, 0)
                        drawBox(width: 80, height: 0.2, depth: 80)
                    }
                }
                drawImage(scene.image, 0, 0)
            }
        }
        func litChannels(_ sketch: Sketch) -> Int {
            guard let image = OllinApp.image(of: sketch) else { return 0 }
            let bytes = rgba(of: image)
            var n = 0
            for i in bytes.indices where i % 4 != 3 && bytes[i] > 24 { n += 1 }
            return n
        }
        let many = LayeredScene(); many.lamps = 64
        let few = LayeredScene(); few.lamps = 8
        let litMany = litChannels(many), litFew = litChannels(few)
        #expect(litMany > litFew * 2,
                "through a render target, 64 lamps lit \(litMany) channels and 8 lit \(litFew)")
    }

    /// A raymarched field shades through the same lit tail a mesh does, so it takes
    /// the grid too, at full resolution and at the reduced tier, which marches at its
    /// own size and divides its position back down to find the tile. Both tiers are
    /// checked because they are two separate passes with two separate bindings.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [RenderQuality.default, .performance])
    func aMarchedFieldTakesTheGridToo(_ quality: RenderQuality) throws {
        final class FieldScene: Sketch {
            var lamps = 40
            var quality = RenderQuality.default
            override var canvasSize: CanvasSize { .square(200) }
            override func draw() {
                background(.black)
                ambientLight(Color(white: 0.02))
                raymarchQuality(quality)
                camera(.orbiting(target: .zero, radius: 14, azimuth: 0.4, elevation: 0.35,
                                 fieldOfView: .pi / 4, near: 2, far: 60))
                for i in 0..<lamps {
                    let turn = Double(i) * 2.399963
                    let radius = 2.0 + 5.0 * (Double(i) / Double(max(lamps - 1, 1))).squareRoot()
                    pointLight(Color(hue: Double(i) / Double(lamps), saturation: 0.8, brightness: 1),
                               at: Vector3(cos(turn) * radius, 2.5, sin(turn) * radius),
                               intensity: 1.6, reach: 6)
                }
                drawSDF3D(SDF3D.sphere(radius: 2.4).colored(Color(white: 0.8)))
            }
        }
        func litChannels(_ lamps: Int) -> Int {
            let scene = FieldScene(); scene.lamps = lamps; scene.quality = quality
            guard let image = OllinApp.image(of: scene) else { return 0 }
            let bytes = rgba(of: image)
            var n = 0
            for i in bytes.indices where i % 4 != 3 && bytes[i] > 24 { n += 1 }
            return n
        }
        let many = litChannels(40), few = litChannels(8)
        #expect(many > few, "at \(quality), 40 lamps lit \(many) channels and 8 lit \(few)")
    }

    // MARK: - What the cull kept

    /// A courtyard of bounded lamps leaves most of them out of most tiles: that
    /// shortening is the whole point, and without it the grid would cost a dispatch
    /// and buy nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func mostLampsAreLeftOutOfMostTiles() throws {
        let lamps = (0..<64).map { i in
            Light.point(.white, at: Vector3(Double(i % 8) * 6 - 21, 2, Double(i / 8) * 6 - 21),
                        reach: 6)
        }
        let camera = Camera3D.perspective(eye: Vector3(0, 30, 30), target: .zero,
                                          fieldOfView: .pi / 4)
        let lists = try tileLists(of: drawer(camera: camera, lights: lamps))
        try #require(!lists.isEmpty, "the cull left no tile grid to read")
        let average = Double(lists.reduce(0) { $0 + $1.count }) / Double(lists.count)
        #expect(average < 12, "a tile lists \(average) of 64 lamps on average")
        #expect(lists.contains { !$0.isEmpty }, "no tile kept any lamp at all")
    }

    /// A light with no reach cannot be bounded, so every tile keeps it. Which is why
    /// giving lamps a reach is what makes many of them affordable, not the grid alone.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLightWithNoReachIsInEveryTile() throws {
        var lamps = (0..<16).map { i in
            Light.point(.white, at: Vector3(Double(i) * 4 - 30, 2, 0), reach: 3)
        }
        lamps.append(.point(.white, at: Vector3(0, 2, 0)))   // unbounded
        let camera = Camera3D.perspective(eye: Vector3(0, 30, 30), target: .zero,
                                          fieldOfView: .pi / 4)
        let lists = try tileLists(of: drawer(camera: camera, lights: lamps))
        try #require(!lists.isEmpty, "the cull left no tile grid to read")
        #expect(lists.allSatisfy { $0.contains(16) })
        #expect(lists.contains { $0.count < 17 }, "every bounded lamp reached every tile")
    }

    /// A spot is bounded by the sector it actually throws into, not by a ball around
    /// its position: one aimed down at the floor lands in fewer tiles than a point
    /// light at the same place with the same reach. A spot bounded by the ball would
    /// land in exactly the point's tiles; on the desk the cone reaches 132 of the 256
    /// tiles and the ball 240, so three quarters of the ball's count is the line.
    ///
    /// The cull runs only for more lights than the shader loops over inline, so the
    /// light under test (index 0) is joined by small lamps far out of view that land
    /// in no tile. With the one light alone there is no grid to read, and this test
    /// passed for a long time without reading one, under a bound of half the ball's
    /// count that nobody had measured.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSpotIsBoundedByItsCone() throws {
        let camera = Camera3D.perspective(eye: Vector3(0, 30, 30), target: .zero,
                                          fieldOfView: .pi / 4)
        let position = Vector3(0, 14, 0)
        let faraway = (0 ..< Int(OLLIN_MAX_LIGHTS)).map { i in
            Light.point(.white, at: Vector3(1000 + Double(i) * 10, 0, 1000), reach: 0.1)
        }
        let asPoint = try tileLists(of: drawer(camera: camera,
            lights: [.point(.white, at: position, reach: 20)] + faraway))
        let asSpot = try tileLists(of: drawer(camera: camera,
            lights: [.spot(.white, at: position, direction: Vector3(0, -1, 0),
                           coneAngle: .pi / 8, reach: 20)] + faraway))
        try #require(!asPoint.isEmpty && !asSpot.isEmpty, "the cull left no tile grid to read")
        let pointTiles = asPoint.filter { $0.contains(0) }.count
        let spotTiles = asSpot.filter { $0.contains(0) }.count
        #expect(spotTiles > 0)
        #expect(spotTiles * 4 < pointTiles * 3,
                "the cone reached \(spotTiles) tiles, the ball \(pointTiles)")
    }

    /// Turning the cull off is the brute-force baseline: every tile takes every light.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCullCanBeTurnedOff() throws {
        let lamps = (0..<12).map { i in
            Light.point(.white, at: Vector3(Double(i) * 8 - 44, 2, 0), reach: 2)
        }
        let camera = Camera3D.perspective(eye: Vector3(0, 30, 30), target: .zero,
                                          fieldOfView: .pi / 4)
        let lists = try tileLists(of: drawer(camera: camera, lights: lamps), culls: false)
        try #require(!lists.isEmpty, "the cull left no tile grid to read")
        #expect(lists.allSatisfy { $0.count == 12 })
    }

    // MARK: - The reach window

    /// The bounded lamp's frame, rendered once this run: both reach probes read it.
    private static var boundedLamp: CGImage?

    private func boundedLampFrame() -> CGImage? {
        if let known = Self.boundedLamp { return known }
        let image = OllinApp.image(of: OneLampScene())
        Self.boundedLamp = image
        return image
    }

    /// The window in the picture: full strength under the lamp, a quarter of that
    /// halfway out, and nothing at all past the reach. Read off a floor seen from
    /// straight above, so a pixel's distance from the center is its distance from
    /// the lamp.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLampReachesItsOwnNeighborhoodAndNoFurther() throws {
        guard let image = boundedLampFrame() else {
            Issue.record("headless render failed"); return
        }
        let data = rgba(of: image)
        let w = image.width, mid = w / 2
        // The lamp hangs 1.5 above the floor with a reach of 8, so the floor under it
        // takes the window at a sixth of the way out and the pool's edge is a ring of
        // radius sqrt(8^2 - 1.5^2), about eight units.
        let under = pixel(data, w, mid, mid)
        #expect(under.r > 150, "the floor under the lamp is dark (\(under))")
        // Out past the reach the lamp contributes exactly nothing, and with no other
        // light and no ambient the floor there is black.
        let beyond = pixel(data, w, mid, 8)
        #expect(beyond == (0, 0, 0), "light arrived past the reach (\(beyond))")
        // And it really is the reach doing it: the same scene unbounded lights there.
        let unbounded = OneLampScene(); unbounded.reach = nil
        guard let far = OllinApp.image(of: unbounded) else {
            Issue.record("headless render failed"); return
        }
        let lit = pixel(rgba(of: far), w, mid, 8)
        #expect(lit.r > 0, "the unbounded lamp left the same place black (\(lit))")
    }

    /// The falloff is monotone: a pixel nearer the lamp is never darker than one
    /// further out, all the way to the edge of the pool.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFalloffOnlyEverDims() throws {
        guard let image = boundedLampFrame() else {
            Issue.record("headless render failed"); return
        }
        let data = rgba(of: image)
        let w = image.width, mid = w / 2
        var last = 256
        for step in stride(from: 0, to: mid - 4, by: 4) {
            let here = pixel(data, w, mid + step, mid).r
            // The present pass dithers, so one value straddles two 8-bit levels: a
            // rise of one level is the dither, not the falloff.
            #expect(here <= last + 1, "the pool brightened \(step) out from the lamp")
            last = here
        }
    }
}
