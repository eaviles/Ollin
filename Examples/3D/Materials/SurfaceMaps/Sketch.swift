import Ollin

/// The rest of the surface-map set: metallic-roughness, occlusion, and emissive
/// maps, the pictures that vary a physically-based finish per pixel.
///
/// Where a normal map changes how light *lands*, these change what the surface
/// *is* from texel to texel: a metallic-roughness map decides where a sphere is
/// bare polished metal and where it is dull paint (roughness rides the green
/// channel, metallic the blue, the standard packing), an occlusion map settles
/// shadow into crevices the geometry doesn't have, and an emissive map makes
/// parts of the surface give off light of their own.
///
/// Every map here is *authored in setup* from a function, no image files, and
/// attaching one is `mesh.surfaceMapped(...)`. The worn sphere draws under
/// `material(.physicallyBased(metallic: 1, roughness: 1))`: the sampled
/// channels multiply the finish, so factors of 1 show the maps as authored.
/// The occlusion sphere pairs its map with a normal map built from the same
/// height field, which is the usual recipe: the relief catches the light, the
/// occlusion keeps its grooves dark.
///
/// The fourth sphere is the bare control: same geometry, same environment,
/// finish only.
@main
final class SurfaceMaps: Sketch {

    @Param(0...4, icon: "lightbulb") var glow = 1.6

    var worn = Mesh(positions: [], normals: [], indices: [])
    var grooved = Mesh(positions: [], normals: [], indices: [])
    var lit = Mesh(positions: [], normals: [], indices: [])
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

    /// A green-up normal map from a height function (the NormalMaps recipe).
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

    /// A tiling patch mask: 1 inside soft blobs seeded at low-discrepancy
    /// points (pure index math, so every run is identical), 0 between them.
    func patches(_ u: Double, _ v: Double, seeds: [Vector2], radius: Double) -> Double {
        var m = 0.0
        for p in seeds {
            var dx = abs(u - p.x); dx = min(dx, 1 - dx)
            var dy = abs(v - p.y); dy = min(dy, 1 - dy)
            let d = (dx * dx + dy * dy).squareRoot()
            if d < radius {
                let t = d / radius
                m = max(m, (1 - t * t) * (1 - t * t))
            }
        }
        return m
    }

    override func setup() {
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)

        // Worn paint over metal: where the paint has rubbed through, the
        // surface turns metallic and polished; the paint itself is a rough
        // dielectric. One packed map says all of it.
        let wear = haltonPoints(count: 26, in: Rectangle(x: 0, y: 0, width: 1, height: 1))
        let orm = map(size: 512) { u, v in
            let bare = min(1, patches(u, v, seeds: wear, radius: 0.09) * 2.2)
            return (1, 0.72 - 0.5 * bare, bare)   // r unused, g roughness, b metallic
        }
        worn = base.textured(map(size: 512) { u, v in
            let bare = min(1, patches(u, v, seeds: wear, radius: 0.09) * 2.2)
            let paint = (r: 0.68, g: 0.34, b: 0.22)
            return (paint.r + (0.9 - paint.r) * bare,
                    paint.g + (0.9 - paint.g) * bare,
                    paint.b + (0.88 - paint.b) * bare)
        }).surfaceMapped(metallicRoughness: orm)

        // A coffered grid: the same height field authors the relief (normal
        // map) and the crevice shadow (occlusion map), the usual pairing.
        func coffer(_ u: Double, _ v: Double) -> Double {
            let a = min(abs(u * 8 - (u * 8).rounded()), abs(v * 8 - (v * 8).rounded()))
            return smoothstep(0.06, 0.2, a)
        }
        let relief = normalMap(size: 512, strength: 0.12, height: coffer)
        let cavity = map(size: 512) { u, v in
            let ao = 0.25 + 0.75 * coffer(u, v)
            return (ao, ao, ao)
        }
        grooved = base.normalMapped(relief).surfaceMapped(occlusion: cavity)
        grooved.material?.baseColor = Color(red: 0.75, green: 0.73, blue: 0.7)

        // Emissive seams: a dark rough shell whose engraved channels give off
        // their own light; the factor is the brightness dial (`glow`).
        lit = base.surfaceMapped(
            emissive: map(size: 512) { u, v in
                let band = { (t: Double) -> Double in
                    let f = abs(t - t.rounded())
                    return 1 - smoothstep(0.03, 0.08, f)
                }
                let seam = max(band(u * 6), band(v * 3))
                return (seam * 0.25, seam * 0.85, seam)
            })
        lit.material?.baseColor = Color(red: 0.09, green: 0.1, blue: 0.12)

        bare = base
    }

    override func draw() {
        background(Color(hex: 0x0E1116))
        cameraShowcase(.sway(amplitude: 0.14, period: 26), target: .zero, radius: 11.2,
                       elevation: 0.14, fieldOfView: .pi / 4)
        environment(.studio.intensity(1.05))

        var glowing = lit
        glowing.material?.emissiveFactor = Color(white: min(1, glow / 4))

        fill(.white)
        let xs: [Double] = [-3.45, -1.15, 1.15, 3.45]
        // The worn sphere and the bare control draw under the identity factors
        // (the maps say what's metal); the occlusion and emissive spheres are
        // plain dielectrics, their maps riding on top.
        let spheres: [(Mesh, Material)] = [
            (worn, .physicallyBased(metallic: 1, roughness: 1)),
            (grooved, .dielectric(roughness: 0.55)),
            (glowing, .dielectric(roughness: 0.85)),
            (bare, .physicallyBased(metallic: 1, roughness: 1)),
        ]
        for (i, (mesh, finish)) in spheres.enumerated() {
            material(finish)
            withState {
                translate(xs[i], 0.25, 0)
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
            for (name, x) in zip(["worn metal", "occlusion", "emissive", "bare"], xs) {
                if let p = project(Vector3(x, -1.35, 0)) {
                    drawText(name, at: p)
                }
            }
        }
    }
}
