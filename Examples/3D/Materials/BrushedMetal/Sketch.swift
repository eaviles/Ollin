import Ollin

/// Anisotropic specular: the brushed, turned, and satin finishes whose highlight is a
/// streak instead of a dot.
///
/// `Material.anisotropy` (`-1…1`) stretches the physically-based specular lobe along
/// one surface direction, the way the micro-grooves of a brushed or lathed metal do.
/// The **top row** sweeps the strength on the same metal: at `0` the highlight is
/// round, and each step pulls it into a longer streak; a negative value runs the
/// streak the other way. The **bottom row** spins the streak with
/// `anisotropyRotation` (radians), and ends on a cylinder, where the stable world
/// frame the lobe uses on an unmapped mesh reads as a turned, on-the-lathe finish.
///
/// The streak follows the surface's `u` axis on a mesh with a normal or surface map;
/// everywhere else it runs around a stable world frame, so primitives just work. The
/// environment gather follows the stretch too (the reflection smears along the
/// brushing), and `.brushedMetal` carries the finish ready-made.
@main
final class BrushedMetal: Sketch {

    let spacing = 2.4

    override func draw() {
        background(Color(hex: 0x0B0C12))

        cameraShowcase(.sway(amplitude: 0.22, period: .tau / 0.1), target: .zero, radius: 15,
                       elevation: 0.22, fieldOfView: .pi / 4)
        environment(.studio.intensified(to: 1.05).backgroundBlurred(0.55))

        // A warm key sweeping with time so the streaks travel; the environment
        // supplies the smeared reflections and the fill light.
        let lightPos = Vector3(cos(time * 0.5) * 8, 6, sin(time * 0.5) * 8)
        pointLight(Color(kelvin: 5200), at: lightPos, intensity: 1.2)

        let steel = Color(white: 0.78)
        let gold = Color(hue: 0.11, saturation: 0.62, brightness: 0.85)

        // Top row: the strength. The same metal from a round highlight to a long
        // streak, and the sign running it the other way.
        row(y: spacing / 2, labels: ["isotropic", "0.4", "0.8", "-0.8"],
            shape: { _ in drawSphere(radius: 0.92) }) { col in
            fill(steel)
            let strength = [0.0, 0.4, 0.8, -0.8][col]
            material(Material(shading: .physicallyBased, metallic: 1,
                              roughness: 0.4, anisotropy: strength))
        }

        // Bottom row: the rotation spinning the streak, then the turned look on a
        // rotational body (the ready-made preset on a tilted torus, whose surface
        // curves through every frame direction and wears the streak the way a
        // machined ring does; a flat face has one constant frame, so a curved body
        // shows the finish best).
        row(y: -spacing / 2, labels: ["turn 0", "turn 45°", "turn 90°", "turned"],
            shape: { col in
                if col == 3 {
                    rotateX(.pi / 2 - 0.5)
                    drawTorus(radius: 0.68, tube: 0.3)
                } else {
                    drawSphere(radius: 0.92)
                }
            }) { col in
            fill(gold)
            if col == 3 {
                material(.brushedMetal)
            } else {
                material(Material(shading: .physicallyBased, metallic: 1, roughness: 0.4,
                                  anisotropy: 0.8,
                                  anisotropyRotation: Double(col) * .pi / 4))
            }
        }

        drawCaption("anisotropy: the brushed streak on the physically-based material")
    }

    /// One row of four bodies with a projected label under each.
    private func row(y: Double, labels: [String],
                     shape: (Int) -> Void, configure: (Int) -> Void) {
        for col in 0..<4 {
            let x = (Double(col) - 1.5) * spacing
            withState {
                translate(x, y, 0)
                configure(col)
                shape(col)
            }
            withState {
                textFont(OutlineFont.system)
                textSize(24)
                textAlign(.center)
                noStroke()
                fill(Color(white: 0.8))
                if let p = project(Vector3(x, y - 1.35, 0)) {
                    drawText(labels[col], at: p)
                }
            }
        }
    }
}
