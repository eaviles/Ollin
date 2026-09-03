// figure: frame=0
//
// Guide figure (Chapter 26): the fractal leaves. A Mandelbulb, a Menger sponge, and a
// Mandelbox side by side, each a single leaf of the raymarched field, lit and shaded by
// the same tracer that draws a melted sphere. None of the three has a distance function
// anyone can write down; each estimates it by iterating its own map.
import Ollin

final class FractalFields: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 480) }

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.perspective(eye: Vector3(0, 2.3, 8.2), target: Vector3(0, 0.05, 0),
                            fieldOfView: .pi / 4.6))
        directionalLight(.white, direction: Vector3(-0.45, -0.8, -0.4),
                         intensity: 1.2, softness: 0.25)
        ambientLight(Color(white: 0.16))
        material(.clay)

        drawSDF3D(SDF3D.mandelbulb(power: 8, iterations: 8, radius: 1.2)
            .colored(Color(hex: 0xFF6B6B)).rotatedY(0.6).at(-3.1, 0, 0))
        drawSDF3D(SDF3D.mengerSponge(iterations: 3, size: 2.1)
            .colored(Color(hex: 0xFFD166)).rotatedY(0.5).at(0, 0, 0))
        drawSDF3D(SDF3D.mandelbox(scale: -1.5, iterations: 12, size: 2.2)
            .colored(Color(hex: 0x4EA8FF)).rotatedY(0.4).at(3.1, 0, 0))
    }
}
