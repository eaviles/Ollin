import Ollin

/// ManyCasters: several lights in the room, each throwing its own shadow.
///
/// `castShadows()` casts from every light in the frame, up to four of them, so a room
/// with several lamps reads like one. A warm key rakes in from the left in both rigs,
/// sweeping slowly so its shadows swing; press any key to cycle what plays beside it.
/// The **spot** rig swings a cool stage light in from the right, and each prop drops a
/// shadow away from each light: two shadows per object, crossing where the lights
/// overlap and coloring the floor with whichever light still reaches it. The **point**
/// rig hangs two lamps circling the props instead. A point light casts every way at
/// once, so it is the expensive kind: it needs a whole cube of depth around it, or a
/// set of rays traced from each lit pixel, and a frame can hold several of them all
/// the same. The renderer picks the cheaper route for the GPU it is on, and nothing
/// here changes with it (on Apple silicon each lamp traces its own rays; elsewhere
/// each renders its own six-face cube of depth).
///
/// The last light is the counter-example. It is a dim overhead fill, and it is told
/// `castsShadow: false`, so it lifts the shaded sides and throws nothing. Take that
/// argument away and it throws another shadow across the same floor. Every caster
/// renders its own pass over the scene from its own point of view, so a light that
/// adds nothing but brightness should stay out of the shadow work.
@main
final class ManyCasters: Sketch {

    /// Press any key to cycle the lamp kind playing beside the key light.
    var usesPointLamps = false

    override func draw() {
        background(Color(hex: 0x090B11))

        cameraShowcase(.turntable(period: .tau / 0.12), target: Vector3(0, 0.9, 0),
                       radius: 16, elevation: 0.78, fieldOfView: .pi / 4.4)

        ambientLight(Color(white: 0.05))

        // The key: warm, high on the left, sweeping slowly so its shadows swing.
        directionalLight(Color(hue: 0.08, saturation: 0.30, brightness: 1.0),
                         direction: Vector3(0.95, -0.95, -0.2 + sin(time * 0.22) * 0.25),
                         intensity: 0.85)

        if usesPointLamps {
            // The warm lamp, circling the props at head height.
            let warmAngle = time * 0.35
            pointLight(Color(hue: 0.07, saturation: 0.45, brightness: 1.0),
                       at: Vector3(cos(warmAngle) * 6.0, 3.4, sin(warmAngle) * 6.0),
                       intensity: 1.5, specular: .white)

            // The cool lamp, crossing it the other way and a little lower.
            let coolAngle = -time * 0.27 + .pi
            pointLight(Color(hue: 0.55, saturation: 0.5, brightness: 1.0),
                       at: Vector3(cos(coolAngle) * 5.2, 2.6, sin(coolAngle) * 5.2),
                       intensity: 1.3, specular: .white)
        } else {
            // The stage light: cool, from the right, circling the props. It casts beside
            // the key rather than waiting its turn.
            let aim = Vector3(cos(time * 0.26) * 1.2, 0.4, sin(time * 0.26) * 1.2)
            let spotPos = Vector3(-7.0, 7.0, 2.0)
            spotLight(Color(hue: 0.56, saturation: 0.42, brightness: 1.0),
                      at: spotPos, direction: (aim - spotPos).normalized,
                      coneAngle: .pi / 4.2, penumbra: 0.35, intensity: 1.7, specular: .white)
        }

        // The fill, kept out of the shadow work.
        directionalLight(Color(hex: 0xBFD2FF), direction: Vector3(0, -1, 0.55),
                         intensity: 0.3, castsShadow: false)

        castShadows()
        shadowSoftness(0.45)

        // The floor that catches every set of shadows.
        withState {
            fill(Color(white: 0.72))
            specular(0.06)
            drawPlane(width: 26, depth: 26)
        }

        specular(0.28)
        specularSharpness(42)

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

        drawCaption(usesPointLamps
            ? "Three casters: a key and two circling lamps (any key: spot)"
            : "Two casters: a key and a spot (any key: point lamps)")
    }

    override func keyPressed() { usesPointLamps.toggle() }
}
