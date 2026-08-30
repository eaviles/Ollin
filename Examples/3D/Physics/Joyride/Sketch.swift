import Ollin
import OllinPhysics

/// A car you drive over an eroded island. The same `Heightfield` is the ground
/// you see and the ground the tires find, and a `Vehicle3D` rides it: arrows or
/// WASD to drive, space for the hand brake, R to be put back on the road.
///
/// A vehicle is not a body you push, it is a machine you operate, and the
/// sketch's whole job is the four numbers under `steer()`. Everything after
/// that belongs to the wheels: the front pair turns, the back pair is what the
/// engine reaches, each one rides a spring you can stiffen until the island
/// starts throwing the car around, and the hand brake locks only the pair that
/// has one, which is what lets the back step out. The three knobs are all live,
/// so you can soften the springs or oil the tires mid-corner and feel it.
@main
final class Joyride: Sketch {
    let world = World3D()
    var land = Heightfield(columns: 2, rows: 2)
    var terrain = Mesh(positions: [], indices: [])
    var car: Vehicle3D!
    var crates: [Body3D] = []

    /// The three knobs worth turning while driving. `topSpeed` is the gearing:
    /// wind it down and the car pulls harder but runs out of legs.
    @Param(10 ... 45, icon: "speedometer") var topSpeed = 26.0
    @Param(1.0 ... 3.2, icon: "car.side.rear.tilted") var springs = 1.6
    @Param(0.2 ... 1.6, icon: "car.rear.and.tire.marks") var grip = 1.0

    /// The chase camera's eye, eased so a jump does not jolt the frame.
    var eye = Vector3(0, 6, -12)
    /// Where a reset puts the car back.
    var start = Vector3(0, 0, 0)

