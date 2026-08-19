// figure: frame=0
//
// Guide figure (Chapter 19): matcaps. The same knot wearing four different
// sphere images; the whole look, lights included, is painted in the picture.
import Ollin

final class MatcapRow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let knot = Mesh.torusKnot(radius: 0.62, tube: 0.21, segments: 220, sides: 14)

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0, 6.9), target: .zero, fieldOfView: .pi / 4))

        let caps: [(name: String, cap: Matcap)] = [
            ("chrome", .chrome), ("terracotta", .terracotta),
            ("carpaint", .carpaint), ("toon", .toon),
        ]
        for (i, entry) in caps.enumerated() {
            withState {
                translate(Double(i) * 2.15 - 3.2, 0.2, 0)
                rotateY(0.6 + Double(i) * 0.3)
                matcap(entry.cap)
                fill(.white)
                drawMesh(knot)
                withBillboard(at: Vector3(0, -1.25, 0)) {
                    fill(.white)
                    textSize(24)
                    textAlign(.center, .middle)
                    drawText(entry.name, 0, 0)
                }
            }
        }
    }
}
