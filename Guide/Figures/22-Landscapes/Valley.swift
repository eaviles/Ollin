// figure: frame=180 unstable
//
// Marked unstable for the reason the other culled field is: the cull pass
// compacts the surviving copies with atomics, so their draw order is the GPU's
// and moves between runs. The seed is pinned and the world is identical; what
// changes is which of two overlapping solids wins a tie, and it stays inside
// six counts of 255 over about 0.03% of the frame.
// Guide payoff (Chapter 22): Valley. Ridged noise weathered by rain and
// gravity, then read out three ways: as the lit mesh, as the sampler that
// finds somewhere flat to stand and decides where a pine can grow, and as the
// ground height every placement sits on. The far world is a culled field; the
// near stand is an instanced draw rebuilt each frame so the wind reaches it.
import Ollin

final class Valley: Sketch {
    let span = 110.0           // world units across the terrain
    let relief = 26.0          // world units from flood plain to ridge
    let floorLevel = 0.3       // heights under this flatten into flood plain

    var field = Heightfield(columns: 2, rows: 2)
    var land = Mesh(positions: [], indices: [])
    let world = MeshField()
    var meadow = StrandField(width: 44, depth: 44, count: 420_000)

    let pine = Mesh.cone(radius: 0.5, height: 3.2, segments: 9)
    let boulder = Mesh.icosphere(radius: 0.6, subdivisions: 1)

    var clearing = Vector2.zero          // where the camera stands, in x/z
    var ridge = Vector2.zero             // what it looks at
    let standReach = 42.0
    var nearSeats: [(x: Double, z: Double, ground: Double, phase: Double)] = []

    override func setup() {
        seed(2_608)
        noiseSeed(2_608)
        growTheLand()
        clearing = findAClearing()
        ridge = findARidge(from: clearing)
        dressTheLand()
        meadow.bladeHeight = 0.6
        meadow.heightVariance = 0.5
        meadow.bladeWidth = 0.035
        meadow.lean = 0.36
        meadow.swayAmount = 0.16
        meadow.swayFrequency = 1.7
        meadow.lowColor = Color(hue: 0.26, saturation: 0.55, brightness: 0.16)
        meadow.tipColor = Color(hue: 0.17, saturation: 0.62, brightness: 0.74)
        meadow.detailNear = 14
        meadow.detailFar = 48
    }

    // MARK: the land

