@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// CPU checks on the atmosphere state (`fog` / `volumetricLight`) and how it packs
/// into the GPU `OllinLighting` uniform, plus Metal-gated render probes for the
/// behaviors a whole-frame snapshot's mean-diff tolerance would average away:
/// distance and height falloff ordering, the air backdrop, a beam confined to its
/// cone, and the shadow shaft an occluder carves out of it.
@Suite
struct VolumetricStateTests {

    private func freshDrawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        return d
    }

    @Test func atmosphereIsOffByDefault() {
        let u = freshDrawer().makeLighting()
        #expect(u.fogColor.w == 0)
        #expect(u.fogParams.z == 0)
    }

    @Test func fogPacksColorAndShape() {
        let d = freshDrawer()
        d.fog(Color(red: 1, green: 0.5, blue: 0), density: 0.2, heightFalloff: 0.7)
        let u = d.makeLighting()
        #expect(u.fogColor.w == 1)
        #expect(abs(u.fogColor.x - Float(Color.srgbToLinear(1))) < 1e-5)
        #expect(abs(u.fogParams.x - 0.2) < 1e-6)
        #expect(abs(u.fogParams.y - 0.7) < 1e-6)
        #expect(u.fogParams.z == 0)   // no volumetric march without volumetricLight
    }

    @Test func beamsOnlyKeepsExtinctionAtZero() {
        // volumetricLight with no fog: the gate opens, the march gain is set, and
        // the extinction stays zero (beams with no dimming).
        let d = freshDrawer()
        d.volumetricLight(0.8, anisotropy: 0.3)
        let u = d.makeLighting()
        #expect(u.fogColor.w == 1)
        #expect(u.fogColor.x == 0 && u.fogColor.y == 0 && u.fogColor.z == 0)
        #expect(u.fogParams.x == 0)
        #expect(abs(u.fogParams.z - 0.8) < 1e-6)
        #expect(abs(u.fogParams.w - 0.3) < 1e-6)
    }

    @Test func atmospherePacksForUnlitScenes() {
        // Fog is a property of the air: `noLights()` still fogs (packed ahead of
        // the `.off` early return), only the shaft march needs the lights.
        let d = freshDrawer()
        d.noLights()
        d.fog(.gray, density: 0.1, heightFalloff: 0)
        let u = d.makeLighting()
        #expect(u.enabled == 0)
        #expect(u.fogColor.w == 1)
        #expect(abs(u.fogParams.x - 0.1) < 1e-6)
    }

    @Test func atmosphereResetsEachFrame() {
        let d = freshDrawer()
        d.fog(.white, density: 0.3, heightFalloff: 0.2)
        d.volumetricLight(1, anisotropy: 0.5)
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        let u = d.makeLighting()
        #expect(u.fogColor.w == 0)
        #expect(u.fogParams.z == 0)
    }

    @Test func farPlaneRidesTheAirCap() {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero, near: 0.1, far: 42))
        d.fog(.gray, density: 0.1, heightFalloff: 0)
        let u = d.makeLighting()
        #expect(abs(u.fogParams2.y - 42) < 1e-5)
    }

    @Test func negativeInputsClampSane() {
        let d = freshDrawer()
        d.fog(.gray, density: -3, heightFalloff: -1)
        d.volumetricLight(-2, anisotropy: 4)
        let u = d.makeLighting()
        #expect(u.fogParams.x == 0)
        #expect(u.fogParams.y == 0)
        #expect(u.fogParams.z == 0)               // negative gain clamps to off
        #expect(u.fogParams.w <= 0.99)
    }
}

/// Rendered probes for the atmosphere: tiny fixed scenes, sampled pixels, and
/// on/off A-B differencing (the `AreaShadowRenderProbes` idiom), because a
/// snapshot's whole-frame mean can't pin an ordering like "farther is foggier".
@Suite @MainActor
struct FogRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> (data: [UInt8], width: Int, height: Int) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private func red(_ p: (data: [UInt8], width: Int, height: Int), _ x: Int, _ y: Int) -> Int {
        Int(p.data[(y * p.width + x) * 4])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func fartherSurfacesFogMore() throws {
        // Two identical dark spheres, one near, one far, under bright uniform fog:
        // the far one must read closer to the fog color (brighter here).
        let p = try pixels(FogDistanceProbe())
        let near = red(p, 128, 128)          // center: the near sphere
        let far = red(p, 200, 116)           // right: the far sphere
        #expect(far > near + 25, "far sphere should sit deeper in bright fog (near \(near), far \(far))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func heightFalloffThinsWithAltitude() throws {
        // One tall dark wall under height fog: its foot drowns (bright), its top
        // rises clear (dark). Both samples sit on the same wall face.
        let p = try pixels(FogHeightProbe())
        let top = red(p, 128, 60)
        let foot = red(p, 128, 196)
        #expect(foot > top + 25, "the wall's foot should drown in low mist (top \(top), foot \(foot))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func airBackdropWashesEmptySky() throws {
        // No geometry covers the upper half, so only the fullscreen air draw can
        // wash it toward the fog color over the near-black clear.
        let p = try pixels(FogDistanceProbe())
        let sky = red(p, 30, 30)
        #expect(sky > 60, "empty air should wash toward the bright fog color (read \(sky))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func fogAppliesToUnlitScenes() throws {
        // The same colonnade with `noLights()`: fog still washes the flat-color
        // geometry with distance (the air is not a lighting feature).
        let p = try pixels(FogUnlitProbe())
        let nearWall = red(p, 128, 170)
        let farAir = red(p, 128, 40)
        #expect(farAir > nearWall + 20, "unlit scenes still fog (near \(nearWall), air \(farAir))")
    }
}

