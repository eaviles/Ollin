// figure: frame=0
//
// Guide figure (Chapter 17): one crater height map read three ways. A
// parallax-mapped sphere (carved in shading, perfectly round outline), the
// same map displaced into real geometry (cratered rim), and the bare
// color-mapped control, seen obliquely so the parallax shift shows.
import Ollin

final class HeightRelief: Sketch {

    override var canvasSize: CanvasSize { .size(880, 380) }

    /// An RGBA map authored per texel from a function of (u, v).
    func map(size: Int, _ texel: (Double, Double) -> (Double, Double, Double)) -> Image {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let (r, g, b) = texel((Double(x) + 0.5) * d, (Double(y) + 0.5) * d)
                let i = (y * size + x) * 4
                bytes[i]     = UInt8(max(0, min(255, r * 255)))
                bytes[i + 1] = UInt8(max(0, min(255, g * 255)))
                bytes[i + 2] = UInt8(max(0, min(255, b * 255)))
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// The crater field: 1 at the surface, dipping toward 0 inside each bowl,
    /// wrapping so the sphere's uv seam stays clean.
    func craters(_ u: Double, _ v: Double) -> Double {
        var h = 1.0
        for p in haltonPoints(count: 42, in: Rectangle(x: 0, y: 0, width: 1, height: 1)) {
            var dx = abs(u - p.x); dx = min(dx, 1 - dx)
            var dy = abs(v - p.y); dy = min(dy, 1 - dy)
            let d = (dx * dx + dy * dy).squareRoot() / 0.075
            if d < 1 {
                let bowl = 1 - (1 - d * d) * (1 - d * d)
                h = min(h, bowl)
            }
        }
        return h
    }

    var spheres: [(String, Mesh)] = []

    override func setup() {
        let heightMap = map(size: 512) { u, v in
            let h = craters(u, v)
            return (h, h, h)
        }
        let colorMap = map(size: 512) { u, v in
            let t = 0.55 + 0.45 * craters(u, v)
            return (0.72 * t, 0.6 * t, 0.5 * t)
        }
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)
        spheres = [
            ("parallax", base.textured(colorMap).parallaxMapped(heightMap, scale: 0.06)),
            ("displaced", base.displaced(by: heightMap, scale: 0.13).textured(colorMap)),
            ("bare", base.textured(colorMap)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        // Oblique on purpose: parallax is a view-dependent effect, and a
        // straight-on camera would show only the craters' floors. From the
        // left, so the parallax sphere sits nearest the eye.
        camera(.perspective(eye: Vector3(-2.1, 0.95, 7.0), target: .zero, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.05).lightingOnly())
        directionalLight(Color(white: 0.9), direction: Vector3(-0.5, -0.6, -0.6))

        fill(.white)
        material(.dielectric(roughness: 0.75))
        let xs: [Double] = [-2.55, 0, 2.55]
        for (i, entry) in spheres.enumerated() {
            withState {
                translate(xs[i], 0.28, 0)
                drawMesh(entry.1)
                withBillboard(at: Vector3(0, -1.42, 0)) {
                    fill(Color(white: 0.6))
                    textSize(20)
                    textAlign(.center, .middle)
                    drawText(entry.0, 0, 0)
                }
            }
        }
        material(Material())
    }
}
