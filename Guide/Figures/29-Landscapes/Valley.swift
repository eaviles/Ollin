// figure: frame=180 unstable
//
// Marked unstable for the reason the other culled field is: the cull pass
// compacts the surviving copies with atomics, so their draw order is the GPU's
// and moves between runs. The seed is pinned and the world is identical; what
// changes is which of two overlapping solids wins a tie, and it stays inside
// six counts of 255 over about 0.03% of the frame.
// Guide payoff (Chapter 29): Valley. Ridged noise weathered by rain and
// gravity, then read out four ways: as the lit mesh, which is also the
// surface the far world is scattered over by area, as the drainage that says
// where the river runs, as the sampler that finds a bank to stand on, and as
// the ground height the near stand sits on. The river is a water surface held
// just under the flood plain, so it shows wherever the channel cut along the
// drainage dips below it. The far world is a culled field; the near stand is
// an instanced draw rebuilt each frame so the wind reaches it.
import Ollin

final class Valley: Sketch {
    let span = 110.0           // world units across the terrain
    let relief = 26.0          // world units from flood plain to ridge
    let floorLevel = 0.3       // heights under this flatten into flood plain
    let channelDepth = 0.03    // how far the river bed cuts under the ground, in field units
    let channelRadius = 8      // half the channel's width, in cells
    var riverLevel: Double { floorLevel - 0.006 }   // where the water stands: just under the plain

    var field = Heightfield(columns: 2, rows: 2)
    var land = Mesh(positions: [], indices: [])
    var river: [River] = []
    let world = MeshField()
    var meadow = StrandField(width: 44, depth: 30, count: 300_000)

    let pine = Mesh.cone(radius: 0.5, height: 3.2, segments: 9)
    let boulder = Mesh.icosphere(radius: 0.6, subdivisions: 1)

    var clearing = Vector2.zero          // where the camera stands, in x/z
    var ridge = Vector2.zero             // what it looks at
    var meadowCenter = Vector2.zero      // the grass, laid along the river's bank
    var meadowTurn = 0.0                 // turned to run with the river
    let standReach = 42.0
    var nearSeats: [(x: Double, z: Double, ground: Double, phase: Double)] = []

    override func setup() {
        seed(2_608)
        noiseSeed(2_608)
        growTheLand()
        clearing = findAClearing()
        ridge = findARidge(from: clearing)
        layTheMeadow()
        dressTheLand()
        meadow.bladeHeight = 0.6
        meadow.heightVariance = 0.5
        meadow.bladeWidth = 0.035
        meadow.lean = 0.36
        meadow.swayAmplitude = 0.16
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

        // Where the water runs, read off the ground before the plain is leveled,
        // since level ground has no downhill. Only a reach that drains 3,000
        // cells or more counts as the river; the rest stay the creases they are.
        let bounds = Rectangle(x: -span / 2, y: -span / 2, width: span, height: span)
        river = grown.drainage().rivers(minFlow: 3_000, in: bounds)

        // Rain carries material downhill and leaves it in the low ground. Holding
        // every height under 0.3 at one level is the flood plain that gets the meadow.
        var heights = grown.values.map { max($0, floorLevel) }
        carveTheRiver(into: &heights, columns: grown.columns, rows: grown.rows)
        field = Heightfield(columns: grown.columns, rows: grown.rows, values: heights)

        let ramp = Ramp([Color(hex: 0x54703C), Color(hex: 0x5F7340),
                         Color(hex: 0x8A8452), Color(hex: 0xA69378),
                         Color(hex: 0xB3AEA6), Color(hex: 0xEDEAE3)])
        // The flood plain is the ramp's first color, the highest ridge its last.
        land = field.coloredMesh(width: span, depth: span, height: relief,
                                 ramp, in: floorLevel...1)
    }

    /// A rounded channel cut under every river point, below whatever ground it
    /// crosses. On the plain that puts the bed under the water level.
    func carveTheRiver(into heights: inout [Double], columns: Int, rows: Int) {
        let ground = heights
        for reach in river {
            for p in reach.points {
                let cx = Int(((p.x / span + 0.5) * Double(columns - 1)).rounded())
                let cy = Int(((p.y / span + 0.5) * Double(rows - 1)).rounded())
                for y in max(0, cy - channelRadius) ... min(rows - 1, cy + channelRadius) {
                    for x in max(0, cx - channelRadius) ... min(columns - 1, cx + channelRadius) {
                        let dx = Double(x - cx), dy = Double(y - cy)
                        let d = (dx * dx + dy * dy).squareRoot() / Double(channelRadius)
                        if d >= 1 { continue }
                        let i = y * columns + x
                        heights[i] = min(heights[i], ground[i] - channelDepth * (1 - d * d))
                    }
                }
            }
        }
    }

    /// The ground height under a world x/z, in world units.
    func ground(atX x: Double, z: Double) -> Double {
        field.value(u: x / span + 0.5, v: z / span + 0.5) * relief
    }

