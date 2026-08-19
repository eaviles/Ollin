import Ollin
import OllinPhysics

/// A walkable island. An eroded `Heightfield` becomes both the ground you see
/// and the ground you stand on, and a `Character3D` walks it: arrow keys or
/// WASD to go, space to jump. The island is built to be argued with. A flight
/// of steps climbs to a lookout only because the walker's `stepHeight` allows
/// it (drag that knob to zero and the same stairs become a wall), the crates on
/// the plaza scatter only because it is strong enough to shove them, and the
/// hills around the rim get too steep to climb somewhere on the way up, which
/// is `maxSlope` deciding rather than the geometry. Stand on the lookout and
/// the sensor under it lights: a character shows up among the ordinary bodies,
/// so triggers see it walk in. Walk off the edge and you fall, and are put back.
@main
final class Stroll: Sketch {
    let world = World3D()
    var land = Heightfield(columns: 2, rows: 2)
    var terrain = Mesh(positions: [], indices: [])
    var walker: Character3D!
    var lookout: Body3D?
    var crates: [Body3D] = []

    /// How fast the walk is, and the tallest step it will take. `stepHeight` is
    /// the knob to play with: at 0 the stairs stop it dead.
    @Param(1 ... 7, icon: "figure.walk") var walkSpeed = 3.4
    @Param(0 ... 0.6, icon: "stairs") var stepHeight = 0.4

    /// How far the stride has swung, advanced by the ground actually covered,
    /// so the legs stop moving when a wall does.
    var stride = 0.0
    /// The chase camera's eye, eased toward where it wants to be.
    var eye = Vector3(0, 6, 10)

    let landWidth = 26.0, landDepth = 26.0, landHeight = 4.0
    /// The height the flat middle of the island ended up at, in world units.
    /// Read back from the finished field rather than assumed: erosion and the
    /// closing `normalized()` both move it, and the stairs have to land on it.
    var plazaY = 0.0
    /// The plaza's height while the field is still being written.
    let plazaLevel = 0.16

