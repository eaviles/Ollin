// figure: frame=0
//
// Guide figure (Chapter 21): glass. Three transmissive bodies in front of
// three colored bars: a solid clear sphere (the bars appear inside it,
// flipped, the lens look), a solid absorbing sphere (bottle green deepening
// with depth), and a thin-walled bubble (the bars pass straight through,
// tinted). Ray-traced, so the glass shows the actual scene behind it.
import Ollin

final class LookingThrough: Sketch {
    override var canvasSize: CanvasSize { .square(640) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        environment(.studio.intensity(1.1))
        rayTracedReflections()
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.6)
        camera(.orbiting(target: Vector3(0, 0.9, 0), radius: 8.8, azimuth: 0.05,
                         elevation: 0.12, fieldOfView: .pi / 4.4, near: 2, far: 24))

        // A matte floor and three bars behind the row: the content the glass
        // has to pass along.
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

        // Clear solid, absorbing solid, thin bubble.
        let bodies: [(Color, Material, Double)] = [
            (.white, .glass(thickness: 1.9), -2.1),
            (.white, .glass(thickness: 1.9, attenuationColor: Color(hex: 0x2E8F5B),
                            attenuationDistance: 1.3), 0),
            (Color(hex: 0xCFE4FF), .glass(), 2.1),
        ]
        for (c, m, x) in bodies {
            withState {
                material(m)
                fill(c)
                translate(x, 0.95, 0.7)
                drawSphere(radius: 0.95)
            }
        }
    }
}