    /// How steeply the land climbs at a point, as rise over run.
    func steepness(atX x: Double, z: Double) -> Double {
        let step = span / 256
        let dx = ground(atX: x + step, z: z) - ground(atX: x - step, z: z)
        let dz = ground(atX: x, z: z + step) - ground(atX: x, z: z - step)
        return sqrt(dx * dx + dz * dz) / (step * 2)
    }

    /// How far a world x/z is from the river, and the river's own direction there.
    func riverside(of point: Vector2) -> (distance: Double, along: Vector2, bank: Vector2) {
        var best = (distance: Double.infinity, reach: 0, index: 0)
        for (r, reach) in river.enumerated() {
            for (i, p) in reach.points.enumerated() where p.distance(to: point) < best.distance {
                best = (p.distance(to: point), r, i)
            }
        }
        guard best.distance.isFinite else { return (best.distance, Vector2(1, 0), Vector2(0, 1)) }
        let points = river[best.reach].points
        let a = points[max(0, best.index - 12)], b = points[min(points.count - 1, best.index + 12)]
        let along = (b - a).normalized
        var bank = Vector2(-along.y, along.x)      // across the river, toward the point
        if bank.dot(point - points[best.index]) < 0 { bank = -bank }
        return (best.distance, along, bank)
    }

    // MARK: reading the land back

    /// Somewhere flat to stand on the river's bank, found by asking the field
    /// instead of guessing: level ground all around, and the water seven to
    /// eleven units off.
    func findAClearing() -> Vector2 {
        let floorY = floorLevel * relief
        var best = Vector2.zero, bestScore = -1.0
        for gz in stride(from: -30.0, through: 30.0, by: 3.0) {
            for gx in stride(from: -30.0, through: 30.0, by: 3.0) {
                let offRiver = riverside(of: Vector2(gx, gz)).distance
                if offRiver < 7 || offRiver > 11 { continue }
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
    /// the shot faces. The golden-hour key light shines from +x, so looking toward -x
    /// puts it behind the camera and lights the land instead of silhouetting it.
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

    /// The grass is a square patch, so it is turned to run with the river and
    /// pushed onto the clearing's side of it, its near edge a few units up the
    /// bank. The camera stands inside it, near that edge.
    func layTheMeadow() {
        let side = riverside(of: clearing)
        guard side.distance.isFinite else { meadowCenter = clearing; return }
        let riverPoint = clearing - side.bank * side.distance
        meadowCenter = riverPoint + side.bank * (5.5 + meadow.depth / 2)
        meadowTurn = -atan2(side.along.y, side.along.x)
    }

    // MARK: what stands on it

    func dressTheLand() {
        let floorY = floorLevel * relief
        var pines: [MeshInstance] = []
        var stones: [MeshInstance] = []
        let pineDark = Color(hue: 0.36, saturation: 0.6, brightness: 0.26)
        let pineLight = Color(hue: 0.26, saturation: 0.5, brightness: 0.5)
        let stoneGray = Color(hue: 0.09, saturation: 0.12, brightness: 0.55)

        // Spots spread by area over the land's own surface, then kept or passed
        // over by what the ground does there. A spot's normal says how steep it is.
        // At this density the pines overlap anyway, so the cheap random scatter
        // serves, where blue noise would take far longer.
        for spot in surfacePoints(on: land, count: 400_000, scatter: .random) {
            let p = spot.position
            // Nothing grows on the flood plain or in the river, and nothing grows on bare rock.
            if p.y < floorY + 0.5 { continue }
            if Vector2(p.x, p.z).distance(to: clearing) < standReach { continue }
            if spot.normal.y > 0.78 && p.y < relief * 0.66 {
                let s = random(0.7, 1.5)
                pines.append(MeshInstance(position: Vector3(p.x, p.y + 1.6 * s, p.z),
                                          rotation: Vector3(0, random(.tau), 0),
                                          scale: Vector3(s, s * random(0.85, 1.5), s),
                                          color: Color.mix(pineDark, pineLight, random(1))))
            } else if spot.normal.y < 0.71 && random(1) < 0.4 {
                let s = random(0.4, 1.4)
                stones.append(MeshInstance(position: Vector3(p.x, p.y + 0.25 * s, p.z),
                                           rotation: Vector3(random(.tau), random(.tau), random(.tau)),
                                           scale: Vector3(s, s * 0.7, s),
                                           color: Color.mix(stoneGray, Color(white: 0.68), random(1))))
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

        // The river is a sea at the valley's scale: a barely stirred surface held
        // just under the flood plain, so it shows only where the channel dips below it.
        let stream = makeOceanField(Ocean(waveHeight: 0.06, windSpeed: 1.5, choppiness: 0.4,
                                          patchSize: span, smallestWave: 0.15, seed: 2_608),
                                    resolution: 512)
        withState {
            translate(0, riverLevel * relief, 0)
            drawOcean(stream, segments: 512, water: .open)
        }

        withState {
            translate(meadowCenter.x, floorLevel * relief, meadowCenter.y)
            rotateY(meadowTurn)
            drawStrands(meadow)
        }

        specular(0.08)
        specularSharpness(18)
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
                                                       sin(seat.phase * 5) * 0.5 + 0.5)))
        }
        drawMesh(pine, instances: stand)
    }
}
