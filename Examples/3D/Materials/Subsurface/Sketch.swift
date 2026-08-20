import Ollin

/// Real subsurface scattering: light that travels under the surface.
///
/// `Material.scattering` sends part of a surface's light *into* the body, where it
/// spreads and re-emerges nearby. Shadow edges soften, thin lit regions glow into
/// the dark side, and the diffusion picks up the material's own color along the way,
/// which is what separates skin, wax, and marble from painted plastic:
///
/// ```swift
/// material(.skin(radius: 0.5))     // radius: how far light travels, world units
/// drawSphere(radius: 2)
/// ```
///
/// `scatteringRadius` names the one scene-dependent number (a head-sized form wants
/// roughly 1% of its width; too large reads as wax), and `scatteringColor` shapes
/// how far each channel travels: the default lets red run farthest, the warm halo
/// of skin, while near-equal channels read as neutral stone.
///
/// With `castShadows()` on, the same material also *transmits*: the caster's depth
/// says how thick the body is at every point, so when the key light crosses behind
/// the row, light comes through wherever a form is thin; the torus tubes rim-light
/// from inside, the way a hand glows red against the sun. **Hold the space bar**
/// to switch the scattering off and compare against the plain surfaces.
@main
final class Subsurface: Sketch {

    override func draw() {
        background(Color(hex: 0x101014))
        cameraShowcase(.sway(amplitude: 0.2, period: .tau / 0.09),
                       target: Vector3(0, 0.4, 0), radius: 9.5, elevation: 0.14,
                       fieldOfView: .pi / 4, near: 1, far: 40)

        // A key light swinging behind the row: as it crosses to the back, the
        // scattering keeps the shadow sides breathing where plain surfaces go flat.
        let a = time * 0.35
        directionalLight(.white, direction: Vector3(-cos(a), -0.3, -sin(a) * 0.8),
                         intensity: 1.3)
        pointLight(Color(hex: 0xdfe8ff), at: Vector3(-4, 3, 4), intensity: 0.3,
                   castsShadow: false)   // a fill, and the key is what transmits
        // The caster is what lets the scattering transmit: its depth map is the
        // thickness gauge, so thin parts glow through when the key swings behind.
        castShadows()
        noStroke()

        let comparing = isKeyDown(" ")
        func scattered(_ m: Material) -> Material {
            var m = m
            if comparing { m.scattering = 0 }
            return m
        }

        // Left to right: skin (red runs farthest), marble (near-neutral, slightly
        // warm), and a jade built from the bare knobs: a green-dominant
        // scatteringColor makes the diffusion itself green.
        var jade = Material.dielectric(roughness: 0.3)
        jade.scattering = 0.8
        jade.scatteringRadius = 0.25
        jade.scatteringColor = Color(red: 0.35, green: 1.0, blue: 0.5)

        withState {
            translate(-2.6, 0.55, 0)
            fill(Color(red: 0.92, green: 0.72, blue: 0.62))
            material(scattered(.skin(radius: 0.4)))
            drawSphere(radius: 1.2)
        }
        withState {
            translate(0, 0.55, 0)
            fill(Color(white: 0.88))
            material(scattered(.marble(radius: 0.2)))
            rotateX(0.9); rotateZ(time * 0.1)
            drawTorus(radius: 0.9, tube: 0.46)
        }
        withState {
            translate(2.6, 0.55, 0)
            fill(Color(red: 0.45, green: 0.78, blue: 0.55))
            material(scattered(jade))
            rotateY(time * 0.12)
            drawTorusKnot(p: 2, q: 3, radius: 0.85, tube: 0.3)
        }

        withState {
            translate(0, -0.75, 0)
            fill(Color(white: 0.35)); material(.roughPlastic)
            drawBox(width: 26, height: 0.3, depth: 16)
        }

        drawCaption(comparing
            ? "Plain surfaces (release space for the scattering)"
            : "Subsurface scattering (hold space to compare)")
    }
}
