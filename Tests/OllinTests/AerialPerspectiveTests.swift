@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// CPU checks on the aerial-perspective state (`aerialPerspective`) and how it packs
/// into the GPU `OllinLighting` uniform (mode 2 on the fog gate, the sun resolution
/// order, the framing-derived density), plus Metal-gated render probes for the
/// behaviors a whole-frame snapshot's mean-diff tolerance would average away: the
/// blue-shifted veil, its distance ordering, the sunward brightening, and the air
/// veil stepping aside behind a skybox.
@Suite
struct AerialStateTests {

    private func freshDrawer(eyeDistance: Double = 5) -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, eyeDistance), target: .zero))
        return d
    }

    @Test func aerialPacksModeTwoWithDerivedDensity() {
        let d = freshDrawer()
        d.aerialPerspective(density: nil, haziness: 0.3, heightFalloff: 0, sun: nil)
        let u = d.makeLighting()
        #expect(u.fogColor.w == 2)
        #expect(abs(u.fogParams.x - Float(0.35 / 5)) < 1e-6)   // derived from the framing
        #expect(abs(u.aerialLight.w - 0.3) < 1e-6)
        #expect(abs(u.aerialSun.w - Float(Drawer.aerialMieAnisotropy)) < 1e-6)
        let len = (u.aerialSun.x * u.aerialSun.x + u.aerialSun.y * u.aerialSun.y
                   + u.aerialSun.z * u.aerialSun.z).squareRoot()
        #expect(abs(len - 1) < 1e-5)
    }

    @Test func explicitParametersPassThroughAndClamp() {
        let d = freshDrawer()
        d.aerialPerspective(density: 0.02, haziness: 3, heightFalloff: 0.4, sun: nil)
        let u = d.makeLighting()
        #expect(abs(u.fogParams.x - 0.02) < 1e-7)
        #expect(u.aerialLight.w == 1)                          // haziness clamps to 0…1
        #expect(abs(u.fogParams.y - 0.4) < 1e-6)
        let e = freshDrawer()
        e.aerialPerspective(density: -1, haziness: -2, heightFalloff: 0, sun: nil)
        let v = e.makeLighting()
        #expect(v.fogParams.x == 0)
        #expect(v.aerialLight.w == 0)
    }

    @Test func derivedDensityScalesWithTheFraming() {
        // The nil-density default is a fraction of the eye-to-target distance (the
        // contact-shadow rule), so a bare call reads alike at any scene scale.
        let near = freshDrawer(eyeDistance: 10)
        near.aerialPerspective(density: nil, haziness: 0.3, heightFalloff: 0, sun: nil)
        let far = freshDrawer(eyeDistance: 100)
        far.aerialPerspective(density: nil, haziness: 0.3, heightFalloff: 0, sun: nil)
        let a = near.makeLighting().fogParams.x
        let b = far.makeLighting().fogParams.x
        #expect(abs(a / b - 10) < 1e-4)
    }

    @Test func sunPrefersTheExplicitOverride() {
        let d = freshDrawer()
        d.environment(.sky(turbidity: 2, sunElevation: 0.5))
        d.aerialPerspective(density: 0.01, haziness: 0.3, heightFalloff: 0,
                            sun: Vector3(1, 0, 0))
        let u = d.makeLighting()
        #expect(abs(u.aerialSun.x - 1) < 1e-6 && abs(u.aerialSun.y) < 1e-6)
    }

    @Test func skySunCarriesElevationAndRotation() {
        // The `.sky` environment's sun, through its rotation: the skybox samples
        // the environment at R_y(rotation) times the view ray, so the content
        // (sun included) sits at R_y(-rotation) in the world.
        let d = freshDrawer()
        let e = 0.6, rot = 1.1
        d.environment(.sky(turbidity: 2, sunElevation: e).rotated(rot))
        d.aerialPerspective(density: 0.01, haziness: 0.3, heightFalloff: 0, sun: nil)
        let u = d.makeLighting()
        #expect(abs(Double(u.aerialSun.x) - (-sin(rot) * cos(e))) < 1e-6)
        #expect(abs(Double(u.aerialSun.y) - sin(e)) < 1e-6)
        #expect(abs(Double(u.aerialSun.z) - cos(rot) * cos(e)) < 1e-6)
    }

    @Test func directionalLightStandsInWithoutASky() {
        // No environment: the first directional light's direction is the light's
        // travel, so the sun is its negation.
        let d = freshDrawer()
        d.addLight(.directional(.white, direction: Vector3(0, -1, -1)))
        d.aerialPerspective(density: 0.01, haziness: 0.3, heightFalloff: 0, sun: nil)
        let u = d.makeLighting()
        let s = 1.0 / 2.0.squareRoot()
        #expect(abs(Double(u.aerialSun.y) - s) < 1e-5)
        #expect(abs(Double(u.aerialSun.z) - s) < 1e-5)
    }

    @Test func theLastAtmosphereCallWins() {
        let d = freshDrawer()
        d.fog(.gray, density: 0.1, heightFalloff: 0)
        d.aerialPerspective(density: 0.01, haziness: 0.3, heightFalloff: 0, sun: nil)
        #expect(d.makeLighting().fogColor.w == 2)
        let e = freshDrawer()
        e.aerialPerspective(density: 0.01, haziness: 0.3, heightFalloff: 0, sun: nil)
        e.fog(.gray, density: 0.1, heightFalloff: 0)
        #expect(e.makeLighting().fogColor.w == 1)
    }

    @Test func aerialResetsEachFrame() {
        let d = freshDrawer()
        d.aerialPerspective(density: 0.01, haziness: 0.3, heightFalloff: 0, sun: nil)
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        #expect(d.makeLighting().fogColor.w == 0)
    }

    @Test func lowSunFeedsWarmLight() {
        // The slant-path reddening: at any elevation red survives best, and a low
        // sun is far redder relative to blue than a high one.
        let high = Drawer.aerialSunRadiance(elevationSine: 0.9)
        let low = Drawer.aerialSunRadiance(elevationSine: 0.05)
        #expect(high.x > high.y && high.y > high.z)
        #expect(low.x / low.z > 4 * (high.x / high.z))
    }

    @Test func theWavelengthSplitFollowsTheMeasuredRatios() {
        // One place pins the numbers the shader mirrors by hand
        // (`OLLIN_AERIAL_RAYLEIGH`): blue extincts ~2.4x green, red ~0.43x.
        let r = Drawer.aerialRayleighRatios
        #expect(r.y == 1.0)
        #expect(abs(r.x - 0.428) < 1e-9 && abs(r.z - 2.442) < 1e-9)
    }
}

