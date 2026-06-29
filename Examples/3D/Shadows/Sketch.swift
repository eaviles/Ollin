import Ollin

/// Shadows — solids grounded by cast shadows from a directional key light.
///
/// `castShadows()` turns on shadow mapping for the frame: the renderer renders a
/// depth pass from the scene's primary directional light, then dims that light on
/// every surface it can't reach. It's opt-in and needs a camera plus a directional
/// light — here a warm key from the upper-left that swings a little, so the shadows
/// sweep. The solids drop shadows onto the floor and across one another, and the
/// camera orbits so you see them from every side.
///
/// This scene casts from a directional light (an orthographic shadow map, auto-fit to
/// the scene around the camera target). A spot light can cast too; see the
/// `3D/SpotShadow` example. Point (omnidirectional) casters are a later step.
@main
final class Shadows3D: Sketch {

    override func draw() {
        background(Color(hex: 0x12141A))

        // Orbit the scene. The shadow frustum auto-fits to the eye→target distance,
        // so a radius that frames the scene also sizes the shadow map's coverage.
        cameraShowcase(.turntable(period: .tau / 0.2), target: Vector3(0, 1.2, 0), radius: 13,
                    elevation: 0.5, fieldOfView: .pi / 4.2)

        // A warm key from the upper-left (the caster, since it's the first
        // directional), gently swinging so the shadows move; a soft cool fill and a
        // little ambient keep the shaded sides from going black.
        ambientLight(Color(white: 0.16))
        directionalLight(Color(hue: 0.09, saturation: 0.25, brightness: 1.0),
                         direction: Vector3(-0.55 + sin(time * 0.25) * 0.3, -0.85, -0.4),
                         intensity: 1.0)
        directionalLight(Color(white: 0.5), direction: Vector3(0.5, 0.4, 0.5), intensity: 0.3)
        castShadows()

        // The ground that catches the shadows (nearly matte, so they read clearly).
        withState {
            fill(Color(white: 0.82))
            specular(0.05)
            drawPlane(width: 22, depth: 22)
        }

        // A few solids above the floor — two resting on it, one floating and bobbing
        // — all turning, so the cast shadows shift and overlap.
        specular(0.3)
        shininess(40)

        withState {
            translate(-3.2, 1.4, -1.0)
            rotateY(time * 0.6)
            rotateX(time * 0.3)
            fill(Color(hue: 0.02, saturation: 0.65, brightness: 0.95))
            drawBox(width: 2.4, height: 2.4, depth: 2.4)
        }
        withState {
            translate(2.7, 1.7, 1.2)
            rotateY(-time * 0.5)
            fill(Color(hue: 0.55, saturation: 0.55, brightness: 0.95))
            drawSphere(radius: 1.7)
        }
        withState {
            translate(0.2, 3.4 + sin(time) * 0.6, -2.6)   // floating, bobbing on time
            rotateX(time * 0.7)
            rotateZ(time * 0.4)
            fill(Color(hue: 0.13, saturation: 0.7, brightness: 1.0))
            drawTorus(radius: 1.3, tube: 0.45)
        }
        withState {
            translate(3.1, 1.1, -3.0)
            rotateY(time * 0.9)
            fill(Color(hue: 0.75, saturation: 0.5, brightness: 0.95))
            drawCone(radius: 1.1, height: 2.2)
        }

        drawCaption("Cast shadows — castShadows() from a directional key light")
    }
}
