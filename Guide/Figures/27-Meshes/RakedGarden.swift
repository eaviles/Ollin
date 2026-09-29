// figure: frame=0
//
// Guide payoff (Chapter 27): the raked garden. A bed of pale gravel raked into
// straight grooves that bend into rings around three stones, set in moss under
// a low warm sun from behind. The sand is a plane with a picture wrapped on it,
// carved by a height map read as real geometry, with a finer grain picture tiled over it
// for a close look. Each stone is a plain box rounded by three levels of
// subdivision, which leaves it with no uvs, so its granite is projected on from
// three sides. Three red leaves are one decal drifting on the breeze; at the
// frame kept, the first lies on top of the largest stone. (Across its rim, the
// decal lands twice: once on the stone and once on the sand the rounded side
// leaves in view below it.) The noise seed is pinned, so every picture comes
// out the same.
import Ollin

final class RakedGarden: Sketch {
    // Each stone: where it sits, the box its cage starts as, and how far it is turned.
    let stones: [(x: Double, z: Double, size: Vector3, turn: Double)] = [
        (-1.7, 0.3, Vector3(1.9, 0.62, 1.3), 0.3),
        (-0.2, -1.4, Vector3(0.8, 1.5, 0.75), -0.2),
        (2.4, 1.2, Vector3(1.0, 0.5, 0.75), 0.9),
    ]
    var sand = Mesh(positions: [], indices: [])
    var pebbles: [Mesh] = []
    var leaf: Decal?

    /// A square picture from a function of its own coordinates, u across and v down.
    func picture(size: Int, _ shade: (Double, Double) -> Color) -> Image {
        let image = Image(width: size, height: size)
        for y in 0 ..< size {
            for x in 0 ..< size {
                image[x, y] = shade((Double(x) + 0.5) / Double(size), (Double(y) + 0.5) / Double(size))
            }
        }
        return image
    }

    /// The rake's height at a point of the bed: rings around the stones, lines elsewhere.
    func rake(_ u: Double, _ v: Double) -> Double {
        let p = Vector2((u - 0.5) * 10, (v - 0.5) * 9)       // the point's x and z on the bed
        var gap = 99.0                                       // how far to the nearest stone
        for s in stones {
            gap = min(gap, p.distance(to: Vector2(s.x, s.z)) - (s.size.x + s.size.z) * 0.25 - 0.1)
        }
        let across = gap < 0.9 ? max(gap, 0) : p.y
        return 0.5 + 0.5 * cos(across * .tau / 0.2)          // one groove every 0.2 units
    }

    override func setup() {
        noiseSeed(27)

        // The sand: a picture wrapped on, the rake carved in, and grain for a close look.
        let heights = picture(size: 800) { u, v in Color(white: rake(u, v)) }
        let tone = picture(size: 200) { u, v in Color(white: 0.7 + 0.2 * fbm(u * 9, v * 8)) }
        let grain = picture(size: 64) { u, v in                  // gray is the neutral
            Color(white: 0.3 + 0.4 * tilingFbm(u, v, detail: 16, octaves: 2))
        }
        sand = Mesh.plane(width: 10, depth: 9, segments: 400)
            .displaced(by: heights, scale: 0.04)
            .textured(tone)
            .detailMapped(grain, scale: 18)

        // Boxes rounded into stones. They come back with no uvs, so the granite is projected.
        let granite = picture(size: 256) { u, v in
            let n = smoothstep(0.3, 0.7, tilingFbm(u, v, detail: 5, octaves: 5))
            return Color.mix(Color(hex: 0x3D3F42), Color(hex: 0x9C988F), n)
        }
        pebbles = stones.map { s in
            Mesh.box(width: s.size.x, height: s.size.y, depth: s.size.z)
                .subdivided(levels: 3)
                .triplanarTextured(granite, scale: 1.4)
        }

        // A leaf: five pointed lobes, and clear everywhere outside them.
        leaf = Decal(picture(size: 128) { u, v in
            let x = u - 0.5, y = v - 0.5
            let r = (x * x + y * y).squareRoot()
            let lobe = abs(sin(atan2(x, -y) * 2.5))           // 0 along a lobe, 1 between two
            let inside = 1 - smoothstep(-0.01, 0.01, r - 0.45 + 0.27 * lobe)
            return Color.mix(Color(hex: 0xEC7C2F), Color(hex: 0xA3201A), r / 0.45).withAlpha(inside)
        })
    }

    override func draw() {
        background(Color(hex: 0x1B2024))
        cameraShowcase(target: Vector3(0, 0.2, 0), radius: 9, elevation: 0.8, fieldOfView: .pi / 4.2)
        ambientLight(Color(hex: 0x30363F))
        directionalLight(Color(hex: 0xFFD4A0), direction: Vector3(0.55, -0.5, 0.65), intensity: 1.15)
        headlight(Color(hex: 0x9DB2D6), intensity: 0.25)     // lifts the sides turned from the sun
        castShadows()

        material(.matte)
        fill(Color(hex: 0x323E27))                           // moss around the bed
        withState { translate(0, -0.05, 0); drawPlane(width: 40, depth: 40) }
        fill(.white)
        drawMesh(sand)

        for (s, pebble) in zip(stones, pebbles) {
            withState { translate(s.x, s.size.y * 0.3, s.z); rotateY(s.turn); drawMesh(pebble) }
        }

        // Three leaves drift across on the breeze, over sand and stone alike.
        if let leaf {
            for (i, lane) in [0.35, 2.4, -2.2].enumerated() {
                let along = (time * 0.03 + 0.37 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
                drawDecal(leaf, at: Vector3(-6 + 12 * along, 0.5, lane), width: 0.42, depth: 3,
                          roll: time * 0.2 + Double(i) * 2)
            }
        }
    }
}
