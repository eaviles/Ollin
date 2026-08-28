// figure: frame=0
//
// Guide figure (Chapter 22): color made by interference. The same polished
// metal bare and under two films of different thickness, then a soap wall.
// Nothing here is tinted: the color comes from the film's thickness alone.
import Ollin

final class ThinFilm: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ball = Mesh.icosphere(radius: 0.72, subdivisions: 4)

    override func draw() {
        background(Color(hex: 0x14171E))
        camera(.perspective(eye: Vector3(0, 0.5, 8.2), target: Vector3(0, 0.15, 0),
                            fieldOfView: .pi / 4.3))
        // A room to reflect, kept off the backdrop so the bodies carry the picture.
        environment(.courtyard.intensity(1.2).rotated(-0.8).lightingOnly())
        sceneThroughGlass()
        toneMap(.aces, exposure: 1.1)
        pointLight(Color(kelvin: 5200), at: Vector3(3, 4, 6), intensity: 1.0)

        let steel = Color(white: 0.75)
        var film360 = Material.metal(roughness: 0.16)
        film360.thinFilm = 1
        film360.thinFilmThickness = 360
        var film600 = film360
        film600.thinFilmThickness = 600

        let bodies: [(String, Color, Material)] = [
            ("bare metal", steel, .metal(roughness: 0.16)),
            ("360 nm", steel, film360),
            ("600 nm", steel, film600),
            ("soap film", Color(white: 0.85), .soapFilm(thickness: 520)),
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
