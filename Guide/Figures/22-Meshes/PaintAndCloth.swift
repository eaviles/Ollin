// figure: frame=0
//
// Guide figure (Chapter 22): the two layered finishes. Left pair: the same red
// metal bare and under a clear coat (the coat adds a second, glassy reflection
// over the satin body). Right pair: the same blue cloth bare and with sheen
// (the silhouette catches light while the face stays matte).
import Ollin

final class PaintAndCloth: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ball = Mesh.icosphere(radius: 0.72, subdivisions: 4)

    override func draw() {
        background(Color(hex: 0x1A1E26))
        camera(.perspective(eye: Vector3(0, 0.5, 8.2), target: Vector3(0, 0.15, 0),
                            fieldOfView: .pi / 4.3))
        environment(.studio.lightingOnly())
        toneMap(.aces, exposure: 1.15)
        // One key so the coat's film highlight and the sheen's rim both read.
        pointLight(Color(kelvin: 5200), at: Vector3(3, 4, 6), intensity: 1.1)

        let red = Color(hue: 0.99, saturation: 0.82, brightness: 0.72)
        let blue = Color(hue: 0.62, saturation: 0.6, brightness: 0.42)
        let bodies: [(String, Color, Material)] = [
            ("car paint", red, .carPaint(roughness: 0.45)),
            ("bare metal", red, .metal(roughness: 0.45)),
            ("felt", blue, .felt),
            ("bare cloth", blue, .dielectric(roughness: 0.9)),
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
