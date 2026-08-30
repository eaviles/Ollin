import Ollin

/// Volumetric light: beams, gobos, and shafts you can see in the air.
///
/// A light normally shows only where it lands; `volumetricLight()` marches the
/// air itself, so a spot's cone becomes a stage beam and everything the light
/// carries shapes that beam too. Two spots light this set:
///
/// - the **key**, high on the left, projecting a window-frame cookie through
///   thin haze: the panes read as tilted bars of bright air before they land
///   on the floor, and `castShadows()` lets the standing props carve their own
///   dark shafts out of the beam,
/// - a bare **rim** spot low behind the set, aimed toward the camera: with a
///   forward-leaning `anisotropy` its cone flares as the orbit swings through
///   it, the looking-into-the-light glow.
///
/// A whisper of `fog` gives the beams a medium to live in and settles the room
/// into haze; drop the `fog` call and the air goes clear but the beams stay
/// (the extinction is the fog's, the glow is the march's). The beams are the
/// same lights that shade the surfaces, so cookie, cone, and shadow agree
/// between the air and the floor.
@main
final class VolumetricLight: Sketch {

    // The window gobo, drawn in code: 2×2 panes behind mullions (the cookie
    // resamples the image once at init, so build it once and keep it).
    private let windowGobo: LightCookie = {
        var frame = Image(width: 128, height: 128, color: .black)
        for y in 0..<128 {
            for x in 0..<128 {
                let inFrame = x > 10 && x < 117 && y > 10 && y < 117
                let onMullion = abs(x - 64) < 6 || abs(y - 64) < 6
                if inFrame && !onMullion { frame[x, y] = .white }
            }
        }
        return LightCookie(frame)!
    }()

    override func draw() {
        background(Color(hex: 0x04050A))
        ambientLight(Color(white: 0.015))   // a whisper so unlit backs aren't dead black

        cameraShowcase(.orbitAndRise(period: 48), target: Vector3(0, 0.9, 0),
                       radius: 10.5, elevation: 0.16, fieldOfView: .pi / 4.2)

        // The key: warm, high on the left, throwing the window across the set.
        spotLight(Color(hue: 0.10, saturation: 0.28, brightness: 1.0),
                  at: Vector3(-4.6, 6.0, 2.6), direction: Vector3(0.62, -0.74, -0.28),
                  coneAngle: .pi / 8, penumbra: 0.22, intensity: 3.2,
                  cookie: windowGobo, roll: 0.18)

        // The rim: cool and faint, crossing the set laterally behind the props (a
        // beam reads best crossing the view; one aimed down the lens floods it).
        spotLight(Color(hue: 0.58, saturation: 0.45, brightness: 1.0),
                  at: Vector3(5.6, 2.6, -4.8), direction: Vector3(-0.92, -0.18, 0.36),
                  coneAngle: .pi / 10, penumbra: 0.5, intensity: 0.7)

        castShadows()            // the props carve shafts out of the key's beam
        volumetricLight(0.9, anisotropy: 0.45)
        fog(Color(hex: 0x0A0E18), density: 0.02)   // thin haze for the beams to live in

        // --- The set: a matte floor and a few standing props ---
        fill(Color(hex: 0x2E3138))
        drawGround(size: 22, thickness: 1.1)

        fill(Color(hex: 0x8A8478))
        withState {
            translate(-0.4, 1.35, -0.3)
            drawCylinder(radius: 0.42, height: 2.7)
        }
        fill(Color(hex: 0x707A86))
        withState {
            translate(1.7, 0.62, 1.3)
            drawSphere(radius: 0.62)
        }
        fill(Color(hex: 0x66605A))
        withState {
            translate(-2.1, 0.85, 1.8)
            rotateY(0.5)
            drawBox(width: 0.75, height: 1.7, depth: 0.75)
        }
        fill(Color(hex: 0x5A6472))
        withState {
            translate(2.6, 1.05, -1.9)
            drawCone(radius: 0.55, height: 2.1)
        }
    }
}