    let start = Vector3(0, 0, 3)
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0xD94F70),
        Color(hex: 0x8D92E0), Color(hex: 0x72BFB2),
    ]

    override func setup() {
        buildIsland()
        buildArchitecture()
        walker = world.addCharacter(radius: 0.28, height: 1.7,
                                    at: start + Vector3(0, plazaY + 0.4, 0),
                                    stepHeight: stepHeight)
        eye = walker.position + Vector3(0, 4, 9)
    }

    /// A flat plaza in the middle, hills around the rim, and nothing past the
    /// shoreline. Erosion cuts the gullies that make the hills worth reading.
    func buildIsland() {
        let bumps = Heightfield.diamondSquare(size: 129, roughness: 0.55, seed: 7)
        land = Heightfield(columns: 129, rows: 129) { u, v in
            let d = (Vector2(u - 0.5, v - 0.5).length) * 2      // 0 center … 1 edge
            // Flat out to the plaza, then hills, then falling into the water.
            let hills = smoothstep(0.3, 0.78, d) * (1 - smoothstep(0.82, 1, d))
            let shore = 1 - smoothstep(0.86, 1.0, d)
            return (self.plazaLevel + hills * (0.3 + 0.7 * bumps.value(atU: u, v: v)))
                * shore
        }
        .eroded(.hydraulic(drops: 30_000), seed: 7)
        .eroded(.thermal(talus: 0.014, iterations: 24))
        .normalized()
        plazaY = land.value(atU: 0.5, v: 0.5) * landHeight
        terrain = terrainMesh(land)
        world.addBody(.heightfield(land, width: landWidth, depth: landDepth,
                                   height: landHeight),
                      at: .zero, kind: .static, friction: 0.6)
    }

    /// The things on the plaza that answer back: a stair up to a lookout with a
    /// sensor under its deck, and a few crates light enough to shove.
    func buildArchitecture() {
        // Four steps climbing north, each one just inside the default reach.
        for index in 0 ..< 4 {
            let rise = 0.3
            let top = plazaY + rise * Double(index + 1)
            world.addBody(.box(width: 3, height: top, depth: 1),
                          at: Vector3(0, top / 2, -2.4 - Double(index) * 1.0),
                          kind: .static, friction: 0.6)
        }
        // The lookout deck the stair arrives on.
        let deckY = plazaY + 1.2
        world.addBody(.box(width: 3.6, height: deckY, depth: 3),
                      at: Vector3(0, deckY / 2, -7.4), kind: .static, friction: 0.6)
        // A detector standing on the deck: it reports the walker without ever
        // pushing it, so stepping onto the lookout is something the sketch can
        // notice happening.
        lookout = world.addBody(.box(width: 3.4, height: 1.8, depth: 2.8),
                                at: Vector3(0, deckY + 0.9, -7.4), isSensor: true)

        for index in 0 ..< 7 {
            let angle = Double(index) / 7 * .tau
            let crate = world.addBody(
                .box(width: 0.5, height: 0.5, depth: 0.5),
                at: Vector3(cos(angle) * 3.4, plazaY + 0.6, sin(angle) * 3.4 + 1.5),
                rotated: random(0, .tau), axis: .unitY, density: 0.02, friction: 0.4)
            crate.userData = palette[index % palette.count]
            crates.append(crate)
        }
    }

    override func draw() {
        background(Color(hex: 0x0B1017))
        // The sky is left visible here: an island wants a horizon behind it,
        // and it carries the ambient that keeps the ground off mud.
        environment(.sky(turbidity: 2.6, sunElevation: 0.85))
        lightingPreset(.standard)
        castShadows()

        steer()
        world.step(dt: deltaTime)

        // Fallen off the island: put the walker back on the plaza.
        if walker.position.y < -3 {
            walker.position = start + Vector3(0, plazaY + 1, 0)
            walker.stop()
        }

        followWithCamera()

        material(.dielectric(roughness: 0.9))
        fill(.white)
        drawMesh(terrain)
        drawArchitecture()
        drawWalker()

        let standing = lookout?.isTouching(walker.body) ?? false
        drawCaption(standing
            ? "on the lookout      arrows or WASD to walk, space to jump"
            : "arrows or WASD to walk, space to jump")
    }

    /// The whole of the input: read the keys, hand the character a velocity,
    /// ask for a jump. Everything else is the world's business.
    func steer() {
        walker.stepHeight = stepHeight

        var east = 0.0, south = 0.0
        if isKeyDown(.upArrow) || isKeyDown("w") { south -= 1 }
        if isKeyDown(.downArrow) || isKeyDown("s") { south += 1 }
        if isKeyDown(.leftArrow) || isKeyDown("a") { east -= 1 }
        if isKeyDown(.rightArrow) || isKeyDown("d") { east += 1 }

        let heading = Vector3(east, 0, south)
        walker.move(heading.length > 0 ? heading.normalized * walkSpeed : .zero)
        if isKeyDown(" ") { walker.jump(4.6) }

        // Face the way it is actually traveling, and swing the legs by the
        // ground covered rather than the clock, so walking into a crate that
        // will not move stops the stride too.
        let travel = Vector3(walker.actualVelocity.x, 0, walker.actualVelocity.z)
        if travel.length > 0.2 {
            walker.facing = atan2(travel.x, travel.z)
        }
        stride += travel.length * deltaTime * 3.4
    }

    /// A camera that trails the walker at a fixed angle, easing rather than
    /// snapping so a jump does not jolt the frame.
    func followWithCamera() {
        let focus = walker.position + Vector3(0, 1.1, 0)
        let wanted = focus + Vector3(0, 8.5, 11)
        eye += (wanted - eye) * min(1, deltaTime * 3.5)
        camera(.perspective(eye: eye, target: focus, fieldOfView: .pi / 3.4))
    }

    /// The figure: modeled facing its own +z, so `withCharacter` turns it by
    /// `facing` and stands it on the ground at the character's feet.
    func drawWalker() {
        let swing = sin(stride) * 0.42
        material(.dielectric(roughness: 0.45))
        withCharacter(walker) {
            fill(Color(hex: 0x1D2430))
            for (side, phase) in [(-1.0, swing), (1.0, -swing)] {
                withState {
                    translate(0.12 * side, 0.72, 0)
                    rotate(phase, axis: .unitX)
                    translate(0, -0.36, 0)
                    drawCapsule(radius: 0.1, height: 0.5)
                }
            }
            fill(Color(hex: 0xE8632F))
            withState {
                translate(0, 1.14, 0)
                drawCapsule(radius: 0.21, height: 0.42)
            }
            fill(Color(hex: 0x1D2430))
            for (side, phase) in [(-1.0, -swing), (1.0, swing)] {
                withState {
                    translate(0.3 * side, 1.3, 0)
                    rotate(phase * 0.7, axis: .unitX)
                    translate(0, -0.24, 0)
                    drawCapsule(radius: 0.07, height: 0.34)
                }
            }
            fill(Color(hex: 0xF2C9A0))
            withState {
                translate(0, 1.56, 0)
                drawSphere(radius: 0.18)
            }
            // A brim so the facing reads at a glance.
            fill(Color(hex: 0xD94F70))
            withState {
                translate(0, 1.62, 0.12)
                drawBox(width: 0.34, height: 0.05, depth: 0.2)
            }
        }
    }

    func drawArchitecture() {
        material(.dielectric(roughness: 0.75))
        fill(Color(hex: 0xB9AE9C))
        for body in world.bodies where body.kind == .static && !body.isSensor {
            guard case .box(let w, let h, let d) = body.collider else { continue }
            withBody(body) { drawBox(width: w, height: h, depth: d) }
        }

        // The lookout's marker, lit while the walker is standing in it.
        if let lookout {
            let standing = lookout.isTouching(walker.body)
            fill(standing ? Color(hex: 0xF2A93B) : Color(hex: 0x3A4455))
            material(standing ? .dielectric(roughness: 0.2) : .dielectric(roughness: 0.8))
            withBody(lookout) {
                withState {
                    translate(0, -0.85, 0)
                    drawBox(width: 3.4, height: 0.1, depth: 2.8)
                }
            }
        }

        material(.dielectric(roughness: 0.5))
        for crate in crates {
            fill(crate.userData as? Color ?? .white)
            withBody(crate) { drawBox(width: 0.5, height: 0.5, depth: 0.5) }
        }
    }

    /// The field as a mesh wearing a height-colored texture: sand at the
    /// waterline, grass on the plaza, rock and scrub up the hills.
    private func terrainMesh(_ field: Heightfield) -> Mesh {
        let ramp = Ramp([Color(hex: 0xE4D2A6), Color(hex: 0x8FAE63),
                         Color(hex: 0x6E9450), Color(hex: 0x9A8E70),
                         Color(hex: 0xC3BCB1)])
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.values.count * 4)
        for value in field.values {
            let c = ramp.color(at: min(max(value, 0), 1))
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
