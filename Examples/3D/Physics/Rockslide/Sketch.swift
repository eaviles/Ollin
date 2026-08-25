import Ollin
import OllinPhysics

/// A rockslide on generated ground: a diamond-square `Heightfield` grows a
/// mountainside, hydraulic rain carves its ravines, and the same field then
/// becomes solid terrain through the `.heightfield` collider, so every bounce
/// lands on exactly the surface the mesh draws. A steady feed of rocks
/// (spheres, slabs, cones) drops onto the ridge, tumbles down the gullies,
/// and piles into scree at the foot; rocks that ride off the edge fall into
/// the void and return to the top. The dice knob regrows the whole slope.
@main
final class Rockslide: Sketch {
    let world = World3D()
    var land = Heightfield(columns: 2, rows: 2)
    var terrain = Mesh(positions: [], indices: [])
    var rocks: [Body3D] = []
    var restFrames: [Int] = []

    @Param(1 ... 99, icon: "dice") var terrainSeed = 12.0
    private var builtSeed = 0.0

    let landWidth = 14.0, landDepth = 14.0, landHeight = 4.2
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0xD94F70),
        Color(hex: 0x8D92E0), Color(hex: 0x72BFB2),
    ]

    override func setup() {
        rebuild()
    }

    /// Grow, weather, and mount the mountainside: a ridge along the west edge
    /// falling toward the east with fractal detail, eroded so ravines funnel
    /// the rocks, then handed whole to the collider.
    func rebuild() {
        builtSeed = terrainSeed.rounded()
        let seed = UInt64(builtSeed)

        let bumps = Heightfield.diamondSquare(size: 129, roughness: 0.55, seed: seed)
        land = Heightfield(columns: 129, rows: 129) { u, v in
            // Steep near the ridge, easing into the flats where scree piles.
            0.7 * pow(1 - u, 1.6) + 0.3 * bumps.value(atU: u, v: v)
        }
        .eroded(.hydraulic(drops: 40_000), seed: seed)
        .eroded(.thermal(talus: 0.012, iterations: 30))
        .normalized()
        terrain = terrainMesh(land)

        world.removeAll()
        world.addBody(.heightfield(land, width: landWidth, depth: landDepth,
                                   height: landHeight),
                      at: .zero, kind: .static, friction: 0.55)
        rocks.removeAll()
        restFrames.removeAll()
        for index in 0 ..< 16 { dropRock(stagger: index) }
    }

    /// A rock onto the ridge: a sphere, a slab, or a cone, staggered so the
    /// feed arrives as a slide rather than one clump.
    func dropRock(stagger: Int = 0) {
        let collider: Collider3D
        switch Int(random(0, 3)) {
        case 0: collider = .sphere(radius: random(0.16, 0.28))
        case 1: collider = .box(width: random(0.3, 0.5), height: random(0.22, 0.38),
                                depth: random(0.3, 0.5))
        default: collider = .cone(height: random(0.34, 0.5), radius: random(0.2, 0.3))
        }
        let u = random(0.03, 0.1), v = random(0.15, 0.85)
        let start = Vector3((u - 0.5) * landWidth,
                            land.value(atU: u, v: v) * landHeight + 1.2
                                + Double(stagger) * 0.55,
                            (v - 0.5) * landDepth)
        let rock = world.addBody(collider, at: start,
                                 rotated: random(0, .tau), axis: .unitY,
                                 density: 2, friction: 0.45, restitution: 0.2)
        rock.userData = palette[Int(random(0, Double(palette.count)))
                                % palette.count]
        rocks.append(rock)
        restFrames.append(0)
    }

    /// Back to the ridge after falling off the world's edge, or after resting
    /// in the scree long enough for the slide to stay alive.
    func recycle(_ index: Int) {
        let rock = rocks[index]
        world.remove(rock)
        rocks.remove(at: index)
        restFrames.remove(at: index)
        dropRock()
    }

    override func draw() {
        if terrainSeed.rounded() != builtSeed { rebuild() }

        background(Color(hex: 0x0A0D12))
        environment(.sky(turbidity: 3, sunElevation: 0.5).lightingOnly())
        lightingPreset(.goldenHour)
        castShadows()
        cameraShowcase(.turntable(period: .tau / 0.08), radius: 17,
                       elevation: 0.38, fieldOfView: .pi / 4)

        world.step(dt: deltaTime)
        for index in (0 ..< rocks.count).reversed() {
            restFrames[index] = rocks[index].velocity.length < 0.05
                ? restFrames[index] + 1 : 0
            if rocks[index].position.y < -3 || restFrames[index] > 420 {
                recycle(index)
            }
        }

        material(.dielectric(roughness: 0.9))
        fill(.white)
        drawMesh(terrain)

        material(.dielectric(roughness: 0.6))
        for rock in rocks {
            fill(rock.userData as? Color ?? .white)
            withBody(rock) {
                switch rock.collider {
                case .sphere(let r): drawSphere(radius: r)
                case .box(let w, let h, let d): drawBox(width: w, height: h, depth: d)
                case .cone(let h, let r): drawCone(radius: r, height: h)
                default: break
                }
            }
        }
    }

    /// The field as a mesh wearing a height-colored texture: scrub at the
    /// foot, bare rock up the slope, snow on the ridge.
    private func terrainMesh(_ field: Heightfield) -> Mesh {
        let ramp = Ramp([Color(hex: 0x27402C), Color(hex: 0x4A5A3C),
                         Color(hex: 0x77664F), Color(hex: 0x8C837A),
                         Color(hex: 0xD8DCE0)])
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.values.count * 4)
        for value in field.values {
            let c = ramp.color(at: clamp(value, 0, 1))
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
