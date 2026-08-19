// figure: frame=127
//
// Guide figure (Chapter 26): motion blur. Three spheres orbit a still
// colonnade at very different speeds under motionBlur(shutter: 1): the fast
// one draws a long streak along its path, the middle one a short smear, the
// slow one stays nearly crisp, and the still columns and floor hold their
// hard edges, so one still frame shows that the blur belongs to each thing's
// own motion rather than to the picture.
import Ollin

final class MotionStreak: Sketch {
    override var canvasSize: CanvasSize { .square(640) }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        perspective(eye: Vector3(0, 2.3, 7.4), target: Vector3(0, 1.1, 0),
                    fieldOfView: .pi / 3.6, near: 0.5, far: 30)
        ambientLight(Color(white: 0.12))
        directionalLight(.white, direction: Vector3(-0.4, -0.9, -0.5), intensity: 0.9)
        motionBlur(shutter: 1)

        // The colonnade and floor hold still: any streak is a mover's own.
        fill(Color(white: 0.55))
        for i in 0..<8 {
            withState {
                let angle = Double(i) / 8 * .tau
                translate(3.1 * cos(angle), 1.0, 3.1 * sin(angle))
                drawCylinder(radius: 0.16, height: 2.0)
            }
        }

        let orbits: [(speed: Double, phase: Double, radius: Double, height: Double,
                      size: Double, color: Color)] = [
            (7.5, 0.95, 2.2, 1.9, 0.30, Color(hex: 0xE0B040)),
            (2.0, 1.4, 2.6, 1.1, 0.38, Color(hex: 0xC05A3E)),
            (0.4, 0, 1.5, 0.55, 0.46, Color(hex: 0x4E8FB0)),
        ]
        for (i, orbit) in orbits.enumerated() {
            withMotion("sphere-\(i)") {
                withState {
                    fill(orbit.color)
                    rotate(time * orbit.speed + orbit.phase, axis: .unitY)
                    translate(orbit.radius, orbit.height, 0)
                    drawSphere(radius: orbit.size)
                }
            }
        }

        withState {
            fill(Color(white: 0.28))
            translate(0, -0.06, 0)
            drawBox(width: 13, height: 0.12, depth: 13)
        }
    }
}