    let landWidth = 64.0, landDepth = 64.0, landHeight = 7.0
    /// The height of the flat apron the car starts on, read back from the
    /// finished field: erosion and the closing `normalized()` both move it.
    var apronY = 0.0

    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0xD94F70),
        Color(hex: 0x8D92E0), Color(hex: 0x72BFB2),
    ]

    override func setup() {
        buildIsland()
        buildCourse()
        start = Vector3(0, apronY + 1.4, -8)
        car = buildCar(at: start)
        eye = start + Vector3(0, 5, -12)
    }

    /// A flat apron in the middle to launch from, hills around the rim to climb
    /// and slide down, and erosion to cut the gullies that make them worth
    /// driving.
    func buildIsland() {
        let bumps = Heightfield.diamondSquare(size: 129, roughness: 0.5, seed: 12)
        land = Heightfield(columns: 129, rows: 129) { u, v in
            let d = Vector2(u - 0.5, v - 0.5).length * 2      // 0 center … 1 edge
            let apron = 0.2
            let hills = smoothstep(0.34, 0.8, d) * (1 - smoothstep(0.84, 1, d))
            let shore = 1 - smoothstep(0.88, 1.0, d)
            return (apron + hills * (0.25 + 0.75 * bumps.value(u: u, v: v))) * shore
        }
        .eroded(.hydraulic(drops: 40_000), seed: 12)
        .eroded(.thermal(talus: 0.02, iterations: 20))
        .normalized()
        apronY = land.value(u: 0.5, v: 0.5) * landHeight
        terrain = terrainMesh(land)
        // The tires want grip: a slick island is a skating rink.
        world.addBody(.heightfield(land, width: landWidth, depth: landDepth,
                                   height: landHeight),
                      at: .zero, kind: .static, friction: 0.9)
    }

    /// The things worth driving at: a ramp to leave the ground over and a stack
    /// of crates light enough to scatter.
    func buildCourse() {
        // A ramp on the apron, tilted about x so it climbs toward +z. Its low
        // lip is sunk into the ground: a ramp a car has to climb a step onto
        // is a wall, not a jump.
        let rampDepth = 8.0, rampTilt = 0.24
        world.addBody(.box(width: 5, height: 0.3, depth: rampDepth),
                      at: Vector3(0, apronY + rampDepth / 2 * sin(rampTilt), 8),
                      kind: .static, rotated: -rampTilt, axis: .unitX,
                      friction: 0.9)

        for level in 0 ..< 3 {
            for column in 0 ... (3 - level) {
                let x = Double(column) * 1.1 - Double(3 - level) * 0.55
                let crate = world.addBody(
                    .box(width: 1, height: 1, depth: 1),
                    at: Vector3(x - 6, apronY + 0.55 + Double(level) * 1.05, 20),
                    density: 0.08, friction: 0.5)
                crate.userData = palette[(level + column) % palette.count]
                crates.append(crate)
            }
        }
    }

    /// The machine: a chassis box on four wheels, the front pair steering, the
    /// back pair driven and carrying the hand brake.
    func buildCar(at position: Vector3) -> Vehicle3D {
        let half = Vector3(0.93, -0.2, 1.32)
        let wheels = [
            Wheel3D.wheel(at: Vector3(half.x, half.y, half.z), radius: 0.37,
                          width: 0.3, steers: true),
            Wheel3D.wheel(at: Vector3(-half.x, half.y, half.z), radius: 0.37,
                          width: 0.3, steers: true),
            Wheel3D.wheel(at: Vector3(half.x, half.y, -half.z), radius: 0.37,
                          width: 0.3, driven: true, handBrake: true),
            Wheel3D.wheel(at: Vector3(-half.x, half.y, -half.z), radius: 0.37,
                          width: 0.3, driven: true, handBrake: true),
        ]
        for wheel in wheels {
            // Short enough that the tires sit in the arches rather than
            // dangling under the car, and long enough that softening the
            // springs visibly drops it onto its bump stops.
            wheel.suspensionLength = 0.3
            wheel.suspensionTravel = 0.24
            wheel.suspensionFrequency = springs
        }
        let built = world.addVehicle(.box(width: 1.68, height: 0.75, depth: 3.9),
                                     at: position, wheels: wheels, mass: 1300,
                                     engineTorque: 520, topSpeed: topSpeed,
                                     friction: 0.4)!
        // Keep it on its wheels: an island has slopes an unlimited chassis
        // would happily roll down on its roof.
        built.maxTilt = .pi / 3
        return built
    }

    override func draw() {
        background(Color(hex: 0x0A0F16))
        environment(.sky(turbidity: 2.4, sunElevation: 0.8))
        lightingPreset(.standard)
        castShadows()

        steer()
        world.advance(by: deltaTime)

        // Off the edge and into the sea: put it back on the apron.
        if car.body.position.y < -4 { reset() }

        followWithCamera()

        material(.dielectric(roughness: 0.9))
        fill(.white)
        drawMesh(terrain)
        drawCourse()
        drawCar()

        let kph = Int(abs(car.speed) * 3.6)
        drawCaption("\(kph) km/h   gear \(car.gear)      "
                    + "arrows or WASD to drive, space to hand brake, R to reset")
    }

    /// The whole of the input: four numbers on the vehicle. Everything after
    /// this is the wheels' business.
    func steer() {
        car.topSpeed = topSpeed
        for wheel in car.wheels {
            wheel.suspensionFrequency = springs
            wheel.grip = grip
        }

        var throttle = 0.0
        if isKeyDown(.upArrow) || isKeyDown("w") { throttle += 1 }
        if isKeyDown(.downArrow) || isKeyDown("s") { throttle -= 1 }
        var steering = 0.0
        if isKeyDown(.leftArrow) || isKeyDown("a") { steering -= 1 }
        if isKeyDown(.rightArrow) || isKeyDown("d") { steering += 1 }

        car.throttle = throttle
        car.steering = steering
        car.handBrake = isKeyDown(" ") ? 1 : 0
        if isKeyDown("r") { reset() }
    }

    /// Put the car back on the apron, upright and still.
    func reset() {
        car.body.position = start
        car.body.setRotation(0, axis: .unitY)
        car.body.velocity = .zero
        car.body.angularVelocity = .zero
        car.coast()
    }

    /// A camera that trails the car, swinging round behind it as it turns and
    /// easing rather than snapping so a landing does not jolt the frame.
    func followWithCamera() {
        let focus = car.body.position + Vector3(0, 1, 0)
        // Behind means behind the *car*, so the view swings through a corner.
        let behind = car.forward * -9 + Vector3(0, 3.4, 0)
        let wanted = focus + behind
        eye += (wanted - eye) * min(1, deltaTime * 3)
        camera(.perspective(eye: eye, target: focus + car.forward * 4,
                            fieldOfView: .pi / 3.2))
    }

    /// The car: a body, a cabin, and four wheels drawn where the suspension
    /// actually put them.
    func drawCar() {
        material(.dielectric(roughness: 0.3))
        fill(Color(hex: 0xE8632F))
        withBody(car.body) {
            drawBox(width: 1.68, height: 0.75, depth: 3.9)
            fill(Color(hex: 0x1D2430))
            withState {
                translate(0, 0.55, -0.25)
                drawBox(width: 1.5, height: 0.6, depth: 1.9)
            }
            // A stripe over the nose so the facing reads at a glance.
            fill(Color(hex: 0xF2A93B))
            withState {
                translate(0, 0.39, 1.3)
                drawBox(width: 0.5, height: 0.04, depth: 1.1)
            }
        }

        material(.dielectric(roughness: 0.7))
        for wheel in car.wheels {
            // A wheel spinning up out of a corner glows: the tire is sliding
            // rather than rolling, which is the one thing a driver wants to see.
            let spinning = min(1, wheel.slip)
            fill(Color.mix(Color(hex: 0x39424E), Color(hex: 0xF2A93B),
                           spinning))
            withWheel(wheel) {
                drawCylinder(radius: wheel.radius, height: wheel.width)
                fill(Color(hex: 0xB9AE9C))
                drawCylinder(radius: wheel.radius * 0.45, height: wheel.width * 1.05)
            }
        }
    }

    func drawCourse() {
        material(.dielectric(roughness: 0.75))
        fill(Color(hex: 0xB9AE9C))
        for body in world.bodies where body.kind == .static {
            guard case .box(let w, let h, let d) = body.collider else { continue }
            withBody(body) { drawBox(width: w, height: h, depth: d) }
        }
        material(.dielectric(roughness: 0.5))
        for crate in crates {
            fill(crate.userData as? Color ?? .white)
            withBody(crate) { drawBox(width: 1, height: 1, depth: 1) }
        }
    }

    /// The field as a mesh wearing a height-colored texture: sand at the
    /// waterline, grass on the apron, rock and scrub up the hills.
    private func terrainMesh(_ field: Heightfield) -> Mesh {
        let ramp = Ramp([Color(hex: 0xE4D2A6), Color(hex: 0x8FAE63),
                         Color(hex: 0x6E9450), Color(hex: 0x9A8E70),
                         Color(hex: 0xC3BCB1)])
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