    func growTheLand() {
        let grown = Heightfield(columns: 257, rows: 257) { u, v in
            ridgedFbm(u * 3.4, v * 3.4, octaves: 6)
        }
        .normalized()
        .eroded(.hydraulic(drops: 60_000), seed: 2_608)
        .eroded(.thermal(talus: 0.014, iterations: 30))
        .normalized()
        // Rain carries material downhill and leaves it in the low ground. Holding
        // the lowest third at one level is the flood plain that gets the meadow.
        field = Heightfield(columns: grown.columns, rows: grown.rows,
                            values: grown.values.map { max($0, floorLevel) })

        let ramp = Ramp([Color(hex: 0x54703C), Color(hex: 0x5F7340),
                         Color(hex: 0x8A8452), Color(hex: 0xA69378),
                         Color(hex: 0xB3AEA6), Color(hex: 0xEDEAE3)])
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.values.count * 4)
        for value in field.values {
            // The flood plain is the ramp's first color, the highest ridge its last.
            let t = (value - floorLevel) / (1 - floorLevel)
            let c = ramp.color(at: min(max(t, 0), 1))
            pixels.append(UInt8((c.red * 255).rounded()))
            pixels.append(UInt8((c.green * 255).rounded()))
            pixels.append(UInt8((c.blue * 255).rounded()))
            pixels.append(255)
        }
        let mesh = field.mesh(width: span, depth: span, height: relief)
        if let skin = Image(width: field.columns, height: field.rows,
                            premultipliedRGBA: pixels) {
            land = mesh.textured(skin)
        } else {
            land = mesh
        }
    }

    /// The ground height under a world x/z, in world units.
    func ground(atX x: Double, z: Double) -> Double {
        field.value(atU: x / span + 0.5, v: z / span + 0.5) * relief
    }

    /// How steeply the land climbs at a point, as rise over run.
    func steepness(atX x: Double, z: Double) -> Double {
        let step = span / 256
        let dx = ground(atX: x + step, z: z) - ground(atX: x - step, z: z)
        let dz = ground(atX: x, z: z + step) - ground(atX: x, z: z - step)
        return sqrt(dx * dx + dz * dz) / (step * 2)
    }

    // MARK: reading the land back

    /// Somewhere flat to stand, found by asking the field instead of guessing.
    func findAClearing() -> Vector2 {
        let floorY = floorLevel * relief
        var best = Vector2.zero, bestScore = -1.0
        for gz in stride(from: -30.0, through: 30.0, by: 3.0) {
            for gx in stride(from: -30.0, through: 30.0, by: 3.0) {
                var flat = 0.0
                for k in 0 ..< 60 {
                    let a = Double(k) / 60 * .tau * 7
                    let r = Double(k) / 60 * 30
                    if ground(atX: gx + cos(a) * r, z: gz + sin(a) * r) < floorY + 0.15 {
                        flat += 1
                    }
                }
                if flat > bestScore { bestScore = flat; best = Vector2(gx, gz) }
            }
        }
        return best
    }

    /// The highest ground in the middle distance, away from the sun, which is what
    /// the shot faces. The sky's sun rises toward +z, so looking the other way puts
    /// it behind the camera and lights the land instead of silhouetting it.
    func findARidge(from here: Vector2) -> Vector2 {
        var best = Vector2.zero, bestHeight = -1.0
        for a in stride(from: .pi * 0.6, to: .pi * 1.4, by: .tau / 180) {
            for r in stride(from: 52.0, through: 80.0, by: 2.0) {
                let p = Vector2(here.x + cos(a) * r, here.y + sin(a) * r)
                if abs(p.x) > span / 2 - 4 || abs(p.y) > span / 2 - 4 { continue }
                let h = ground(atX: p.x, z: p.y)
                if h > bestHeight { bestHeight = h; best = p }
            }
        }
        return best
    }

    // MARK: what stands on it

    func dressTheLand() {
        let floorY = floorLevel * relief
        var pines: [MeshInstance] = []
        var stones: [MeshInstance] = []
        let pineDark = Color(hue: 0.36, saturation: 0.6, brightness: 0.26)
        let pineLight = Color(hue: 0.26, saturation: 0.5, brightness: 0.5)
        let stoneGray = Color(hue: 0.09, saturation: 0.12, brightness: 0.55)
        let half = span / 2 - 1

        for _ in 0 ..< 400_000 {
            let x = random(-half, half), z = random(-half, half)
            let y = ground(atX: x, z: z)
            let slope = steepness(atX: x, z: z)
            // Nothing grows on the flood plain, and nothing grows on bare rock.
            if y < floorY + 0.5 { continue }
            if Vector2(x, z).distance(to: clearing) < standReach { continue }
            if slope < 0.8 && y < relief * 0.66 {
                let s = random(0.7, 1.5)
                pines.append(MeshInstance(position: Vector3(x, y + 1.6 * s, z),
                                          rotation: Vector3(0, random(.tau), 0),
                                          scale: Vector3(s, s * random(0.85, 1.5), s),
                                          color: Color.mix(pineDark, pineLight, t: random(1))))
            } else if slope > 1.0 && random(1) < 0.4 {
                let s = random(0.4, 1.4)
                stones.append(MeshInstance(position: Vector3(x, y + 0.25 * s, z),
                                           rotation: Vector3(random(.tau), random(.tau), random(.tau)),
                                           scale: Vector3(s, s * 0.7, s),
                                           color: Color.mix(stoneGray, Color(white: 0.68), t: random(1))))
            }
        }
        world.place(pine, at: pines)
        world.place(boulder, at: stones)

        // The stand around the camera, kept on the CPU so the wind can move it.
        for _ in 0 ..< 40_000 {
            let a = random(.tau), r = sqrt(random(1)) * standReach
            let x = clearing.x + cos(a) * r, z = clearing.y + sin(a) * r
            let y = ground(atX: x, z: z)
            if y < floorY + 0.5 || y > relief * 0.66 { continue }
            if steepness(atX: x, z: z) > 0.8 { continue }
            nearSeats.append((x, z, y, random(.tau)))
        }
    }

    // MARK: the frame

    override func draw() {
        background(Color(hex: 0x2A2320))
        environment(.sky(turbidity: 2.6, sunElevation: 0.16))
        let eye = Vector3(clearing.x, ground(atX: clearing.x, z: clearing.y) + 2.4, clearing.y)
        let look = Vector3(ridge.x, ground(atX: ridge.x, z: ridge.y) * 0.72, ridge.y)
        camera(Camera3D(eye: eye, target: look, far: 190,
                        projection: .perspective(fieldOfView: .pi / 3.6)))
        lightingPreset(.goldenHour)
        castShadows()
        aerialPerspective(haziness: 0.12)

        specular(0.04)
        drawMesh(land)

        withState {
            translate(clearing.x, ground(atX: clearing.x, z: clearing.y), clearing.y)
            drawStrands(meadow)
        }

        specular(0.08)
        shininess(18)
        drawMeshField(world)

        // The near stand, rebuilt every frame: the wind lives in the placements.
        let pineDark = Color(hue: 0.36, saturation: 0.6, brightness: 0.26)
        let pineLight = Color(hue: 0.26, saturation: 0.5, brightness: 0.5)
        var stand: [MeshInstance] = []
        stand.reserveCapacity(nearSeats.count)
        for seat in nearSeats {
            let gust = sin(time * 0.9 + seat.phase + seat.x * 0.06) * 0.04
            let s = 0.8 + (sin(seat.phase * 3) * 0.5 + 0.5) * 0.8
            stand.append(MeshInstance(position: Vector3(seat.x, seat.ground + 1.6 * s, seat.z),
                                      rotation: Vector3(gust, seat.phase, gust * 0.6),
                                      scale: Vector3(s, s * 1.2, s),
                                      color: Color.mix(pineDark, pineLight,
                                                       t: sin(seat.phase * 5) * 0.5 + 0.5)))
        }
        drawMesh(pine, instances: stand)
    }
}
