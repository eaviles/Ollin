import Ollin
import OllinPhysics

/// A machine on tracks, working a quarry it could not drive out of on wheels.
/// Arrows or WASD to drive, space to brake, R to be put back on the floor.
///
/// The three controls are the ones any vehicle here takes, and two of them mean
/// exactly what they always did. Steering is the one that changes: a track has
/// nothing to turn, so the number runs one band slower than the other, and at
/// full lock the inside band runs backwards and the machine spins where it
/// stands. Hold the throttle and push the stick over on the flat to feel it.
/// The bank at the far end is the other half of the bargain: a band lays its
/// whole length on the ground and keeps gripping while it slides, so the
/// crawler walks up a slope that would leave a car turning its wheels.
@main
final class Crawler: Sketch {
    let world = World3D()
    var land = Heightfield(columns: 2, rows: 2)
    var terrain = Mesh(positions: [], indices: [])
    var crawler: Vehicle3D!
    var rubble: [Body3D] = []

    /// The knobs worth turning while driving. Wind `topSpeed` down and the
    /// machine pulls harder and crawls, which is what a working one does.
    @Param(3 ... 18, icon: "speedometer") var topSpeed = 9.0
    @Param(0.05 ... 1.5, icon: "road.lanes") var grip = 1.0
    @Param(1.0 ... 4.0, icon: "car.side.rear.tilted") var springs = 2.0

    /// How far each band has run, in units: what the drawn links are laid out
    /// from, so the track scrolls with the machine rather than with the clock.
    var bandPhase: [Double] = [0, 0]

    /// The chase camera's eye, eased so a drop off a ledge does not jolt it.
    var eye = Vector3(0, 8, -14)
    var start = Vector3(0, 0, 0)

    let landWidth = 48.0, landDepth = 48.0, landHeight = 16.0
    /// Where the working floor sits in the field, and in world units.
    let floorLevel = 0.1
    var floorY = 0.0

    // The machine's own dimensions, shared by the collider and the drawing.
    let hull = Vector3(2.0, 0.9, 5.2)
    let wheelRadius = 0.44, wheelWidth = 0.6, trackX = 1.3

    let palette: [Color] = [
        Color(hex: 0xE8A33D), Color(hex: 0xD9663B), Color(hex: 0x8C8A85),
        Color(hex: 0x5F7A6B),
    ]

    override func setup() {
        buildQuarry()
        start = Vector3(0, floorY + 1.6, -9)
        crawler = buildCrawler(at: start)
        eye = start + Vector3(0, 6, -14)
    }

    /// A dead flat working floor with a steep weathered bank at the far end
    /// climbing to a bench. The bank is eroded so it has gullies rather than
    /// one clean face; the floor is held flat afterwards, because a pivot on
    /// the spot only reads as one if there is no slope to roll down.
    func buildQuarry() {
        let bumps = Heightfield.diamondSquare(size: 129, roughness: 0.5, seed: 7)
        let weathered = Heightfield(columns: 129, rows: 129) { u, v in
            // Two cut faces with a bench between them: the shape a quarry is
            // worked into, and two climbs of different steepness to try.
            let lower = smoothstep(0.46, 0.58, v) * 0.2
            let upper = smoothstep(0.66, 0.78, v) * 0.26
            let rim = 1 - smoothstep(0.86, 1.0, Vector2(u - 0.5, v - 0.5).length * 2)
            let rough = (bumps.value(atU: u, v: v) - 0.5) * (0.04 + (lower + upper))
            return max(0, (floorLevel + lower + upper + rough) * rim)
        }
        .eroded(.hydraulic(drops: 30_000), seed: 7)
        .eroded(.thermal(talus: 0.03, iterations: 16))
        land = Heightfield(columns: 129, rows: 129) { u, v in
            lerp(floorLevel, weathered.value(atU: u, v: v),
                 smoothstep(0.4, 0.56, v))
        }
        floorY = floorLevel * landHeight
        terrain = terrainMesh(land)
        world.addBody(.heightfield(land, width: landWidth, depth: landDepth,
                                   height: landHeight),
                      at: .zero, kind: .static, friction: 0.9)

        // Spoil fallen off the bank, and a stack of crates to shove about.
        for i in 0 ..< 7 {
            let across = Double(i) * 2.4 - 7.2 + (i % 2 == 0 ? -3 : 3)
            let along = -2.0 + Double(i % 3) * 2.0
            let rock = world.addBody(.sphere(radius: 0.5 + Double(i % 3) * 0.15),
                                     at: Vector3(across, floorY + 1.2, along),
                                     density: 0.4, friction: 0.8)
            rock.userData = palette[(i + 2) % palette.count]
            rubble.append(rock)
        }
        for level in 0 ..< 3 {
            for column in 0 ... (2 - level) {
                let x = Double(column) * 1.05 - Double(2 - level) * 0.52
                let crate = world.addBody(
                    .box(width: 1, height: 1, depth: 1),
                    at: Vector3(x + 8, floorY + 0.55 + Double(level) * 1.05, -6),
                    density: 0.09, friction: 0.6)
                crate.userData = palette[(level + column) % palette.count]
                rubble.append(crate)
            }
        }
    }

