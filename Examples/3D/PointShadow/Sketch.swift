import Ollin

/// PointShadow — a point light at the center, casting shadows in every direction.
///
/// `castShadows()` casts from the scene's primary caster. With no directional or spot
/// light present, that's the first point light, and a point caster is omnidirectional:
/// the renderer renders the scene's depth into all six faces of a cube map from the
/// light, so a pillar's shadow falls whichever way it points. Here a bulb hangs at the
/// center of a ring of pillars, so every pillar throws its shadow radially outward,
/// the signature look a single direction can't make. The camera orbits.
///
/// (Under the hood the cube is rendered in one layered pass and sampled by direction
/// with a hardware depth-comparison sampler.)
@main
final class PointShadow3D: Sketch {

    override func draw() {
        background(Color(hex: 0x0A0B10))

        camera(.orbiting(target: Vector3(0, 1.0, 0), radius: 15,
                         azimuth: time * 0.16, elevation: 0.55,
                         fieldOfView: .pi / 4.6))

        // The bulb hangs high above the center (well over the solids), so each one's
        // shadow fans down and outward onto the lit floor near its base rather than
        // grazing off to the dark edges. A touch of ambient keeps the far sides off
        // black. No directional or spot light, so the point light is the caster.
        ambientLight(Color(white: 0.08))
        let bulb = Vector3(0, 6.0, 0)
        pointLight(Color(hue: 0.10, saturation: 0.15, brightness: 1.0),
                   at: bulb, intensity: 1.7, specular: .white)
        castShadows()

        // The floor that catches the radiating shadows.
        withState {
            fill(Color(white: 0.82))
            specular(0.05)
            drawPlane(width: 30, depth: 30)
        }

        // A ring of pillars around the bulb, each turning a little, so their shadows
        // sweep across the floor as the light reaches past them.
        let count = 9
        for i in 0..<count {
            let a = Double(i) / Double(count) * .tau
            let radius = 3.6
            withState {
                translate(cos(a) * radius, 1.1, sin(a) * radius)
                rotateY(a + time * 0.2)
                fill(Color(hue: Double(i) / Double(count), saturation: 0.55, brightness: 0.95))
                specular(0.3); shininess(40)
                drawBox(width: 1.0, height: 2.2, depth: 1.0)
            }
        }

        // A couple of solids closer in, casting their own outward shadows.
        withState {
            translate(1.5, 0.9, 0.4); rotateY(time * 0.5)
            fill(Color(hue: 0.55, saturation: 0.5, brightness: 0.95)); specular(0.3); shininess(40)
            drawSphere(radius: 0.9)
        }
        withState {
            translate(-1.4, 0.7, -1.1); rotateY(-time * 0.4); rotateX(time * 0.2)
            fill(Color(hue: 0.0, saturation: 0.6, brightness: 0.95)); specular(0.3); shininess(40)
            drawBox(size: 1.3)
        }

        drawCaption("Point shadows — castShadows() from an omnidirectional point light")
    }
}
