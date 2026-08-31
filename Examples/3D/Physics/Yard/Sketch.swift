import Foundation
import Ollin
import OllinPhysics

/// A yard with a truck in it, a figure pacing across it, and a heap of crates
/// to knock about. Then the whole yard is put in a file, and comes back.
///
/// A saved world holds more than its loose crates. The truck comes back with
/// its wheels still turning at the speed they were turning, in the gear the
/// box had picked, so a restore mid-drive carries on rather than pulling away
/// from rest. The walker comes back mid-stride. The figure comes back where it
/// fell, wearing the capsules that were fitted to its mesh.
///
/// - **Arrow keys** drive the truck. Run it into the crates, or into the
///   figure lying by the wall.
/// - **S** writes the yard to a file, **L** reads it back, **R** puts back the
///   moment the yard was last saved. The file is loaded at startup whenever
///   one is found, so quitting and running again finds the yard as you left it.
/// - **N** clears it out and lays a fresh one.
///
/// **R** works before anything is saved, too: the yard keeps a snapshot of the
/// moment it first settled, so a wrecked yard comes back exactly, down to
/// which crate leans on which. Settling again would not do that. The solver
/// runs in floating point, and a toppling stack turns a last-bit difference
/// into a different arrangement; a snapshot has nothing left to compute.
///
/// The one thing the file does not hold is the figure's skin. That is the
/// sketch's own asset, loaded from the sketch's own bundle, and the snapshot
/// holds only what the solver was built from: a capsule per joint, the tree
/// they hang in, and how far each may bend. So `figure.apply(walker)` still
/// draws the mesh over the restored bodies, exactly as it did before.
///
/// Two things in the yard say the same thing out loud. The ground the yard is
/// cut into is a heightfield, and the banner strung across it is a cloth, and
/// both are made of more numbers than everything else here put together. So
/// each is given an `assetName`, the file writes the name down instead of the
/// geometry, and the sketch says what the names mean on the way back in. That
/// is the trade: a snapshot that names nothing is self-contained and can be
/// committed beside a sketch, and one that names things is a fraction of the
/// size and needs the sketch to hand its assets over.
@main
final class Yard: Sketch {
    let world = World3D()

    /// The figure's skin: the sketch's asset, not the snapshot's. One copy is
    /// posed from the fallen figure every frame; the other stays as it was
    /// loaded, so the pacer has a body to wear.
    var skin: Scene!
    var standing: Scene!
    /// The two heavy pieces of geometry, which the file names rather than
    /// holds. They are built here, once, and handed back when it asks.
    let ground = Heightfield.diamondSquare(size: 65, roughness: 0.5, seed: 6)
    let bannerMesh = Mesh.plane(width: 5, depth: 2.4, segments: 18)
    var groundMesh: Mesh!
    var banner: SoftBody3D?
    /// The animation the file ships with, so the pacer is not a mannequin.
    var idle: SceneAnimation?
    var truck: Vehicle3D?
    var pacer: Character3D?
    var fallen: Ragdoll3D?

    /// The yard as it stood when it was last saved.
    var kept: PhysicsSnapshot?

    /// Where **S** writes and **L** reads.
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("ollin-yard.physics")

    var message = ""
    var messageUntil = 0.0
    /// Which way the pacer is walking, so it turns at the end of its beat.
    var pacing = 1.0

    let crateColors: [Color] = [Color(hex: 0xB98B54), Color(hex: 0xA97B49),
                                Color(hex: 0xC59A63), Color(hex: 0x94693D)]
    let paint = Color(hex: 0x3F6E8C)
    let rubber = Color(hex: 0x22242A)
    let cloth = Color(hex: 0xD8CBB4)

    override func setup() {
        skin = Scene(resource: "figure", withExtension: "gltf", in: Bundle.module)
        standing = skin
        idle = skin.animations.first
        groundMesh = ground.mesh(width: 40, depth: 34, height: 1.6)
        world.ground = nil
        world.restitution = 0.1

        if world.load(contentsOf: file, resolving: asset) {
            adopt()
            kept = try? PhysicsSnapshot(contentsOf: file)
            say("loaded the yard from the last run")
        } else {
            build()
        }
    }

    // MARK: Laying out a yard