    /// The machine: a hull on ten road wheels, five to a band. Which side of
    /// the hull a wheel sits on is what puts it on a band, so there is no list
    /// to keep in order; the rearmost of each five is the sprocket the engine
    /// turns.
    func buildCrawler(at position: Vector3) -> Vehicle3D {
        var wheels: [Wheel3D] = []
        for side in [trackX, -trackX] {
            for i in 0 ..< 5 {
                let wheel = Wheel3D.wheel(at: Vector3(side, -0.28, -1.8 + Double(i) * 0.9),
                                          radius: wheelRadius, width: wheelWidth)
                wheel.suspensionLength = 0.4
                wheel.suspensionTravel = 0.28
                wheel.suspensionFrequency = springs
                wheels.append(wheel)
            }
        }
        let built = world.addVehicle(.box(width: hull.x, height: hull.y, depth: hull.z),
                                     at: position, wheels: wheels, mass: 4200,
                                     engineTorque: 520, topSpeed: topSpeed,
                                     friction: 0.9, tracked: true)!
        // A quarry has slopes an unlimited hull would happily lie down on.
        built.maxTilt = .pi / 3
        return built
    }

    override func draw() {
        background(Color(hex: 0x0B1017))
        environment(.sky(turbidity: 2.2, sunElevation: 0.55).rotated(2.4))
        lightingPreset(.standard)
        castShadows()

        operate()
        world.step(dt: deltaTime)
        for (index, side) in [Vehicle3D.TrackSide.left, .right].enumerated() {
            bandPhase[index] += crawler.trackSpeed(side) * deltaTime
        }
        if crawler.body.position.y < floorY - 8 { reset() }

        followWithCamera()

        material(.dielectric(roughness: 0.9))
        fill(.white)
        drawMesh(terrain)
        drawRubble()
        drawCrawler()

        let left = crawler.trackSpeed(.left), right = crawler.trackSpeed(.right)
        drawCaption(String(format: "tracks %+.1f / %+.1f      gear %d      ",
                           left, right, crawler.gear)
                    + "arrows or WASD to drive, hold both to spin on the spot, "
                    + "space to brake, R to reset")
    }

    /// The whole of the input. Steering is the interesting one: it is not an
    /// angle here, it is how much slower the inside band runs.
    func operate() {
        crawler.topSpeed = topSpeed
        for wheel in crawler.wheels {
            wheel.suspensionFrequency = springs
            wheel.grip = grip
        }

        var throttle = 0.0
        if isKeyDown(.upArrow) || isKeyDown("w") { throttle += 1 }
        if isKeyDown(.downArrow) || isKeyDown("s") { throttle -= 1 }
        var steering = 0.0
        if isKeyDown(.leftArrow) || isKeyDown("a") { steering -= 1 }
        if isKeyDown(.rightArrow) || isKeyDown("d") { steering += 1 }
        // A machine that steers through its drivetrain needs the engine
        // turning to turn at all, so a pivot is throttle *and* stick.
        if steering != 0, throttle == 0 { throttle = 1 }

        crawler.throttle = throttle
        crawler.steering = steering
        crawler.brake = isKeyDown(" ") ? 1 : 0
        if isKeyDown("r") { reset() }
    }

    func reset() {
        crawler.body.position = start
        crawler.body.setRotation(0, axis: .unitY)
        crawler.body.velocity = .zero
        crawler.body.angularVelocity = .zero
        crawler.coast()
    }

    func followWithCamera() {
        let focus = crawler.body.position + Vector3(0, 1.2, 0)
        let wanted = focus + crawler.forward * -12 + Vector3(0, 8.5, 0)
        eye += (wanted - eye) * min(1, deltaTime * 2.5)
        camera(.perspective(eye: eye, target: focus + crawler.forward * 4,
                            fieldOfView: .pi / 3.4))
    }

