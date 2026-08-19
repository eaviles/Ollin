// figure: frame=0
//
// Guide figure (Chapter 21): real subsurface scattering. Two pairs under one hard
// side light: the same skin-toned ball bare and scattering (the shadow side keeps
// a warm glow past the terminator), and the same white ball bare and as marble
// (a near-neutral softening). The scattering pair's shadow sides are the point.
import Ollin

final class Subsurface: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ball = Mesh.icosphere(radius: 0.72, subdivisions: 4)

    override func draw() {
        background(Color(hex: 0x1A1E26))
        camera(.perspective(eye: Vector3(0, 0.5, 8.2), target: Vector3(0, 0.15, 0),
                            fieldOfView: .pi / 4.3))
        toneMap(.aces, exposure: 1.1)
        // One hard key from the right, so every ball turns a shadow side toward
        // the viewer's left and the diffusion has somewhere to show.
        directionalLight(.white, direction: Vector3(-1, -0.25, -0.35), intensity: 1.35)
        pointLight(Color(hex: 0xdfe8ff), at: Vector3(-4, 3, 5), intensity: 0.18)

        let skinTone = Color(red: 0.92, green: 0.72, blue: 0.62)
        let stone = Color(white: 0.88)
        let bodies: [(String, Color, Material)] = [
            ("skin", skinTone, .skin(radius: 0.34)),
            ("bare", skinTone, .dielectric(roughness: 0.45)),
            ("marble", stone, .marble(radius: 0.26)),
            ("bare", stone, .dielectric(roughness: 0.2)),
        ]
        for (index, body) in bodies.enumerated() {
            withState {
                translate(Double(index) * 1.9 - 2.85, 0.35, 0)
                fill(body.1)
                material(body.2)
                drawMesh(ball)
                withBillboard(at: Vector3(0, -1.35, 0)) {
                    noStroke()
                    fill(.white)
                    textSize(22)
                    textAlign(.center, .middle)
                    drawText(body.0, 0, 0)
                }
            }
        }
    }
}
