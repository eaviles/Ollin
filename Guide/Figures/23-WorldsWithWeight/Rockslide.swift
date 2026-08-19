// figure: frame=210
//
// Guide listing (Chapter 23): the heightfield collider. The grown-and-eroded
// terrain from "A landscape you grow" becomes solid ground through
// .heightfield, and a staged slide of rocks tumbles down its ravines. Fixed
// seed, staged drops, no random anywhere, so the moment replays identically.
import Ollin
import OllinPhysics

final class Rockslide: Sketch {
    let world = World3D()
    var land = Heightfield(columns: 2, rows: 2)
    var terrain = Mesh(positions: [], indices: [])

    let landWidth = 14.0, landDepth = 14.0, landHeight = 4.2
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0xD94F70),
        Color(hex: 0x8D92E0), Color(hex: 0x72BFB2),
    ]

    override func setup() {
        let bumps = Heightfield.diamondSquare(size: 129, roughness: 0.55, seed: 12)
        land = Heightfield(columns: 129, rows: 129) { u, v in
            0.7 * pow(1 - u, 1.6) + 0.3 * bumps.value(atU: u, v: v)
        }
        .eroded(.hydraulic(drops: 40_000), seed: 12)
        .eroded(.thermal(talus: 0.012, iterations: 30))
        .normalized()
        terrain = terrainMesh(land)

        world.addBody(.heightfield(land, width: landWidth, depth: landDepth,
                                   height: landHeight),
                      at: .zero, kind: .static, friction: 0.55)

        // A staged slide: (shape, ridge spot v, extra drop height).
        let drops: [(Collider3D, Double, Double)] = [
            (.sphere(radius: 0.24), 0.22, 0.0), (.cone(height: 0.44, radius: 0.26), 0.3, 0.5),
            (.box(width: 0.42, height: 0.3, depth: 0.38), 0.38, 1.0),
            (.sphere(radius: 0.19), 0.46, 1.5), (.cone(height: 0.38, radius: 0.22), 0.54, 2.0),
            (.sphere(radius: 0.27), 0.62, 2.5),
            (.box(width: 0.36, height: 0.26, depth: 0.44), 0.7, 3.0),
            (.sphere(radius: 0.22), 0.78, 3.5), (.cone(height: 0.48, radius: 0.28), 0.35, 4.0),
            (.sphere(radius: 0.25), 0.5, 4.5),
            (.box(width: 0.46, height: 0.34, depth: 0.4), 0.58, 5.0),
            (.sphere(radius: 0.2), 0.68, 5.5),
        ]
        for (index, drop) in drops.enumerated() {
            let u = 0.06
            let start = Vector3((u - 0.5) * landWidth,
                                land.value(atU: u, v: drop.1) * landHeight + 1.2 + drop.2,
                                (drop.1 - 0.5) * landDepth)
            let rock = world.addBody(drop.0, at: start,
                                     rotated: Double(index) * 0.7, axis: .unitY,
                                     density: 2, friction: 0.45, restitution: 0.2)
            rock.userData = palette[index % palette.count]
        }
    }

    override func draw() {
        background(Color(hex: 0x0A0D12))
        environment(.sky(turbidity: 4, sunElevation: 0.35).lightingOnly())
        lightingPreset(.goldenHour)
        castShadows()
        perspective(eye: Vector3(3.5, 4.6, 13), target: Vector3(-0.8, 1.9, 0))

        world.step(dt: deltaTime)

        material(.dielectric(roughness: 0.9))
        fill(.white)
        drawMesh(terrain)

        material(.dielectric(roughness: 0.6))
        for body in world.bodies {
            fill(body.userData as? Color ?? .white)
            withBody(body) {
                switch body.collider {
                case .sphere(let r): drawSphere(radius: r)
                case .box(let w, let h, let d): drawBox(width: w, height: h, depth: d)
                case .cone(let h, let r): drawCone(radius: r, height: h)
                default: break
                }
            }
        }
    }

    private func terrainMesh(_ field: Heightfield) -> Mesh {
        let ramp = Ramp([Color(hex: 0x27402C), Color(hex: 0x4A5A3C),
                         Color(hex: 0x77664F), Color(hex: 0x8C837A),
                         Color(hex: 0xD8DCE0)])
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.values.count * 4)
        for value in field.values {
            let c = ramp.color(at: min(max(value, 0), 1))
            pixels.append(UInt8((c.red * 255).rounded()))
            pixels.append(UInt8((c.green * 255).rounded()))
            pixels.append(UInt8((c.blue * 255).rounded()))
            pixels.append(255)
        }
        let texture = Image(width: field.columns, height: field.rows,
                            premultipliedRGBA: pixels)
        let mesh = field.mesh(width: landWidth, depth: landDepth, height: landHeight)
        guard let texture else { return mesh }
        return mesh.textured(texture)
    }
}