@Suite @MainActor
struct VolumetricLightRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> (data: [UInt8], width: Int, height: Int) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private func red(_ p: (data: [UInt8], width: Int, height: Int), _ x: Int, _ y: Int) -> Int {
        Int(p.data[(y * p.width + x) * 4])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func beamGlowsInsideItsConeOnly() throws {
        // A spot crossing dark empty air: pixels inside the beam's crossing glow,
        // pixels well outside stay black.
        let p = try pixels(BeamProbe())
        let inBeam = red(p, 128, 128)
        let outside = red(p, 30, 100)
        #expect(inBeam > outside + 30, "the beam should glow only inside the cone (in \(inBeam), out \(outside))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func occluderCarvesAShaftOutOfTheBeam() throws {
        // The same beam with a floating panel in it, shadows on: the beam segment
        // beyond the panel must darken (the crepuscular shaft), pinned by A-B
        // differencing the beam pixel below the panel.
        let blocked = BeamProbe()
        blocked.blocker = true
        let with = try pixels(blocked)
        let without = try pixels(BeamProbe())
        let shadowed = red(with, 128, 128)
        let open = red(without, 128, 128)
        #expect(open > shadowed + 15, "the panel should carve a dark shaft (open \(open), blocked \(shadowed))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func beamsOnlyLeavesOffBeamSurfacesAlone() throws {
        // `volumetricLight` with no `fog`: a lit floor pixel far from any cone
        // must match the plain render (no dimming, no ambient wash), within the
        // march's additive rounding.
        let marched = BeamsOnlyProbe()
        marched.volumetric = true
        let with = try pixels(marched)
        let without = try pixels(BeamsOnlyProbe())
        let a = red(with, 40, 220)
        let b = red(without, 40, 220)
        #expect(abs(a - b) <= 2, "off-beam surfaces must not dim in beams-only mode (\(a) vs \(b))")
    }
}

// MARK: - Probe scenes (fixed cameras, no time, no rng)

private final class FogDistanceProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 0, 8), target: .zero))
        directionalLight(Color(white: 0.4), direction: Vector3(0.3, 0.8, 0.5))
        fog(Color(white: 0.85), density: 0.12, heightFalloff: 0)
        fill(Color(white: 0.05))
        withState { translate(0, 0, 0); drawSphere(radius: 1.4) }
        withState { translate(5.2, 0.8, -9); drawSphere(radius: 2.4) }
    }
}

private final class FogHeightProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 4, 13), target: Vector3(0, 4, 0)))
        directionalLight(Color(white: 0.3), direction: Vector3(0.3, 0.8, 0.5))
        fog(Color(white: 0.85), density: 0.5, heightFalloff: 0.5)
        fill(Color(white: 0.05))
        withState { translate(0, 5, 0); drawBox(width: 10, height: 10, depth: 0.5) }
    }
}

private final class FogUnlitProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 2, 10), target: Vector3(0, 2, 0)))
        noLights()
        fog(Color(white: 0.8), density: 0.1, heightFalloff: 0)
        fill(Color(white: 0.1))
        withState { translate(0, 1, 4); drawBox(width: 8, height: 2, depth: 0.5) }
    }
}

private final class BeamProbe: Sketch {
    var blocker = false
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1, 9), target: Vector3(0, 1, 0)))
        // A steep beam dropping across the view, well inside the frame.
        spotLight(Color(white: 1.0), at: Vector3(0, 7, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 10, penumbra: 0.2, intensity: 3)
        castShadows()
        volumetricLight(1.0, anisotropy: 0.2)
        // A floor in both variants: a frame with no geometry at all encodes no
        // batches, and the whole render (air backdrop included) is skipped.
        fill(Color(white: 0.15))
        withState { translate(0, -2.15, 0); drawBox(width: 20, height: 0.3, depth: 20) }
        if blocker {
            fill(Color(white: 0.3))
            withState { translate(0, 3.4, 0); drawBox(width: 2.6, height: 0.25, depth: 2.6) }
        }
    }
}

private final class BeamsOnlyProbe: Sketch {
    var volumetric = false
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 3, 10), target: Vector3(0, 0.5, 0)))
        // Ambient floor light on purpose: ambient never joins the march, so any
        // off-beam difference the probe reads would be a real leak. (A directional
        // light would legitimately haze the whole frame in beams-only mode.)
        ambientLight(Color(white: 0.45))
        spotLight(Color(white: 1.0), at: Vector3(3, 6, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 12, penumbra: 0.2, intensity: 2)
        if volumetric { volumetricLight(1.0, anisotropy: 0.4) }
        fill(Color(white: 0.5))
        withState { translate(0, -0.25, 0); drawBox(width: 18, height: 0.5, depth: 18) }
    }
}