/// Rendered probes: tiny fixed scenes, sampled pixels, on/off A-B differencing
/// (the `FogRenderProbes` idiom). Most run `noLights()` on purpose: aerial
/// perspective is a property of the air (packed ahead of the `.off` return), and
/// flat-unlit geometry isolates the veil from any shading change.
@Suite @MainActor
struct AerialRenderProbes {

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

    private func channel(_ p: (data: [UInt8], width: Int, height: Int),
                         _ x: Int, _ y: Int, _ c: Int) -> Int {
        Int(p.data[(y * p.width + x) * 4 + c])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func turningItOffRestoresTheFrame() throws {
        // `noAerialPerspective()` leaves the gate untaken: byte-identical to a
        // frame that never asked.
        let canceled = AerialSlabProbe()
        canceled.mode = .canceled
        let off = try pixels(AerialSlabProbe())
        let with = try pixels(canceled)
        #expect(off.data == with.data)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theVeilLeansBlue() throws {
        // A dark slab across a long air path: the added veil (A-B against the
        // aerial-off render) must gain more blue than red, the molecular
        // signature no gray fog has.
        let on = AerialSlabProbe(); on.mode = .far
        let off = AerialSlabProbe(); off.mode = .far; off.aerial = false
        let a = try pixels(on), b = try pixels(off)
        let dRed = channel(a, 128, 128, 0) - channel(b, 128, 128, 0)
        let dBlue = channel(a, 128, 128, 2) - channel(b, 128, 128, 2)
        #expect(dBlue > dRed + 10, "the veil should lean blue (dR \(dRed), dB \(dBlue))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func fartherVeilsMore() throws {
        // The same slab, near then far (each sized to hold the frame center):
        // the far one sits under more air.
        let near = AerialSlabProbe(); near.mode = .near
        let nearOff = AerialSlabProbe(); nearOff.mode = .near; nearOff.aerial = false
        let far = AerialSlabProbe(); far.mode = .far
        let farOff = AerialSlabProbe(); farOff.mode = .far; farOff.aerial = false
        let dNear = channel(try pixels(near), 128, 128, 2) - channel(try pixels(nearOff), 128, 128, 2)
        let dFar = channel(try pixels(far), 128, 128, 2) - channel(try pixels(farOff), 128, 128, 2)
        #expect(dFar > dNear + 15, "farther should veil more (near \(dNear), far \(dFar))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func lookingSunwardBrightensTheAir() throws {
        // One dark wall, the sun explicitly ahead of the camera versus behind it:
        // the forward (aerosol) lobe must brighten the sunward air.
        let toward = AerialSunwardProbe(); toward.sunAhead = true
        let away = AerialSunwardProbe(); away.sunAhead = false
        let a = channel(try pixels(toward), 128, 128, 0)
        let b = channel(try pixels(away), 128, 128, 0)
        #expect(a > b + 15, "sunward air should brighten (toward \(a), away \(b))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func hazinessTradesBlueForGray() throws {
        // Pure molecular air veils blue; a hazy sky veils gray. The veil's
        // blue-over-red ratio must fall as haziness rises.
        func veil(_ haziness: Double) throws -> (r: Int, b: Int) {
            let on = AerialSlabProbe(); on.mode = .far; on.haziness = haziness
            let off = AerialSlabProbe(); off.mode = .far; off.aerial = false
            let a = try pixels(on), b = try pixels(off)
            return (channel(a, 128, 128, 0) - channel(b, 128, 128, 0),
                    channel(a, 128, 128, 2) - channel(b, 128, 128, 2))
        }
        let clear = try veil(0)
        let hazy = try veil(1)
        let clearLean = Double(clear.b) / Double(max(clear.r, 1))
        let hazyLean = Double(hazy.b) / Double(max(hazy.r, 1))
        #expect(clearLean > hazyLean + 0.3,
                "haziness should gray the veil (clear \(clearLean), hazy \(hazyLean))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func heightFalloffClearsTheTops() throws {
        // One tall dark wall under falling-off aerial air: its foot drowns in
        // veil, its top rises clear. Same wall face, same distance.
        let p = try pixels(AerialHeightProbe())
        let top = channel(p, 128, 60, 2)
        let foot = channel(p, 128, 196, 2)
        #expect(foot > top + 15, "the foot should veil more (top \(top), foot \(foot))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSkyBackdropKeepsItsColor() throws {
        // Behind a skybox the air veil steps aside (the sky already is the
        // scattering at infinity): a pure-sky pixel must not change when aerial
        // perspective turns on.
        let on = AerialSkyProbe()
        let off = AerialSkyProbe(); off.aerial = false
        let a = try pixels(on), b = try pixels(off)
        for c in 0 ..< 3 {
            #expect(channel(a, 12, 12, c) == channel(b, 12, 12, c),
                    "sky pixel channel \(c) moved under the aerial veil")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func bareAirGlowsWithoutABackdrop() throws {
        // With no environment the air paints the implied horizon glow over the
        // 2D clear, so empty sky brightens.
        let on = AerialSlabProbe(); on.mode = .near
        let off = AerialSlabProbe(); off.mode = .near; off.aerial = false
        let a = channel(try pixels(on), 128, 30, 2)
        let b = channel(try pixels(off), 128, 30, 2)
        #expect(a > b + 20, "empty air should glow (on \(a), off \(b))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func beamsStillRideTheAerialAir() throws {
        // `volumetricLight` under aerial perspective: the beam march reads the
        // aerial density, so a spot still glows inside its cone.
        let p = try pixels(AerialBeamProbe())
        let inBeam = channel(p, 128, 128, 0)
        let outside = channel(p, 30, 100, 0)
        #expect(inBeam > outside + 20,
                "the beam should glow through aerial air (in \(inBeam), out \(outside))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func twoRendersMatch() throws {
        let a = AerialSlabProbe(); a.mode = .far
        let b = AerialSlabProbe(); b.mode = .far
        #expect(try pixels(a).data == pixels(b).data)
    }
}

// MARK: - Probe scenes (fixed cameras, no time, no rng)

private final class AerialSlabProbe: Sketch {
    enum Mode { case off, near, far, canceled }
    var mode: Mode = .off
    var aerial = true
    var haziness = 0.3
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 0, 0.01), target: Vector3(0, 0, -10)))
        noLights()
        if aerial, mode != .off {
            // The sun sits overhead so left/right framing doesn't bias the phase.
            aerialPerspective(density: 0.03, haziness: haziness, sun: Vector3(0, 1, 0))
        }
        if mode == .canceled {
            aerialPerspective(density: 0.03)
            noAerialPerspective()
        }
        fill(Color(white: 0.05))
        switch mode {
        case .near, .canceled, .off:
            withState { translate(0, 0, -5); drawBox(width: 2, height: 2, depth: 0.2) }
        case .far:
            withState { translate(0, 0, -30); drawBox(width: 12, height: 12, depth: 0.2) }
        }
    }
}