    /// What each name the snapshot wrote down actually is. The sketch stays
    /// the source of truth about where its own geometry lives.
    func asset(_ name: String) -> PhysicsAsset? {
        switch name {
        case "yard": return .heightfield(ground)
        case "banner": return .mesh(bannerMesh)
        default: return nil
        }
    }

    func build() {
        world.removeAll()

        // The yard's own ground: a heightfield, which is thousands of numbers,
        // so it is named rather than written into the file.
        let floor = world.addBody(.heightfield(ground, width: 40, depth: 34,
                                               height: 1.6),
                                  at: Vector3(0, -0.8, 0), kind: .static,
                                  friction: 0.9)
        floor.assetName = "yard"

        // The walls, so nothing that gets hit leaves.
        world.addBody(.box(width: 22, height: 1.4, depth: 0.5),
                      at: Vector3(0, 0.7, -6), kind: .static, friction: 0.8)
        world.addBody(.box(width: 0.5, height: 1.4, depth: 12),
                      at: Vector3(-9, 0.7, 0), kind: .static, friction: 0.8)

        // A stack to drive into.
        for i in 0 ..< 12 {
            let row = i / 3, column = i % 3
            world.addBody(.box(width: 0.8, height: 0.8, depth: 0.8),
                          at: Vector3(Double(column) * 0.85 - 3.15,
                                      0.41 + Double(row) * 0.81, -4.3),
                          density: 0.6, friction: 0.7)
        }

        let wheels = [Vector3(0.85, -0.28, 1.2), Vector3(-0.85, -0.28, 1.2),
                      Vector3(0.85, -0.28, -1.2), Vector3(-0.85, -0.28, -1.2)]
            .enumerated().map { index, mount -> Wheel3D in
                let wheel = Wheel3D.wheel(at: mount, radius: 0.38, width: 0.28,
                                          steers: index < 2, driven: index >= 2,
                                          handBrake: index >= 2)
                // A shorter spring than the default, so the body sits down on
                // its wheels rather than up on stilts.
                wheel.suspensionLength = 0.26
                wheel.suspensionTravel = 0.2
                return wheel
            }
        truck = world.addVehicle(.box(width: 1.7, height: 0.7, depth: 3.4),
                                 at: Vector3(2.4, 1.3, 2.4), wheels: wheels,
                                 mass: 1400, engineTorque: 520, topSpeed: 16,
                                 rotated: .pi, axis: .unitY)

        // Parked while the yard settles, or it rolls away down the slope
        // before anyone has touched it.
        truck?.handBrake = 1

        pacer = world.addCharacter(radius: 0.3, height: 1.75,
                                   at: Vector3(-5.5, 0.1, 1.6))

        // A second figure, dropped from a height so it lands in a heap: the
        // arrangement a snapshot exists to keep.
        fallen = world.addRagdoll(from: skin, at: Vector3(-0.6, 2.4, -1.4),
                                  mass: 68, friction: 0.7)

        // A banner strung between two posts. A soft body *is* its mesh, so a
        // name is what makes it saveable at all.
        banner = world.addSoftBody(from: bannerMesh, at: Vector3(2.9, 2.7, -3.9),
                                   mass: 1.2, stiffness: 0.7, damping: 0.2,
                                   pinned: { $0.z < -1.1 && abs($0.x) > 2.2 })
        banner?.assetName = "banner"

        for _ in 0 ..< 300 { world.advance(by: 1.0 / 60) }

        kept = world.snapshot()
        say("a fresh yard")
    }

    /// After a restore the objects are new ones, so the sketch takes them from
    /// the world again rather than holding on to what it had.
    func adopt() {
        truck = world.vehicles.first
        pacer = world.characters.first
        fallen = world.ragdolls.first
        banner = world.softBodies.first
    }

    // MARK: Keeping it

    override func keyPressed() {
        switch key?.lowercased() ?? "" {
        case "s":
            do {
                try world.save(to: file)
                kept = world.snapshot()
                say("saved to \(file.path)")
            } catch {
                say("could not write \(file.path)")
            }
        case "l":
            if world.load(contentsOf: file, resolving: asset) {
                adopt()
                kept = try? PhysicsSnapshot(contentsOf: file)
                say("loaded the yard from the file")
            } else {
                say("no file yet: press S first")
            }
        case "r":
            guard let kept else { return }
            world.restore(kept, resolving: asset)
            adopt()
            say("back to the yard as it was saved")
        case "n":
            build()
        default:
            break
        }
    }

