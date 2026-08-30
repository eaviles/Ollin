import Ollin

/// AreaShadows: a softbox panel casting shadows whose softness is its size.
///
/// `castShadows()` reaches the area lights: with no punctual light present, the
/// first rect or disk panel is the caster, and its penumbra comes from the panel's
/// *real extent* rather than a knob. Here one warm softbox hangs over a small set and
/// slowly breathes between a narrow strip and a wide panel; watch the shadows harden
/// and soften with it, staying crisp where a shape meets the floor and spreading as
/// they fall away (the contact-hardening a real softbox gives). The panel's radiance
/// scales down as it grows, so the pour of light stays steady while only the shadows
/// change. A tube never casts: it glows in every direction, so there is no side to
/// render a shadow from.
///
/// (Under the hood, on a ray-tracing GPU each lit pixel traces visibility rays to
/// points spread over the panel's actual surface, so a wide panel even throws a
/// lopsided penumbra along its long axis; on other GPUs the panel renders a spot-style
/// shadow map from its center whose soft edge is sized from the same extent.)
@main
final class AreaShadows: Sketch {

    override func draw() {
        background(Color(hex: 0x0A0B10))
        ambientLight(Color(white: 0.05))

        cameraShowcase(.sway(amplitude: 0.35, period: 36), target: Vector3(0, 0.4, 0),
                       radius: 12, elevation: 0.42, fieldOfView: .pi / 4.4)

        // The softbox: a warm panel high over the set, aimed down and across. Its
        // width breathes between a strip and a broad square; intensity divides by
        // the area so the light poured on the set holds steady while the shadow
        // edges do all the talking.
        let side = 1.0 + pingPong(over: 12) * 3.0
        rectangleLight(Color(hue: 0.09, saturation: 0.25, brightness: 1.0),
                  at: Vector3(-2.6, 5.4, 2.2), direction: Vector3(0.4, -1, -0.35),
                  width: side, height: side, intensity: 26 / (side * side))
        castShadows()

        // The floor that catches the shadows.
        withState {
            fill(Color(white: 0.8))
            specular(0.05)
            drawPlane(width: 26, depth: 26)
        }

        // A small set: a tall pillar (a long shadow that fans out with distance),
        // a sphere (a soft-edged ellipse), and a leaning box near the camera.
        withState {
            translate(0, 1.25, 0)
            fill(Color(hue: 0.58, saturation: 0.45, brightness: 0.9))
            specular(0.3); shininess(40)
            drawBox(width: 1.0, height: 2.5, depth: 1.0)
        }
        withState {
            translate(2.3, 0.75, -1.1)
            fill(Color(hue: 0.02, saturation: 0.55, brightness: 0.9))
            specular(0.3); shininess(40)
            drawSphere(radius: 0.75)
        }
        withState {
            translate(-1.9, 0.5, 1.7)
            rotateY(0.6)
            fill(Color(hue: 0.32, saturation: 0.4, brightness: 0.85))
            specular(0.3); shininess(40)
            drawBox(width: 1.0, height: 1.0, depth: 1.0)
        }
    }
}
