import Ollin

/// SpotShadow — a spot light throwing a cone of light, and the shadows inside it.
///
/// `castShadows()` casts from the scene's primary caster: the first directional light
/// or, when there's no directional, the first spot light, as here. A spot caster is a
/// perspective shadow map fit to its cone, so the solids inside the beam drop crisp
/// shadows onto the floor and across one another, and everything outside the cone falls
/// to the dim fill. The spot sweeps, so the lit pool and its shadows slide over the
/// scene; the camera orbits so you see them from every side.
///
/// (A point/omnidirectional caster is a later step.)
@main
final class SpotShadow3D: Sketch {

    override func draw() {
        background(Color(hex: 0x0C0E13))

        camera(.orbiting(target: Vector3(0, 1.0, 0), radius: 14,
                         azimuth: time * 0.18, elevation: 0.5,
                         fieldOfView: .pi / 4.4))

        // No directional light in the scene, so the spot is the caster. A dim point
        // light fills the shaded sides (point lights aren't shadow casters yet, so it
        // doesn't steal the caster role from the spot), and a little ambient lifts the
        // black.
        ambientLight(Color(white: 0.10))
        pointLight(Color(hue: 0.6, saturation: 0.35, brightness: 0.5),
                   at: Vector3(-6, 5, 6), intensity: 0.5)

        // The spot: high and raking in from the left, aimed at a point that circles
        // near the cluster, so the beam (and the long shadows it casts) sweeps across
        // the scene. A soft penumbra gives the pool of light a feathered edge.
        let aim = Vector3(sin(time * 0.3) * 1.6, 0, cos(time * 0.3) * 1.6)
        let spotPos = Vector3(-3, 9, 5)
        spotLight(Color(hue: 0.09, saturation: 0.18, brightness: 1.0),
                  at: spotPos, direction: (aim - spotPos).normalized,
                  angle: .pi / 4.2, penumbra: 0.4, intensity: 1.4,
                  specular: .white)
        castShadows()

        // The ground that catches the shadows (nearly matte, reads the beam clearly).
        withState {
            fill(Color(white: 0.85))
            specular(0.05)
            drawPlane(width: 24, depth: 24)
        }

        // A cluster of turning solids inside the beam, so the cast shadows shift and
        // overlap as the spot sweeps over them.
        specular(0.3)
        shininess(48)

        withState {
            translate(-1.9, 1.0, 0.4)
            rotateY(time * 0.5)
            rotateX(time * 0.25)
            fill(Color(hue: 0.02, saturation: 0.6, brightness: 0.95))
            drawBox(size: 2.0)
        }
        withState {
            translate(1.7, 1.3, 0.7)
            rotateY(-time * 0.4)
            fill(Color(hue: 0.52, saturation: 0.5, brightness: 0.95))
            drawSphere(radius: 1.3)
        }
        withState {
            translate(-0.2, 2.7 + sin(time * 1.1) * 0.4, -1.4)   // floating, bobbing
            rotateX(time * 0.6)
            rotateZ(time * 0.35)
            fill(Color(hue: 0.14, saturation: 0.7, brightness: 1.0))
            drawTorus(radius: 1.1, tube: 0.4)
        }
        withState {
            translate(1.6, 1.0, -1.8)
            rotateY(time * 0.8)
            fill(Color(hue: 0.78, saturation: 0.45, brightness: 0.95))
            drawCone(radius: 0.95, height: 2.0)
        }

        drawCaption("Spot shadows — castShadows() from a sweeping spot light")
    }
}
