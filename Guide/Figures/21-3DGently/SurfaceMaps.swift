// figure: frame=0
//
// Guide figure (Chapter 21): the PBR map set. Three spheres whose maps vary
// the surface itself per texel (worn paint turning to polished metal, a
// coffered grid whose one height field makes both relief and occlusion,
// emissive seams on a dark shell) beside the bare control, under one
// studio environment.
import Ollin

final class SurfaceMaps: Sketch {

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

    var spheres: [(String, Mesh, Material)] = []

    override func setup() {
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)

        // Worn paint over metal, one packed map (roughness g, metallic b).
        let wear = haltonPoints(count: 26, in: Rectangle(x: 0, y: 0, width: 1, height: 1))
        func bare(_ u: Double, _ v: Double) -> Double {
            var m = 0.0
            for p in wear {
                var dx = abs(u - p.x); dx = min(dx, 1 - dx)
                var dy = abs(v - p.y); dy = min(dy, 1 - dy)
                let r = 0.09, dist = (dx * dx + dy * dy).squareRoot()
                if dist < r {
                    let t = dist / r
                    m = max(m, (1 - t * t) * (1 - t * t))
                }
            }
            return min(1, m * 2.2)
        }
        let worn = base.textured(map(size: 512) { u, v in
            let b = bare(u, v)
            return (0.68 + 0.22 * b, 0.34 + 0.56 * b, 0.22 + 0.66 * b)
        }).surfaceMapped(metallicRoughness: map(size: 512) { u, v in
            (1, 0.72 - 0.5 * bare(u, v), bare(u, v))
        })

        // One height field authoring both the relief and its occlusion.
        func coffer(_ u: Double, _ v: Double) -> Double {
            let a = min(abs(u * 8 - (u * 8).rounded()), abs(v * 8 - (v * 8).rounded()))
            return smoothstep(0.06, 0.2, a)
        }
        var grooved = base.normalMapped(normalMap(size: 512, strength: 0.12, height: coffer))
            .surfaceMapped(occlusion: map(size: 512) { u, v in
                let ao = 0.25 + 0.75 * coffer(u, v)
                return (ao, ao, ao)
            })
        grooved.material?.baseColor = Color(red: 0.75, green: 0.73, blue: 0.7)

        // Emissive seams on a dark shell.
        var lit = base.surfaceMapped(emissive: map(size: 512) { u, v in
            func band(_ t: Double) -> Double {
                let f = abs(t - t.rounded())
                return 1 - smoothstep(0.03, 0.08, f)
            }
            let seam = max(band(u * 6), band(v * 3))
            return (seam * 0.25, seam * 0.85, seam)
        })
        lit.material?.baseColor = Color(red: 0.09, green: 0.1, blue: 0.12)
        lit.material?.emissiveFactor = Color(white: 0.5)

        spheres = [("worn metal", worn, .physicallyBased(metallic: 1, roughness: 1)),
                   ("occlusion", grooved, .dielectric(roughness: 0.55)),
                   ("emissive", lit, .dielectric(roughness: 0.85)),
                   ("bare", base, .physicallyBased(metallic: 1, roughness: 1))]
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.45, 9.2), target: .zero, fieldOfView: .pi / 4))
        // The environment lights the metals; the backdrop stays the dark card
        // (the sibling figure's look), so the maps carry the picture.
        environment(.studio.intensity(1.05).lightingOnly())

        fill(.white)
        let xs: [Double] = [-3.6, -1.2, 1.2, 3.6]
        for (i, entry) in spheres.enumerated() {
            material(entry.2)
            withState {
                translate(xs[i], 0.28, 0)
                drawMesh(entry.1)
                withBillboard(at: Vector3(0, -1.32, 0)) {
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