    func say(_ text: String) {
        message = text
        messageUntil = time + 5
    }

    // MARK: Drawing

    override func draw() {
        background(Color(hex: 0x151A21))
        environment(.sky(turbidity: 3.6, sunElevation: 0.36))
        lightingPreset(.goldenHour)
        castShadows()
        perspective(eye: Vector3(7.4, 6.2, 12.2), target: Vector3(-0.7, 0.9, -1.4))

        drive()
        walk()
        if let idle {
            standing.apply(idle, at: time.truncatingRemainder(dividingBy: idle.duration))
        }
        world.advance(by: deltaTime)
        if let fallen { skin.apply(fallen) }

        drawGround()
        drawBanner()
        drawCrates()
        drawTruck()
        drawPacer()
        drawScene(skin)

        drawCaption(time < messageUntil
                    ? message
                    : "arrows drive      S save      L load      R saved yard"
                        + "      N new yard")
    }

    /// The truck is driven the way any vehicle is: three numbers set each
    /// frame. They are saved too, so a restore comes back under power.
    func drive() {
        guard let truck else { return }
        truck.throttle = (isKeyDown(.upArrow) ? 1 : 0) - (isKeyDown(.downArrow) ? 1 : 0)
        truck.steering = (isKeyDown(.rightArrow) ? 1 : 0) - (isKeyDown(.leftArrow) ? 1 : 0)
        truck.brake = isKeyDown(" ") ? 1 : 0
        // The yard is not flat, so a truck nobody is driving is a truck with
        // its parking brake on.
        truck.handBrake = truck.throttle == 0 ? 1 : 0
    }

    /// The pacer walks its own beat, so a restore lands mid-stride rather than
    /// at either end of it.
    func walk() {
        guard let pacer else { return }
        if pacer.position.x > -2 { pacing = -1 }
        if pacer.position.x < -7 { pacing = 1 }
        pacer.move(Vector3(1.6 * pacing, 0, 0))
        pacer.facing = pacing > 0 ? .pi / 2 : -.pi / 2
    }

    /// The yard's ground is the same heightfield the collider was cut from, so
    /// the mesh drawn and the surface walked on are one surface.
    func drawGround() {
        fill(Color(hex: 0x8A7F63))
        material(.dielectric(roughness: 1))
        withState {
            translate(0, -0.8, 0)
            drawMesh(groundMesh)
        }
    }

    func drawBanner() {
        guard let banner else { return }
        fill(Color(hex: 0xC2544A))
        material(.dielectric(roughness: 0.85))
        drawSoftBody(banner)
    }

    /// Everything loose in the yard, walls included, drawn out of the collider
    /// each body came back wearing.
    func drawCrates() {
        for (index, body) in world.bodies.enumerated() {
            guard case .box(let width, let height, let depth) = body.collider else {
                continue
            }
            let isWall = body.kind == .static
            let isTruck = body === truck?.body
            if isTruck { continue }
            fill(isWall ? Color(hex: 0x6B6552) : crateColors[index % crateColors.count])
            material(.dielectric(roughness: isWall ? 1 : 0.85))
            withBody(body) { drawBox(width: width, height: height, depth: depth) }
        }
    }

    func drawTruck() {
        guard let truck else { return }
        fill(paint)
        material(.glossy)
        withBody(truck.body) { drawBox(width: 1.7, height: 0.7, depth: 3.4) }
        fill(rubber)
        material(.dielectric(roughness: 0.9))
        for wheel in truck.wheels {
            withWheel(wheel) {
                drawCylinder(radius: wheel.radius, height: wheel.width)
            }
        }
    }

    /// A character is a swept capsule with no mesh of its own, so the pacer
    /// wears the same figure the fallen one does, standing in the pose it was
    /// loaded in. `withCharacter` puts it on its feet facing the right way.
    func drawPacer() {
        guard let pacer else { return }
        fill(cloth)
        material(.dielectric(roughness: 0.8))
        withCharacter(pacer) { drawScene(standing) }
    }
}
