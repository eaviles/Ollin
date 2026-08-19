// figure: frame=0
//
// Guide figure (Chapter 19): normal maps. Two spheres wearing authored
// normal maps (hammered dents, engraved rings) beside the bare control:
// same geometry, same light, and the silhouettes stay perfect circles.
import Ollin

final class SurfaceRelief: Sketch {

    override var canvasSize: CanvasSize { .size(880, 380) }

    /// A height function turned into a green-up normal map by its slopes.
    func normalMap(size: Int, strength: Double, height: (Double, Double) -> Double) -> Image {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let dx = (height(u + d, v) - height(u - d, v)) / (2 * d) * strength
                let dy = (height(u, v + d) - height(u, v - d)) / (2 * d) * strength
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * size + x) * 4
                bytes[i]     = UInt8((-dx / len * 0.5 + 0.5) * 255)
                bytes[i + 1] = UInt8((dy / len * 0.5 + 0.5) * 255)
                bytes[i + 2] = UInt8((1 / len * 0.5 + 0.5) * 255)
                bytes[i + 3] = 255
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    var spheres: [(String, Mesh)] = []

    override func setup() {
        let dents = haltonPoints(count: 90, in: Rectangle(x: 0, y: 0, width: 1, height: 1))
        let hammered = normalMap(size: 512, strength: 0.12) { u, v in
            var h = 0.0
            for p in dents {
                var dx = abs(u - p.x); dx = min(dx, 1 - dx)
                var dy = abs(v - p.y); dy = min(dy, 1 - dy)
                let r = 0.075, dist = (dx * dx + dy * dy).squareRoot()
                if dist < r {
                    let t = dist / r
                    h = max(h, (1 - t * t) * (1 - t * t))
                }
            }
            return h
        }
        let rings = normalMap(size: 512, strength: 0.07) { u, v in
            let r = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot()
            return sin(r * 24 * .tau) * 0.5 + 0.5
        }
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)
        spheres = [("hammered", base.normalMapped(hammered)),
                   ("rings", base.normalMapped(rings)),
                   ("bare", base)]
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.4, 8.2), target: .zero, fieldOfView: .pi / 4))
        directionalLight(Color(kelvin: 5200), direction: Vector3(-0.7, -0.5, -0.55), intensity: 1.1)
        directionalLight(Color(kelvin: 9000), direction: Vector3(0.6, 0.25, 0.4), intensity: 0.22)
        ambientLight(Color(white: 0.07))

        fill(Color(hex: 0xB9BDC7))
        let xs: [Double] = [-2.5, 0, 2.5]
        for (i, entry) in spheres.enumerated() {
            withState {
                translate(xs[i], 0.28, 0)
                drawMesh(entry.1)
                withBillboard(at: Vector3(0, -1.32, 0)) {
                    fill(Color(white: 0.6))
                    textSize(24)
                    textAlign(.center, .middle)
                    drawText(entry.0, 0, 0)
                }
            }
        }
    }
}
