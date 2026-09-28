// figure: frame=0
//
// Guide figure (Chapter 30): the distortions. A column twisted about its
// upright axis, a bar bent about z, a sphere rippled by a product of sines, and
// a sphere roughened by noise, each one field bent whole before the tracer
// draws it. The amounts are fixed, so the still is the same every run.
import Ollin

final class Distortions: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 480) }

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.perspective(eye: Vector3(0, 2.3, 8.6), target: Vector3(0, 0.05, 0),
                            fieldOfView: .pi / 4.6))
        directionalLight(.white, direction: Vector3(-0.45, -0.8, -0.4),
                         intensity: 1.2, softness: 0.25)
        ambientLight(Color(white: 0.16))
        material(.clay)

        drawSDF3D(SDF3D.box(width: 0.8, height: 2.4, depth: 0.8)
            .twisted(1.2)
            .colored(Color(hex: 0x46C2FF)).at(-3.9, 0, 0))
        drawSDF3D(SDF3D.box(width: 2.2, height: 0.5, depth: 0.7)
            .bent(0.6)
            .colored(Color(hex: 0xFFB454)).at(-1.45, 0, 0))
        drawSDF3D(SDF3D.sphere(radius: 0.95)
            .displaced(amplitude: 0.1, frequency: 6)
            .colored(Color(hex: 0xFF6F61)).at(1.15, 0, 0))
        drawSDF3D(SDF3D.sphere(radius: 0.95)
            .roughened(amplitude: 0.15, frequency: 3)
            .colored(Color(hex: 0x9AA7B8)).at(3.75, 0, 0))
    }
}
