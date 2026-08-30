import Ollin

/// Glass: physically-based transmission and refraction.
///
/// `Material.glass()` lets light *through* a physically-based surface instead of
/// bouncing it all back: the diffuse body is replaced by whatever shows through,
/// tinted by the `fill`, bent by `ior`, and frosted by `roughness`. A `thickness`
/// makes the body solid, so a sphere magnifies and flips what's behind it the way a
/// lens does, and an `attenuationColor` deepens the tint the farther light travels
/// inside (thick bottle glass going green at the edges):
///
/// ```swift
/// environment(.studio)                     // something to transmit
/// material(.glass(thickness: 1.8))         // a solid clear body
/// drawSphere(radius: 0.9)
/// ```
///
/// Transmission needs an environment set; on its own it refracts *that*. With
/// `rayTracedReflections()` on a ray-tracing GPU, the view through the glass upgrades
/// to the actual scene: the striped wall behind this row of spheres appears inside
/// them, inverted by the solid ones. **Hold the space bar** to drop the ray-traced
/// upgrade and compare (the glass falls back to refracting the environment alone, and
/// the wall behind vanishes from the glass).
@main
final class Glass: Sketch {

    override func draw() {
        background(Color(hex: 0x14171d))
        cameraShowcase(.sway(amplitude: 0.22, period: .tau / 0.09),
                       target: Vector3(0, 1.35, 0), radius: 11, elevation: 0.18,
                       fieldOfView: .pi / 4, near: 1, far: 40)
        environment(.studio.intensified(to: 1.1).backgroundBlurred(0.5))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.7)

        // Trace the view through the glass against the actual scene (hold space to compare).
        if !isKeyDown(" ") { rayTracedReflections() }

        // A matte floor and a wall of colored stripes behind the row: the content the
        // glass has to transmit, refract, and frost.
        withState {
            material(.dielectric(roughness: 0.8))
            fill(Color(hex: 0x3a3f4c))
            translate(0, -0.55, 0)
            drawBox(width: 30, height: 1.0, depth: 18)
        }
        let stripes = [Color(hex: 0xe6533c), Color(hex: 0xf2b134), Color(hex: 0x4fb477),
                       Color(hex: 0x3f7fd6), Color(hex: 0xb35fd1)]
        for (i, c) in stripes.enumerated() {
            withState {
                material(.dielectric(roughness: 0.6))
                fill(c)
                translate((Double(i) - 2) * 1.5, 1.7, -3.2)
                drawBox(width: 1.1, height: 4.4, depth: 0.5)
            }
        }

        // The glass row, left to right: a solid clear sphere (a lens: the stripes appear
        // inverted inside it), a solid absorbing sphere (bottle green deepening with
        // depth), a frosted solid, and a thin-walled bubble (tints without bending).
        let r = 0.95
        let bodies: [(fill: Color, mat: Material)] = [
            (.white, .glass(thickness: r * 2)),
            (.white, .glass(thickness: r * 2,
                            attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 1.4)),
            (.white, .glass(roughness: 0.45, thickness: r * 2)),
            (Color(hex: 0xcfe4ff), .glass()),
        ]
        for (i, b) in bodies.enumerated() {
            withState {
                material(b.mat)
                fill(b.fill)
                translate((Double(i) - 1.5) * 2.1, 0.95, 0.6)
                drawSphere(radius: r)
            }
        }

        drawCaption(isKeyDown(" ")
            ? "Refracting the environment only (release space for the traced scene)"
            : "Refracting the traced scene (hold space to compare)")
    }
}
