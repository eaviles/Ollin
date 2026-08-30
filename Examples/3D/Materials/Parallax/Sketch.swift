import Ollin

/// One height map, read two ways: parallax occlusion and real displacement.
///
/// A height map is a picture of relief, white at the surface and darker the
/// deeper it is carved. `parallaxMapped(_:scale:)` reads it per pixel: the
/// renderer marches the eye ray through the relief and shifts what every other
/// map shows, so the craters sink convincingly and slide with the view, yet
/// not one vertex has moved. `displaced(by:scale:)` reads the same image as
/// geometry: vertices really move, normals are recomputed, and the relief
/// becomes true of the mesh.
///
/// The silhouette is the tell, and the whole lesson: turn the spheres and
/// watch their outlines. The parallax sphere stays a perfect circle no matter
/// how deep the craters look (shading only, the technique's honest envelope,
/// and the same reason its cast shadow and reflection stay round); the
/// displaced sphere's rim is genuinely cratered. Inside the outline the two
/// read almost alike, which is exactly why parallax is worth having: all of
/// the depth at none of the geometry.
///
/// The map is authored in setup from a function, no image files; `depth` drives
/// the parallax relief live.
@main
final class Parallax: Sketch {

    @Param(0...0.12, icon: "arrow.down.to.line") var depth = 0.06

    var parallaxSphere = Mesh(positions: [], normals: [], indices: [])
    var displacedSphere = Mesh(positions: [], normals: [], indices: [])
    var bare = Mesh(positions: [], normals: [], indices: [])

    /// An RGBA image authored per texel from a function of (u, v).
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

    /// The crater field: 1 at the surface, dipping toward 0 inside each bowl.
    /// Craters seed at low-discrepancy points (pure index math, so every run
    /// is identical) and wrap, so the sphere's uv seam stays clean.
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

    override func setup() {
        let heightMap = map(size: 512) { u, v in
            let h = craters(u, v)
            return (h, h, h)
        }
        // The color map follows the same field, so the floors read dusty.
        let colorMap = map(size: 512) { u, v in
            let h = craters(u, v)
            let t = 0.55 + 0.45 * h
            return (0.72 * t, 0.6 * t, 0.5 * t)
        }
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)
        parallaxSphere = base.textured(colorMap).parallaxMapped(heightMap, scale: 0.06)
        displacedSphere = base.displaced(by: heightMap, scale: 0.13).textured(colorMap)
        bare = base.textured(colorMap)
    }

    override func draw() {
        background(Color(hex: 0x0E1116))
        cameraShowcase(.sway(amplitude: 0.2, period: 24), target: .zero, radius: 8.6,
                       elevation: 0.12, fieldOfView: .pi / 4)
        environment(.studio.intensified(to: 1.05))
        directionalLight(Color(white: 0.9), direction: Vector3(-0.5, -0.6, -0.6))

        var carved = parallaxSphere
        carved.material?.heightScale = depth

        fill(.white)
        material(.dielectric(roughness: 0.75))
        let xs: [Double] = [-2.4, 0, 2.4]
        for (mesh, x) in zip([carved, displacedSphere, bare], xs) {
            withState {
                translate(x, 0.25, 0)
                drawMesh(mesh)
            }
        }
        material(Material())
        drawLabels(at: xs)
    }

    private func drawLabels(at xs: [Double]) {
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.55))
            for (name, x) in zip(["parallax", "displaced", "bare"], xs) {
                if let p = project(Vector3(x, -1.45, 0)) {
                    drawText(name, at: p)
                }
            }
        }
    }
}