private final class AerialSunwardProbe: Sketch {
    var sunAhead = true
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 0, 0.01), target: Vector3(25, 0, 0)))
        noLights()
        let sun = sunAhead ? Vector3(1, 0.15, 0) : Vector3(-1, 0.15, 0)
        aerialPerspective(density: 0.02, haziness: 0.5, sun: sun)
        fill(Color(white: 0.05))
        withState {
            translate(25, 0, 0)
            drawBox(width: 0.2, height: 60, depth: 60)
        }
    }
}

private final class AerialHeightProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.02))
        camera(Camera3D(eye: Vector3(0, 4, 13), target: Vector3(0, 4, 0)))
        noLights()
        aerialPerspective(density: 0.15, haziness: 0.3, heightFalloff: 0.5,
                          sun: Vector3(0, 1, 0))
        fill(Color(white: 0.05))
        withState { translate(0, 5, 0); drawBox(width: 10, height: 10, depth: 0.5) }
    }
}

private final class AerialSkyProbe: Sketch {
    var aerial = true
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1, 8), target: Vector3(0, 1, 0)))
        environment(.sky(turbidity: 2.4, sunElevation: 0.6))
        if aerial { aerialPerspective(density: 0.05) }
        fill(Color(white: 0.3))
        withState { translate(0, 0, 0); drawBox(width: 2, height: 2, depth: 2) }
    }
}

private final class AerialBeamProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        // A short far plane keeps the empty air's own veil modest (the default
        // 1000-unit path saturates to the sky tone, hiding the beam on top).
        camera(Camera3D(eye: Vector3(0, 1, 9), target: Vector3(0, 1, 0), near: 0.1, far: 40))
        spotLight(Color(white: 1.0), at: Vector3(0, 7, 0), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 10, penumbra: 0.2, intensity: 3)
        // The march's scattering coefficient is the aerial density (thin air), so
        // the gain is turned up to keep the beam readable over the veil.
        volumetricLight(6.0, anisotropy: 0.2)
        aerialPerspective(density: 0.008, sun: Vector3(0, 1, 0))
        fill(Color(white: 0.15))
        withState { translate(0, -2.15, 0); drawBox(width: 20, height: 0.3, depth: 20) }
    }
}
