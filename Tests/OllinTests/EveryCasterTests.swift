@testable import Ollin
import Testing
import CoreGraphics
import simd

/// The systems that read a frame's shadow casters beside the lit mesh itself: the
/// fog march, the contact march, the scattering transmittance, the marched fields
/// casting onto a mesh, and a marched field receiving a mesh's shadow. Each one used
/// to follow the *primary* caster alone, so a second casting light lit the scene and
/// left every one of them untouched. Each probe renders the same scene twice with
/// only the second light's `castingShadow` flipped, so the difference isolates what
/// that caster contributes; with the old rule every one of these reads zero.
@Suite
@MainActor
struct EveryCasterRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> (data: [UInt8], width: Int) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w)
    }

    private func red(_ p: (data: [UInt8], width: Int), _ x: Int, _ y: Int) -> Int {
        Int(p.data[(y * p.width + x) * 4])
    }

    /// Per-pixel red-channel darkening of `b` against `a` (the probe scenes are grayscale).
    private func darkening(_ a: (data: [UInt8], width: Int), _ b: (data: [UInt8], width: Int)) -> [Int] {
        stride(from: 0, to: a.data.count, by: 4).map { Int(a.data[$0]) - Int(b.data[$0]) }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSecondCasterCarvesItsOwnShaft() throws {
        // A spot beam standing beside a directional key, with a panel across the
        // beam. The air below the panel is pure fog, so nothing but the spot's own
        // shadow tap can darken it, and the key's shaft (which both renders share)
        // cannot stand in for it.
        let open = try pixels(SecondCasterBeamProbe.make(secondCasts: false))
        let shafted = try pixels(SecondCasterBeamProbe.make(secondCasts: true))
        let a = red(open, 128, 128), b = red(shafted, 128, 128)
        #expect(a - b > 12, "the second caster should carve its beam (open \(a), cast \(b))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSecondCasterGetsItsOwnContactSeam() throws {
        // The contact march is isolated by flipping only `contactShadows()`, so the
        // map's own shadow is on in both renders. The seam a second caster adds is
        // the region the first caster's march leaves alone.
        let keyOnly = darkening(try pixels(SecondCasterContactProbe.make(secondCasts: false, contact: false)),
                                try pixels(SecondCasterContactProbe.make(secondCasts: false, contact: true)))
        let both = darkening(try pixels(SecondCasterContactProbe.make(secondCasts: true, contact: false)),
                             try pixels(SecondCasterContactProbe.make(secondCasts: true, contact: true)))
        var seam = 0
        for i in both.indices where both[i] > 6 && keyOnly[i] < 3 { seam += 1 }
        #expect(seam > 30, "expected the second caster's own contact seam, got \(seam) pixels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSecondCasterTransmitsThroughABody() throws {
        // A thin slab lit from behind by the second caster, with the key overhead so
        // it never lights the camera-facing side. Only a caster can say how thick the
        // body is, so that face glows only when the light behind it casts.
        let dark = try pixels(SecondCasterTransmitProbe.make(secondCasts: false))
        let glowing = try pixels(SecondCasterTransmitProbe.make(secondCasts: true))
        var lit = 0.0, unlit = 0.0, count = 0.0
        for py in 70..<130 {
            for px in 70..<130 {
                lit += Double(red(glowing, px, py)); unlit += Double(red(dark, px, py)); count += 1
            }
        }
        let a = lit / count, b = unlit / count
        #expect(a - b > 8, "expected a transmitted glow from the second caster (\(a) vs \(b))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMarchedFieldCastsUnderASecondCaster() throws {
        // A marched blob over a mesh floor. The key is a 2D caster, which renders the
        // field into its own map; the second caster is a point light, which has no map
        // a field can render into, so the floor only darkens under it if the mesh
        // fragments march the field toward that caster too.
        let open = try pixels(SecondCasterFieldProbe.make(secondCasts: false))
        let shadowed = try pixels(SecondCasterFieldProbe.make(secondCasts: true))
        let diff = darkening(open, shadowed)
        let darkened = diff.filter { $0 > 20 }.count
        #expect(darkened > 200, "expected the field's cast under the second caster, got \(darkened) pixels")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aSecondCasterCannotLeakBounceThroughAWall() throws {
        // The probe pass shades what its rays hit, so a caster it does not shadow
        // lights surfaces it cannot reach. A sealed room with a bright light outside
        // it: the raster already shadows that light, and the interior must not
        // brighten through the bounce either. Absolute, not a flipped flag, because
        // turning the outside light off changes what the probes gather everywhere.
        let sealedOnly = try pixels(GISecondCasterProbe.make(outside: false))
        let withOutside = try pixels(GISecondCasterProbe.make(outside: true))
        var a = 0.0, b = 0.0, count = 0.0
        for py in 48..<112 {
            for px in 48..<112 {
                a += Double(red(sealedOnly, px, py)); b += Double(red(withOutside, px, py)); count += 1
            }
        }
        let inside = a / count, leaked = b / count
        #expect(inside > 20, "the control interior must be lit from within: \(inside)")
        #expect(leaked - inside < 4, "bounce leaked through the wall: \(leaked) against \(inside)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMarchedFieldReceivesFromASecondCaster() throws {
        // The other direction: a mesh box over a marched slab. A field is in no map,
        // so it reads a factor it marched itself, one per caster; with the old rule
        // it marched toward the primary alone and the second light's shadow of the
        // box simply never landed on it.
        let open = try pixels(SecondCasterCarrierProbe.make(secondCasts: false))
        let shadowed = try pixels(SecondCasterCarrierProbe.make(secondCasts: true))
        let diff = darkening(open, shadowed)
        let darkened = diff.filter { $0 > 20 }.count
        #expect(darkened > 200, "expected the second caster's shadow on the field, got \(darkened) pixels")
    }
}

