// figure: frame=0
//
// Guide figure (Chapter 29): the hologram finish. One grated metal under one
// light: a flat plate whose rainbow sits where the grating equation puts it, a
// sphere with the first order on both sides of its highlight, and a sheet of
// flat facets from a normal map, where every facet turns the grooves its own
// way and the rainbow breaks into pieces.
import Ollin

final class Hologram: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }
    private var crumple: Image?

    override func setup() {
        let size = 384
        let field = FacetField.crumpled(in: Rectangle(x: 0, y: 0, width: Double(size), height: Double(size)),
                                        spacing: 52, crinkle: 0.85, seed: 7)
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                let n = field.facet(containing: p)?.normal ?? Vector3(0, 0, 1)
                let i = (y * size + x) * 4
                bytes[i] = UInt8((n.x * 0.5 + 0.5) * 255)
                bytes[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                bytes[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
            }
        }
        crumple = Image(width: size, height: size, premultipliedRGBA: bytes)
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        camera(.perspective(eye: Vector3(0, 0.6, 8.6), target: Vector3(0, 0.05, 0),
                            fieldOfView: .pi / 4.6))
        environment(.studio.intensified(to: 0.2).lightingOnly())
        toneMap(.aces, exposure: 1.0)
        // Tilted so the plate's first order sits across its middle.
        directionalLight(.white, direction: Vector3(-0.2, -0.42, -0.85), intensity: 1.6)

        fill(Color(white: 0.82))
        let bodies: [String] = ["a plate", "a sphere", "a crumpled sheet"]
        for (index, label) in bodies.enumerated() {
            withState {
                translate(Double(index) * 2.75 - 2.75, 0.25, 0)
                material(.hologram)
                switch index {
                case 0:
                    rotateX(.pi / 2)
                    drawPlane(width: 2.2, depth: 2.2)
                case 1:
                    drawSphere(radius: 1.08)
                default:
                    rotateX(.pi / 2)
                    if let crumple {
                        drawMesh(Mesh.plane(width: 2.2, depth: 2.2).normalMapped(crumple, scale: 1))
                    }
                }
            }
            withState {
                withBillboard(at: Vector3(Double(index) * 2.75 - 2.75, -1.35, 0)) {
                    noStroke()
                    fill(Color(white: 0.6))
                    textSize(20)
                    textAlign(.center, .middle)
                    drawText(label, 0, 0)
                }
            }
        }
    }
}
