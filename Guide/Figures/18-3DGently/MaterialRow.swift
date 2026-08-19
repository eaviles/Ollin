// figure: frame=0
//
// Guide contact sheet (Chapter 18): ten materials from the library on the
// same sphere, in the same fill color. The color is the fill; the material
// is how the surface catches light.
import Ollin

final class MaterialRow: Sketch {
    let looks: [(name: String, material: Material)] = [
        ("matte", .matte), ("plastic", .plastic), ("glossy", .glossy),
        ("iridescent", .iridescent), ("soapBubble", .soapBubble),
        ("velvet", .velvet), ("jade", .jade), ("toon", .toon),
        ("gooch", .gooch), ("glitter", .glitter),
    ]

    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0, 10), target: .zero, fieldOfView: .pi / 4))
        lightingPreset(.threePoint)

        let columns = 5, colSpacing = 2.35, rowSpacing = 3.05
        let x0 = -colSpacing * Double(columns - 1) / 2

        for (i, look) in looks.enumerated() {
            withState {
                translate(x0 + colSpacing * Double(i % columns),
                          1.35 - rowSpacing * Double(i / columns), 0)
                material(look.material)
                fill(Color(hex: 0x2C8C86))
                drawSphere(radius: 1.0, segments: 48, rings: 32)
                withBillboard(at: Vector3(0, -1.32, 0)) {
                    fill(.white)
                    textSize(26)
                    textAlign(.center, .middle)
                    drawText(look.name, 0, 0)
                }
            }
        }
    }
}
