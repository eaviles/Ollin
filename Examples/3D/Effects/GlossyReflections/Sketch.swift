import Ollin

/// Glossy reflections: a *satin* surface shows the room, not the sky.
///
/// A mirror sends every ray one way, so one traced ray describes it exactly. Brushed
/// steel, a waxed table, or a satin floor sends each ray a slightly different way, and
/// what you see in one is the average of all of them. Ray-traced reflections trace the
/// mirror ray, so on their own they answer roughness by fading that one ray into the
/// blurred environment, and a satin floor standing in a red room reflects a gray sky.
/// `glossyReflections()` spreads each ray by the surface's own roughness instead, and
/// every pixel also borrows the rays its neighbors sent, which is what turns a handful of
/// rays into a smooth reflection rather than glitter:
///
/// ```swift
/// rayTracedReflections()
/// glossyReflections()
/// material(.brushedMetal)   // now shows a blurred room instead of a blurred sky
/// ```
///
/// A satin metal floor stands between two colored walls, with a row of balls whose
/// roughness climbs from mirror on the left to nearly matte on the right. The floor and
/// the middle of the row are where the change lives: they take the walls' color and the
/// balls' own images, softened by exactly as much as each surface is rough. **Hold the
/// space bar** to drop back to the mirror ray and watch the room drain out of them, the
/// left-hand mirror ball staying where it is because a mirror was never the problem.
/// Needs an Apple-silicon (ray-tracing) GPU.
@main
final class GlossyReflections: Sketch {

    override func draw() {
        background(Color(hex: 0x0b0d11))
        // A sway, not a full orbit: the arc keeps the room in frame instead of
        // carrying the camera behind the back wall, and the reflections still
        // get judged in motion.
        cameraShowcase(.sway(amplitude: .pi / 5, period: 26),
                       target: Vector3(0, 1.0, 0), radius: 14, elevation: 0.30,
                       fieldOfView: .pi / 4, near: 1, far: 40)
        // The live window renders at two-thirds size and reconstructs the full
        // canvas; exports and snapshots still render every pixel.
        temporalUpscaling()
        environment(.studio.intensity(1.0).backgroundBlur(0.6))
        directionalLight(.white, direction: Vector3(-0.35, -1, -0.3), intensity: 0.8)
        castShadows()

        rayTracedReflections()
        // The whole example (hold the space bar to compare).
        if !isKeyDown(" ") { glossyReflections() }

        // The satin floor: rough enough that a single mirror ray cannot describe it, and
        // the first surface to change when the lobe arrives.
        withState {
            material(.metal(roughness: 0.3))
            fill(Color(hex: 0x9298a2))
            translate(0, -0.4, 0)
            drawBox(width: 30, height: 0.8, depth: 30)
        }

        // Two colored walls, the room the satin has to show. They are matte, so they
        // reflect nothing themselves; they are only there to be seen in everything else.
        for (x, hex) in [(-5.2, 0xd8442a as UInt32), (5.2, 0x2f6fd8 as UInt32)] {
            withState {
                material(.matte)
                fill(Color(hex: hex))
                translate(x, 2.2, -1.0)
                drawBox(width: 0.4, height: 4.4, depth: 11)
            }
        }
        // A warm slab behind the row, so the far half of the floor has something to hold.
        withState {
            material(.matte)
            fill(Color(hex: 0xe8a33c))
            translate(0, 1.6, -5.4)
            drawBox(width: 6.4, height: 3.2, depth: 0.4)
        }

        // The row: one finish per ball, mirror on the left to nearly matte on the right.
        // The ends make the rule visible. The left ball looks the same either way, because
        // its lobe is a single direction already; the right one is so wide that the
        // environment is the honest answer and Ollin hands back to it.
        let roughness = [0.02, 0.14, 0.28, 0.44, 0.62]
        for (i, r) in roughness.enumerated() {
            withState {
                material(.metal(roughness: r))
                fill(Color(hex: 0xcfd4dc))
                translate(-3.6 + Double(i) * 1.8, 0.9, 0)
                drawSphere(radius: 0.85)
            }
        }
    }
}
