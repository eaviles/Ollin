import Ollin

/// TwoCasters: a warm key and a cool spot, each throwing its own shadow.
///
/// `castShadows()` casts from every light in the frame, up to four of them, so a room
/// with two lamps reads like one. The key rakes in from the left and the spot swings
/// from the right, and each prop drops a shadow away from each of them: two shadows per
/// object, crossing where the lights overlap and coloring the floor with whichever
/// light still reaches it.
///
/// The third light is the counter-example. It is a dim overhead fill, and it is told
/// `castsShadow: false`, so it lifts the shaded sides and throws nothing. Take that
/// argument away and it throws a third shadow across the same floor. Every caster
/// renders its own pass over the scene from its own point of view, so a light that adds
/// nothing but brightness should stay out of the shadow work.
@main
final class TwoCasters: Sketch {

    override func draw() {
        background(Color(hex: 0x090B11))

        cameraShowcase(.turntable(period: .tau / 0.12), target: Vector3(0, 0.9, 0),
                       radius: 16, elevation: 0.78, fieldOfView: .pi / 4.4)

        ambientLight(Color(white: 0.05))

        // The key: warm, high on the left, sweeping slowly so its shadows swing.
        directionalLight(Color(hue: 0.08, saturation: 0.30, brightness: 1.0),
                         direction: Vector3(0.95, -0.95, -0.2 + sin(time * 0.22) * 0.25),
                         intensity: 0.85)

        // The stage light: cool, from the right, circling the props. It casts beside
        // the key rather than waiting its turn.
        let aim = Vector3(cos(time * 0.26) * 1.2, 0.4, sin(time * 0.26) * 1.2)
        let spotPos = Vector3(-7.0, 7.0, 2.0)
        spotLight(Color(hue: 0.56, saturation: 0.42, brightness: 1.0),
                  at: spotPos, direction: (aim - spotPos).normalized,
                  angle: .pi / 4.2, penumbra: 0.35, intensity: 1.7, specular: .white)

        // The fill, kept out of the shadow work.
        directionalLight(Color(hex: 0xBFD2FF), direction: Vector3(0, -1, 0.55),
                         intensity: 0.3, castsShadow: false)

        castShadows()
        shadowSoftness(0.45)

        // The floor that catches both shadows.
        withState {
            fill(Color(white: 0.72))
            specular(0.06)
            drawPlane(width: 26, depth: 26)
        }

        specular(0.28)
        shininess(42)

        withState {
            translate(-1.0, 1.1, 2.4)
            rotateY(time * 0.4)
            fill(Color(hue: 0.02, saturation: 0.55, brightness: 0.95))
            drawBox(size: 2.2)
        }
        withState {
            translate(2.8, 1.4, -0.4)
            fill(Color(hue: 0.42, saturation: 0.45, brightness: 0.95))
            drawSphere(radius: 1.4)
        }
        withState {
            translate(0.4, 2.9 + sin(time * 0.9) * 0.35, -3.2)
            rotateX(time * 0.5)
            rotateZ(time * 0.3)
            fill(Color(hue: 0.13, saturation: 0.68, brightness: 1.0))
            drawTorus(radius: 1.1, tube: 0.36)
        }
        withState {
            translate(-3.0, 1.0, -1.0)
            rotateY(-time * 0.6)
            fill(Color(hue: 0.75, saturation: 0.42, brightness: 0.95))
            drawCone(radius: 0.9, height: 2.0)
        }

        drawCaption("Two casters: a key and a spot, each with its own shadow")
    }
}
