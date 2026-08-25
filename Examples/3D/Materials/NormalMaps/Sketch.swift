import Ollin

/// Normal maps: per-pixel surface relief without per-pixel geometry.
///
/// A tangent-space normal map stores a surface direction in each texel; at
/// shading time the lighting normal bends by it, so a smooth sphere catches
/// light like hammered metal, woven cloth, or engraved rings while its
/// silhouette stays a perfect circle (the giveaway, and the point: relief this
/// way costs a texture sample, not a million triangles).
///
/// The three maps here are *authored in setup*, no image files: each starts as
/// a height function (dents packed by a low-discrepancy sequence, a weave of
/// crossing sine bands, concentric rings), and its normals fall out as the
/// height's slopes, in the standard green-up encoding `(n + 1) / 2`. Attaching
/// one is `mesh.normalMapped(map)`, which also generates the per-vertex
/// tangent basis the map needs (MikkTSpace, the same basis normal-map bakers
/// target, so maps baked in other tools light the same way). The `relief` knob
/// is the map's strength: 0 turns it off, 1 is as authored, higher exaggerates.
///
/// The fourth sphere is the bare control: same geometry, same light, no map.
@main
final class NormalMaps: Sketch {

    @Param(0...3, icon: "circle.grid.cross") var relief = 1.0

    var spheres: [Mesh] = []

    /// Turn a height function (0…1 over the unit square) into a green-up
    /// normal map: central-difference slopes, x right, y up the image.
    func normalMap(size: Int, strength: Double, height: (Double, Double) -> Double) -> Image {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x) + 0.5) * d, v = (Double(y) + 0.5) * d
                let dx = (height(u + d, v) - height(u - d, v)) / (2 * d) * strength
                let dy = (height(u, v + d) - height(u, v - d)) / (2 * d) * strength
                // A slope rising down the image is +dy; green-up encodes the
                // *up*-the-image tilt.
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let n = (x: -dx / len, y: dy / len, z: 1 / len)
                let i = (y * size + x) * 4
                bytes[i]     = UInt8((n.x * 0.5 + 0.5) * 255)
                bytes[i + 1] = UInt8((n.y * 0.5 + 0.5) * 255)
                bytes[i + 2] = UInt8((n.z * 0.5 + 0.5) * 255)
                bytes[i + 3] = 255
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    override func setup() {
        // Hammered: soft dents at low-discrepancy points (pure index math, so
        // every run of this variation is identical).
        let dents = haltonPoints(count: 90, in: Rectangle(x: 0, y: 0, width: 1, height: 1))
        let hammered = normalMap(size: 512, strength: 0.16) { u, v in
            var h = 0.0
            for p in dents {
                var dx = abs(u - p.x); dx = min(dx, 1 - dx)   // tile both ways
                var dy = abs(v - p.y); dy = min(dy, 1 - dy)
                let r = 0.075, dist = (dx * dx + dy * dy).squareRoot()
                if dist < r {
                    let t = dist / r
                    h = max(h, (1 - t * t) * (1 - t * t))
                }
            }
            return h
        }
        // Woven: two crossing sine bands.
        let woven = normalMap(size: 256, strength: 0.045) { u, v in
            let a = unipolar(sin(u * 24 * .tau))
            let b = unipolar(sin(v * 24 * .tau))
            return a * b
        }
        // Engraved rings around the map center.
        let rings = normalMap(size: 512, strength: 0.09) { u, v in
            let r = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot()
            return unipolar(sin(r * 30 * .tau))
        }
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)
        spheres = [base.normalMapped(hammered),
                   base.normalMapped(woven),
                   base.normalMapped(rings),
                   base]
    }

    override func draw() {
        background(Color(hex: 0x11141B))
        cameraShowcase(.sway(amplitude: 0.14, period: 26), target: .zero, radius: 11.2,
                       elevation: 0.14, fieldOfView: .pi / 4)

        // A warm key swinging past, a dim cool fill: relief reads by how its
        // shading slides, so the key keeps moving.
        let angle = time * 0.6
        directionalLight(Color(kelvin: 5000),
                         direction: Vector3(-cos(angle), -0.55, -sin(angle)), intensity: 1.15)
        directionalLight(Color(kelvin: 9000), direction: Vector3(0.5, 0.3, 0.4), intensity: 0.2)
        ambientLight(Color(white: 0.06))

        fill(Color(hex: 0xB9BDC7))
        let xs: [Double] = [-3.45, -1.15, 1.15, 3.45]
        for (i, var mesh) in spheres.enumerated() {
            if mesh.material != nil { mesh.material!.normalScale = relief }
            withState {
                translate(xs[i], 0.25, 0)
                drawMesh(mesh)
            }
        }
        drawLabels(at: xs)
    }

    private func drawLabels(at xs: [Double]) {
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.55))
            for (name, x) in zip(["hammered", "woven", "rings", "bare"], xs) {
                if let p = project(Vector3(x, -1.35, 0)) {
                    drawText(name, at: p)
                }
            }
        }
    }
}