    /// The hull, the road wheels where the suspension actually put them, and a
    /// band of links laid around each five.
    func drawCrawler() {
        material(.dielectric(roughness: 0.35))
        fill(Color(hex: 0xE8A33D))
        withBody(crawler.body) {
            drawBox(width: hull.x, height: hull.y, depth: hull.z)
            fill(Color(hex: 0x2A3038))
            withState {
                translate(0, 0.7, -0.4)
                drawBox(width: 1.9, height: 0.7, depth: 2.2)
            }
            // A stripe over the nose so the facing reads while it spins.
            fill(Color(hex: 0x1C2229))
            withState {
                translate(0, 0.52, 1.9)
                drawBox(width: 1.2, height: 0.06, depth: 1.0)
            }
        }

        material(.dielectric(roughness: 0.6))
        for wheel in crawler.wheels {
            fill(Color(hex: 0x3A424C))
            withWheel(wheel) {
                drawCylinder(radius: wheel.radius, height: wheel.width * 0.75)
                fill(Color(hex: 0xB9AE9C))
                drawCylinder(radius: wheel.radius * 0.4, height: wheel.width * 0.8)
            }
        }

        material(.dielectric(roughness: 0.75))
        fill(Color(hex: 0x232A32))
        for (index, side) in [Vehicle3D.TrackSide.left, .right].enumerated() {
            drawBand(on: side, phase: bandPhase[index])
        }
    }

    /// A closed run of links around one band's road wheels: over the top of
    /// them, round the rear, back along the ground, round the nose. The links
    /// are laid at a fixed spacing and slid along by how far the band has run,
    /// so the track crawls under the machine at the speed the solver says.
    func drawBand(on side: Vehicle3D.TrackSide, phase: Double) {
        let wheels = crawler.wheels(on: side)
        guard wheels.count >= 2 else { return }
        let up = crawler.up, forward = crawler.forward
        let radius = wheelRadius + 0.06

        // The path: the tops of the wheels front to back, an end cap round the
        // rear, the undersides back to front, an end cap round the nose.
        var path: [Vector3] = []
        for wheel in wheels { path.append(wheel.center + up * radius) }
        path += arc(around: wheels[wheels.count - 1].center, from: up,
                    toward: forward * -1, radius: radius)
        for wheel in wheels.reversed() { path.append(wheel.center - up * radius) }
        path += arc(around: wheels[0].center, from: up * -1, toward: forward,
                    radius: radius)

        // Walk it at a fixed pitch, sliding the whole run by how far the band
        // has traveled so the links move rather than the wheels alone.
        let pitch = 0.34
        var lengths: [Double] = [0]
        for i in 1 ... path.count {
            lengths.append(lengths[i - 1] + (path[i % path.count] - path[i - 1]).length)
        }
        let total = lengths[path.count]
        guard total > pitch else { return }
        let links = Int(total / pitch)
        var segment = 0
        for k in 0 ..< links {
            let along = (Double(k) * pitch + phase).truncatingRemainder(dividingBy: total)
            let at = along < 0 ? along + total : along
            while segment < path.count - 1, lengths[segment + 1] < at { segment += 1 }
            while segment > 0, lengths[segment] > at { segment -= 1 }
            let span = max(1e-6, lengths[segment + 1] - lengths[segment])
            let t = (at - lengths[segment]) / span
            let from = path[segment], to = path[(segment + 1) % path.count]
            withState {
                translate(from + (to - from) * t)
                let heading = (to - from).normalized
                rotate(atan2(heading.x, heading.z), axis: .unitY)
                rotate(-asin(max(-1, min(1, heading.y))), axis: .unitX)
                drawBox(width: wheelWidth, height: 0.1, depth: pitch * 0.82)
            }
        }
    }

    /// Points along a half turn from `from` to the far side, swinging through
    /// `toward`: the cap that wraps one end wheel.
    func arc(around center: Vector3, from: Vector3, toward: Vector3,
             radius: Double) -> [Vector3] {
        (1 ... 5).map { step in
            let angle = Double(step) * .pi / 6
            return center + (from * cos(angle) + toward * sin(angle)) * radius
        }
    }

    func drawRubble() {
        material(.dielectric(roughness: 0.7))
        for body in rubble {
            fill(body.userData as? Color ?? .white)
            withBody(body) {
                switch body.collider {
                case .sphere(let r): drawIcosphere(radius: r, subdivisions: 2)
                default: drawBox(width: 1, height: 1, depth: 1)
                }
            }
        }
    }

    /// The field as a mesh wearing a height-colored texture: quarry floor,
    /// spoil, and the weathered rock of the bank.
    private func terrainMesh(_ field: Heightfield) -> Mesh {
        let ramp = Ramp([Color(hex: 0x9E8C6E), Color(hex: 0xB29C78),
                         Color(hex: 0x8E7A5E), Color(hex: 0xA89272),
                         Color(hex: 0xD8CBAE)])
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.values.count * 4)
        for value in field.values {
            let c = ramp.color(at: clamp(value, 0, 1))
            pixels.append(UInt8((c.red * 255).rounded()))
            pixels.append(UInt8((c.green * 255).rounded()))
            pixels.append(UInt8((c.blue * 255).rounded()))
            pixels.append(255)
        }
        let mesh = field.mesh(width: landWidth, depth: landDepth, height: landHeight)
        guard let texture = Image(width: field.columns, height: field.rows,
                                  premultipliedRGBA: pixels) else { return mesh }
        return mesh.textured(texture)
    }
}