// MARK: - Probe scenes (fixed cameras, no time, no rng)

/// A spot beam beside a directional key, with a panel across the beam.
private final class SecondCasterBeamProbe: Sketch {
    var secondCasts = true

    static func make(secondCasts: Bool) -> SecondCasterBeamProbe {
        let probe = SecondCasterBeamProbe()
        probe.secondCasts = secondCasts
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1, 9), target: Vector3(0, 1, 0)))
        // Two spots, so the first one is the primary caster and the beam below is the
        // second. A directional key would be the primary instead, but its own air glow
        // washes the empty sky white and buries the shaft this probe reads.
        light(Light.spot(Color(white: 1.0), at: Vector3(-5, 6, 0), direction: Vector3(0.4, -1, 0),
                         angle: .pi / 9, penumbra: 0.2, intensity: 2)
                .castingShadow(true))
        light(Light.spot(Color(white: 1.0), at: Vector3(0, 7, 0), direction: Vector3(0, -1, 0),
                         angle: .pi / 10, penumbra: 0.2, intensity: 3)
                .castingShadow(secondCasts))
        castShadows()
        volumetricLight(1.0, anisotropy: 0.2)
        fill(Color(white: 0.15))
        withState { translate(0, -2.15, 0); drawBox(width: 20, height: 0.3, depth: 20) }
        fill(Color(white: 0.3))
        withState { translate(0, 3.4, 0); drawBox(width: 2.6, height: 0.25, depth: 2.6) }
    }
}

/// A box and a sphere resting on a floor under two casters from opposite sides.
private final class SecondCasterContactProbe: Sketch {
    var secondCasts = true
    var contact = true

    static func make(secondCasts: Bool, contact: Bool) -> SecondCasterContactProbe {
        let probe = SecondCasterContactProbe()
        probe.secondCasts = secondCasts
        probe.contact = contact
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.5, 0), radius: 8, azimuth: 0.4, elevation: 0.3))
        ambientLight(Color(white: 0.2))
        light(Light.directional(.white, direction: Vector3(-0.7, -0.55, -0.3),
                                intensity: 1.0).castingShadow(true))
        light(Light.spot(.white, at: Vector3(-4.5, 1.6, 2.5), direction: Vector3(4.5, -1.4, -2.5).normalized,
                         angle: .pi / 2.5, intensity: 1.2).castingShadow(secondCasts))
        castShadows()
        shadowSoftness(0.8)
        if contact { contactShadows(length: 0.9) }
        fill(Color(white: 0.85))
        drawPlane(width: 20, depth: 20)
        withState {
            fill(Color(white: 0.75))
            translate(-0.8, 0.7, 0)
            drawBox(size: 1.4)
        }
        withState {
            fill(Color(white: 0.75))
            translate(1.2, 0.62, 0.8)
            drawSphere(radius: 0.62)
        }
    }
}

/// A thin slab lit from behind by the second caster, the key overhead.
private final class SecondCasterTransmitProbe: Sketch {
    var secondCasts = true

