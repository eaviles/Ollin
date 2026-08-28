// figure: gif duration=4 fps=8 width=560
//
// Guide figure (Chapter 22): the scene through the glass, on any Mac. The same
// still scene alternates every two seconds between `sceneThroughGlass()` off
// and on, so the colored bars appear inside the pane and the two solid bodies
// and then leave again. No ray tracing anywhere: the camera holds still, and
// the only thing changing is the one call.
import Ollin

final class SceneInTheGlass: Sketch {
    override var canvasSize: CanvasSize { .square(640) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        environment(.studio.intensity(1.1))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.6)
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 8.8, azimuth: 0.05,
                         elevation: 0.12, fieldOfView: .pi / 4.4, near: 2, far: 24))

        // Two seconds with it, two seconds without.
        let on = Int(time) % 4 < 2
        if on { sceneThroughGlass() }

        // A matte floor and three bars behind the row: the content the glass has
        // to carry.
        withState {
            material(.dielectric(roughness: 0.8))
            fill(Color(hex: 0x2E3440))
            translate(0, -0.55, 0)
            drawBox(width: 24, height: 1.0, depth: 14)
        }
        for (i, c) in [Color(hex: 0xE4572E), Color(hex: 0x4FB477), Color(hex: 0x5AA9E6)].enumerated() {
            withState {
                material(.dielectric(roughness: 0.6))
                fill(c)
                translate((Double(i) - 1) * 1.9, 1.5, -2.4)
                drawBox(width: 1.2, height: 4.0, depth: 0.5)
            }
        }

        // A thin pane, a solid body, and a frosted solid.
        let bodies: [(Color, Material, Double)] = [
            (Color(hex: 0xCFE4FF), .glass(), -2.1),
            (.white, .glass(thickness: 1.9), 0),
            (.white, .glass(roughness: 0.3, thickness: 1.9), 2.1),
        ]
        for (c, m, x) in bodies {
            withState {
                material(m)
                fill(c)
                translate(x, 0.95, 0.7)
                drawSphere(radius: 0.95)
            }
        }

        drawCaption(on ? "sceneThroughGlass()" : "the environment alone")
    }
}
