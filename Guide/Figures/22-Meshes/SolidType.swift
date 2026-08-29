// figure: frame=0
//
// Guide figure (Chapter 22): a word as a solid. Left, the whole string as one
// mesh, turned enough to show that it has a thickness and that the O keeps its
// hole. Right, the same word a letter at a time, each letter tipped about its
// own center. Both stand on the same floor and throw the same kind of shadow,
// which is the point: type here is a solid like any other.
import Foundation
import Ollin

final class SolidType: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    let word = "Ollin"
    let size = 1.55

    override func draw() {
        background(Color(hex: 0x0B0D14))
        camera(.perspective(eye: Vector3(0, 3.6, 7.4), target: Vector3(0, 1.1, 0),
                            fieldOfView: .pi / 4.2))
        directionalLight(.white, direction: Vector3(-0.45, -0.85, -0.4), intensity: 1.35)
        pointLight(Color(hex: 0xFFD9A8), at: Vector3(5, 3.5, 5), intensity: 0.6,
                   castsShadow: false)
        ambientLight(Color(hex: 0x161B2C))
        castShadows()
        noStroke()

        fill(Color(hex: 0x14161F))
        material(.dielectric(roughness: 0.7))
        drawPlane(width: 80, depth: 80)

        // Left: one mesh, turned so the walls and the counter of the O show.
        let whole = Mesh.text(word, size: size, depth: 0.28)
        withState {
            translate(-2.9, whole.bounds.max.y + 0.55, 0)
            rotateY(0.72)
            fill(Color(hex: 0xE8C88A))
            material(.metal(roughness: 0.28))
            drawMesh(whole)
        }

        // Right: the same word, each letter tipped about its own center.
        let letters = Mesh.textGlyphs(word, size: size, depth: 0.28)
        withState {
            translate(3.1, whole.bounds.max.y + 0.55, 0)
            fill(Color(hex: 0x7FD4FF))
            material(.dielectric(roughness: 0.35))
            for (i, glyph) in letters.enumerated() {
                let pivot = glyph.center
                withState {
                    translate(pivot)
                    rotateX(sin(Double(i) * 1.1) * 0.9)
                    translate(-pivot)
                    drawMesh(glyph)
                }
            }
        }

        for (x, label) in [(-2.9, "Mesh.text"), (3.1, "Mesh.textGlyphs")] {
            withBillboard(at: Vector3(x, 0.16, 1.2)) {
                fill(.white)
                textSize(21)
                textAlign(.center, .middle)
                drawText(label, 0, 0)
            }
        }
    }
}