    static func make(secondCasts: Bool) -> SecondCasterTransmitProbe {
        let probe = SecondCasterTransmitProbe()
        probe.secondCasts = secondCasts
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 6, azimuth: 0,
                         elevation: 0, fieldOfView: .pi / 4, near: 1, far: 30))
        // Straight down, so the key never lights the face the probe reads.
        light(Light.directional(.white, direction: Vector3(0, -1, 0),
                                intensity: 0.6).castingShadow(true))
        light(Light.spot(.white, at: Vector3(0.3, 1.2, -6.5), direction: Vector3(-0.05, -0.05, 1),
                         angle: 0.9, intensity: 1.5).castingShadow(secondCasts))
        castShadows()
        noStroke()
        fill(Color(red: 0.92, green: 0.72, blue: 0.62))
        material(.skin(radius: 0.12))
        withState {
            translate(0, 0.9, 0)
            drawBox(width: 2.2, height: 2.6, depth: 0.18)
        }
    }
}

/// A marched blob over a mesh floor, the second caster a point light.
private final class SecondCasterFieldProbe: Sketch {
    var secondCasts = true

    static func make(secondCasts: Bool) -> SecondCasterFieldProbe {
        let probe = SecondCasterFieldProbe()
        probe.secondCasts = secondCasts
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 9, azimuth: 0.3, elevation: 0.5))
        light(Light.directional(.white, direction: Vector3(-1, -0.9, -0.4),
                                intensity: 0.35).castingShadow(true))
        light(Light.point(.white, at: Vector3(0, 5, 0), intensity: 1.4)
                .castingShadow(secondCasts))
        castShadows()
        fill(Color(white: 0.85))
        drawPlane(width: 20, depth: 20)
        withState {
            fill(Color(white: 0.8))
            drawSDF3D(SDF3D.sphere(radius: 1.1).at(x: 0, y: 1.8, z: 0))
        }
    }
}

/// A mesh box over a marched slab, so the field is the receiver.
private final class SecondCasterCarrierProbe: Sketch {
    var secondCasts = true

    static func make(secondCasts: Bool) -> SecondCasterCarrierProbe {
        let probe = SecondCasterCarrierProbe()
        probe.secondCasts = secondCasts
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 9, azimuth: 0.3, elevation: 0.5))
        light(Light.directional(.white, direction: Vector3(-1, -0.9, -0.4),
                                intensity: 0.35).castingShadow(true))
        light(Light.spot(.white, at: Vector3(0, 6, 0), direction: Vector3(0, -1, 0),
                         angle: 0.9, intensity: 1.6).castingShadow(secondCasts))
        castShadows()
        fill(Color(white: 0.85))
        drawSDF3D(SDF3D.box(width: 14, height: 0.4, depth: 14).at(x: 0, y: 0, z: 0))
        withState {
            fill(Color(white: 0.8))
            translate(0, 2.2, 0)
            drawBox(size: 1.6)
        }
    }
}

/// A sealed room lit from within, with a brighter light outside it as the second caster.
private final class GISecondCasterProbe: Sketch {
    var outside = true

    static func make(outside: Bool) -> GISecondCasterProbe {
        let probe = GISecondCasterProbe()
        probe.outside = outside
        return probe
    }

    override var canvasSize: CanvasSize { .square(160) }

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 1.2, 0), radius: 1.3,
                         azimuth: 0.4, elevation: 0.12, near: 0.05, far: 30))
        pointLight(.white, at: Vector3(0, 2.0, 0), intensity: 0.12)
        if outside { pointLight(.white, at: Vector3(6, 5, 4), intensity: 1.0) }
        castShadows()
        globalIllumination()
        // A sealed room, interior 3.6 x 2.6 x 3.6 around the camera.
        withState { fill(Color(white: 0.9)); translate(0, -0.1, 0); drawBox(width: 4.0, height: 0.2, depth: 4.0) }
        withState { fill(Color(white: 0.9)); translate(0, 2.7, 0); drawBox(width: 4.0, height: 0.2, depth: 4.0) }
        withState { fill(Color(white: 0.9)); translate(0, 1.3, -1.9); drawBox(width: 4.0, height: 2.8, depth: 0.2) }
        withState { fill(Color(white: 0.9)); translate(0, 1.3, 1.9); drawBox(width: 4.0, height: 2.8, depth: 0.2) }
        withState { fill(Color(white: 0.9)); translate(-1.9, 1.3, 0); drawBox(width: 0.2, height: 2.8, depth: 4.0) }
        withState { fill(Color(white: 0.9)); translate(1.9, 1.3, 0); drawBox(width: 0.2, height: 2.8, depth: 4.0) }
    }
}
