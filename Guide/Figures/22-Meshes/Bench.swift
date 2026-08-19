// figure: frame=0
//
// Guide payoff (Chapter 22): the bench. Five specimens on a stone slab, one
// technique each: a loaded crystal in thin glass on a lacquered plinth, a crude
// cage the computer rounded, painted iron worn back to metal by a
// metallic-roughness map, a tile carved by a height map and by nothing else,
// and wax on felt. The slab has no uvs, so its stone is projected, and the
// maker's mark is stamped rather than drawn.
import Foundation
import Ollin

final class Bench: Sketch {

    // MARK: pictures authored in code

    /// A height function turned into a green-up normal map by its slopes.
    func normalMap(size: Int, strength: Double, height: (Double, Double) -> Double) -> Image {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let d = 1.0 / Double(size)
        for y in 0 ..< size {
            for x in 0 ..< size {
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

    /// A color picture from a function of the tile's own coordinates.
    func picture(size: Int, _ shade: (Double, Double) -> Color) -> Image {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let c = shade((Double(x) + 0.5) / Double(size), (Double(y) + 0.5) / Double(size))
                let i = (y * size + x) * 4
                bytes[i]     = UInt8((c.red * c.alpha * 255).rounded())
                bytes[i + 1] = UInt8((c.green * c.alpha * 255).rounded())
                bytes[i + 2] = UInt8((c.blue * c.alpha * 255).rounded())
                bytes[i + 3] = UInt8((c.alpha * 255).rounded())
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// The example model this chapter has been loading all along. Found by walking
    /// up from the working directory, since a figure compiles from a copy of itself.
    var modelURL: URL {
        let tail = "Examples/3D/Geometry/LoadedMesh/model.obj"
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            let candidate = directory.appendingPathComponent(tail)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { return candidate }
            directory = parent
        }
    }

    // MARK: the two height functions the pictures are made from

    /// How far the paint has worn back to bare metal at a point on the tile.
    func bareness(_ u: Double, _ v: Double) -> Double {
        smoothstep(0.46, 0.62, fbm(u * 4, v * 8, octaves: 4))
    }

    /// The coin's device, as a height: white is the face, darker is cut into it.
    func device(_ u: Double, _ v: Double) -> Double {
        let r = Vector2(u - 0.5, v - 0.5).length
        let a = atan2(v - 0.5, u - 0.5)
        let rays = smoothstep(0.25, 0.55, sin(a * 6) * 0.5 + 0.5)
        let band = smoothstep(0.3, 0.32, r) * (1 - smoothstep(0.37, 0.39, r))
        let hub = 1 - smoothstep(0.1, 0.25, r)
        return 1 - max(band, hub * rays) * 0.85
    }

    // MARK: the parts

    var bench = Mesh(positions: [], indices: [])
    var worn = Mesh(positions: [], indices: [])
    var tile = Mesh(positions: [], indices: [])
    var star = Mesh(positions: [], indices: [])
    var specimen: Mesh?
    var mark: Decal?

    let plinth = Mesh.box(width: 0.86, height: 0.2, depth: 0.86)
    let cushion = Mesh.sphere(radius: 0.6, segments: 64, rings: 40)
    let egg = Mesh.sphere(radius: 0.34, segments: 48, rings: 32)

    override func setup() {
        seed(714)
        noiseSeed(714)

        // The bench has no uvs worth having, so its stone is projected, grain and all.
        let stone = picture(size: 512) { u, v in
            let grain = fbm(u * 5, v * 5, octaves: 5)
            return Color.mix(Color(hex: 0x585A5C), Color(hex: 0x7C7B74), t: grain)
        }
        let stoneRelief = normalMap(size: 512, strength: 0.35) { u, v in
            fbm(u * 8, v * 8, octaves: 5) * 0.5
        }
        bench = Mesh.box(width: 9, height: 0.5, depth: 5)
            .triplanarTextured(stone, normal: stoneRelief, scale: 2.6)

        // Painted metal, and a map that says where the paint has gone.
        let paint = picture(size: 512) { u, v in
            Color.mix(Color(hex: 0x1D5450), Color(hex: 0xC7BFB0), t: self.bareness(u, v))
        }
        let wear = picture(size: 512) { u, v in
            let b = self.bareness(u, v)
            return Color(red: 0, green: 0.7 - b * 0.5, blue: b)   // g roughness, b metallic
        }
        let scuffs = normalMap(size: 512, strength: 0.05) { u, v in
            fbm(u * 14, v * 14, octaves: 3) * 0.5
        }
        let grain = picture(size: 256) { u, v in
            let n = fbm(u * 30, v * 30, octaves: 3) * 0.5 + 0.5
            return Color(white: 0.5 + (n - 0.5) * 0.5)          // gray is the neutral
        }
        let grainBumps = normalMap(size: 256, strength: 0.06) { u, v in
            fbm(u * 30, v * 30, octaves: 3) * 0.5
        }
        worn = Mesh.sphere(radius: 0.5, segments: 96, rings: 48)
            .textured(paint)
            .normalMapped(scuffs)
            .surfaceMapped(metallicRoughness: wear)
            .detailMapped(grain, normal: grainBumps, scale: 6, strength: 0.5)

        // A tile whose device is carved by a height map rather than by geometry.
        let carved = picture(size: 512) { u, v in Color(white: self.device(u, v)) }
        let slate = picture(size: 512) { u, v in
            Color.mix(Color(hex: 0x3E4A52), Color(hex: 0x8FA0A8), t: self.device(u, v))
        }
        tile = Mesh.plane(width: 1.15, depth: 1.15)
            .textured(slate)
            .parallaxMapped(carved, scale: 0.09)

        // A crude cage, rounded by the computer.
        star = Mesh.extrude(Profile.star(points: 6, outerRadius: 0.46, innerRadius: 0.24), depth: 0.42)
            .subdivided(levels: 2)

        specimen = loadMesh(modelURL.path)?.normalized(scale: 1.15)

        // The bench is stamped where the maker signed it.
        mark = Decal(picture(size: 256) { u, v in
            let r = Vector2(u - 0.5, v - 0.5).length
            let ring = abs(r - 0.34) < 0.02 || abs(r - 0.29) < 0.009
            let bar = abs(v - 0.5) < 0.028 && abs(u - 0.5) < 0.18
            let stem = abs(u - 0.5) < 0.028 && abs(v - 0.5) < 0.18
            return Color(hex: 0x17130E, alpha: (ring || bar || stem) ? 0.7 : 0)
        })
    }

    override func draw() {
        background(Color(hex: 0x0D0E12))
        camera(Camera3D(eye: Vector3(0.55, 2.35, 6.4), target: Vector3(0.15, 0.35, 0.2),
                        projection: .perspective(fieldOfView: .pi / 4.8)))
        environment(.interior.backgroundBlur(0.55))
        directionalLight(Color(kelvin: 4600), direction: Vector3(-0.5, -0.72, -0.5),
                         intensity: 0.85, softness: 0.22)
        castShadows()
        toneMap(.aces)

        // The bench, and the mark stamped into it.
        withState {
            translate(0, -0.25, 0)
            fill(.white)
            material(.dielectric(roughness: 0.85))
            drawMesh(bench)
        }
        if let mark { decal(mark, at: Vector3(-1.4, 0, 1.25), width: 0.7) }

        // The crystal on its lacquered plinth.
        withState {
            translate(-1.45, 0.1, -0.2)
            fill(Color(hex: 0x14100E))
            material(.lacquer)
            drawMesh(plinth)
            if let specimen {
                translate(0, 0.68, 0)
                rotateY(0.6)
                fill(Color(hex: 0xDCEEF6))
                var crystal = Material.glass(roughness: 0.03, ior: 1.48, thickness: 0)
                crystal.attenuationColor = Color(hex: 0xBBE0EC)
                crystal.attenuationDistance = 4
                material(crystal)
                drawMesh(specimen)
            }
        }

        // The cage the computer rounded, in brushed steel.
        withState {
            translate(-0.4, 0.24, 0.5)
            rotateX(-.pi / 2)
            rotateZ(0.5)
            fill(Color(hex: 0xBFC4C9))
            material(.brushedMetal)
            drawMesh(star)
        }

        // Painted iron, worn back to metal.
        withState {
            translate(0.8, 0.5, -0.45)
            rotateY(-0.5)
            fill(.white)
            material(.physicallyBased(metallic: 1, roughness: 1))
            drawMesh(worn)
        }

        // The tile, carved by a picture and by nothing else.
        withState {
            translate(0.1, 0.005, 1.1)
            rotateY(0.28)
            fill(.white)
            material(.dielectric(roughness: 0.55))
            drawMesh(tile)
        }

        // Wax on cloth: the light goes in, wanders, and comes back out.
        withState {
            translate(1.75, 0.12, 0.35)
            fill(Color(hex: 0x3A1018))
            var felt = Material.felt
            felt.sheenColor = Color(hex: 0xB9724F)
            material(felt)
            withState {
                scale(1.35, 0.36, 1.35)
                drawMesh(cushion)
            }
            translate(0, 0.26, 0)
            fill(Color(hex: 0xF2E3C0))
            var wax = Material.marble(radius: 0.12)
            wax.scatteringColor = Color(red: 1, green: 0.66, blue: 0.34)
            material(wax)
            drawMesh(egg)
        }
    }
}
