import Ollin

/// How far a reflection is allowed to travel: `reflectionBounces`.
///
/// A traced reflection walks two surfaces by default. The ray finds a surface, and that
/// surface's own reflection is the environment. One mirror never needs more than that, and
/// the pair is what keeps a polished corner honest where two reflectors meet. Two mirrors
/// facing each other are the case that does need more: their tunnel of images has no end in
/// life, and a two-surface chain stops at the third door and shows the sky in it.
///
/// ```swift
/// rayTracedReflections()
/// reflectionBounces(4)     // the corridor keeps receding
/// ```
///
/// Here a colored block stands in a corridor of two near-mirror walls. Move the **Bounces**
/// stepper and watch the tunnel grow a door at a time. Each step costs one more traced ray
/// for every reflected pixel, and each mirror passes on only the fraction it reflects, so
/// the images dim fast: three or four is usually the end of what reads. **Hold the space
/// bar** to drop back to the default pair and compare. Needs an Apple-silicon (ray-tracing)
/// GPU; on other GPUs the environment reflection is all you get.
@main
final class MirrorTunnel: Sketch {

    @Param(2 ... 8, icon: "arrow.triangle.2.circlepath", group: "Reflection")
    var bounces = 4

    override func draw() {
        background(Color(hex: 0x0A0D12))
        // The eye stands *between* the two mirrors and looks at one of them at an angle, so
        // a reflected ray crosses the corridor and meets the other mirror. A slow sway keeps
        // it inside the corridor, where an orbit would carry it out through a wall.
        camera(.orbiting(target: Vector3(3, 0, 0), radius: 3.2,
                         azimuth: -1.216 + sin(time * 0.25) * 0.08,
                         elevation: 0.12 + sin(time * 0.17) * 0.05,
                         fieldOfView: .pi / 3, near: 0.2, far: 40))
        environment(.sunset.intensity(1.15))
        directionalLight(.white, direction: Vector3(0.3, 1, 0.4), intensity: 1.8)
        rayTracedReflections()
        reflectionBounces(isKeyDown(" ") ? 2 : bounces)

        // The two walls, near-mirror metal, facing each other across the corridor.
        for side in [-1.0, 1.0] {
            withState {
                material(.metal(roughness: 0.04))
                fill(Color(hex: 0xEBEDF2))
                translate(side * 3.2, 0, 0)
                drawBox(width: 0.4, height: 6, depth: 14)
            }
        }

        // Something for the tunnel to carry: a block low in the corridor, and a slimmer
        // one further down it, so the receding images have more than one thing in them.
        withState {
            material(.dielectric(roughness: 0.35))
            fill(Color(hex: 0xE4572E))
            translate(0.9, -0.7, 0.2)
            drawBox(width: 0.8, height: 0.8, depth: 0.8)
        }
        withState {
            material(.metal(roughness: 0.18))
            fill(Color(hex: 0x49CF86))
            translate(-0.6, -0.2, -2.6)
            drawBox(width: 0.5, height: 1.6, depth: 0.5)
        }
    }
}
