import Foundation
import Ollin
import OllinPhysics

/// A cairn: stones tipped one at a time onto a heap and left to find their own
/// arrangement. The heap is the point. It takes a few hundred steps of falling
/// and rocking to make, no two are alike, and there is no way to write one down
/// as code. So it is saved instead.
///
/// - **R** puts back the heap as it stood the moment it settled, exactly, down
///   to which stone leans on which and where the lantern is in its swing.
/// - **S** writes that to a file and **L** reads it back. Quit the sketch, run
///   it again, and the same cairn is standing there: the file is loaded at
///   startup whenever one is found.
/// - **N** tips in a fresh load of stones and settles a new heap.
/// - **Drag** a stone to rummage, then press R when you have wrecked it.
///
/// Nothing in the drawing holds on to a body. Every one comes back wearing the
/// collider it was made with, so the loop asks each one what shape it is, and
/// they arrive in the order they were saved in, so the lantern is still the
/// second one. That is also why simulating again is not the same as saving:
/// the solver runs in floating point, and a toppling heap turns a last-bit
/// difference into a different arrangement. A saved heap has nothing left to
/// compute.
@main
final class Cairn: Sketch {
    let world = World3D()

    /// The heap as it stood when it first came to rest.
    var settled: PhysicsSnapshot?

    /// Where **S** writes and **L** reads.
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("ollin-cairn.physics")

    var grabbed: Joint3D?
    var message = ""
    var messageUntil = 0.0

    let stones: [Color] = [Color(hex: 0x9A9081), Color(hex: 0x847A6C),
                           Color(hex: 0xA8A091), Color(hex: 0x6F6A61),
                           Color(hex: 0x8D8474)]
    let timber = Color(hex: 0x4A4238)
    let flame = Color(hex: 0xFFC272)

    override func setup() {
        world.ground = 0
        world.bounce = 0

        if world.load(contentsOf: file) {
            settled = try? PhysicsSnapshot(contentsOf: file)
            say("loaded the cairn from the last run")
        } else {
            buildHeap()
        }
    }

    // MARK: Building a heap

    /// The post and its lantern first, so they are always the world's first two
    /// bodies, then the stones dropped down a narrow column onto each other.
    func buildHeap() {
        world.removeAll()

        let post = world.addBody(.box(width: 0.14, height: 3.4, depth: 0.14),
                                 at: Vector3(2.5, 1.7, -0.5), kind: .static)
        let lamp = world.addBody(.box(width: 0.3, height: 0.34, depth: 0.3),
                                 at: Vector3(1.85, 3.0, -0.5), density: 0.5)
        world.connect(post, lamp, .revolute(at: postTop(post), axis: .unitZ))
        lamp.velocity = Vector3(0, 0, 0.9)

        // A cairn is built a stone at a time, so it is settled a stone at a
        // time: each one is laid a little above whatever the heap has become
        // and given long enough to find its seat before the next arrives.
        // Dropping them all from a column just makes a scatter.
        for i in 0 ..< 26 {
            let turn = Double(i) * 2.399           // the golden angle: no lanes
            let reach = random(0.02, 0.26) * (1 - Double(i) / 40)
            let shape: Collider3D = switch i % 5 {
            case 0: .cylinder(height: random(0.1, 0.16), radius: random(0.24, 0.38))
            case 1: .sphere(radius: random(0.12, 0.17))
            default: .box(width: random(0.3, 0.54), height: random(0.11, 0.19),
                          depth: random(0.3, 0.54))
            }
            world.addBody(shape,
                          at: Vector3(cos(turn) * reach, heapTop() + 0.4,
                                      sin(turn) * reach),
                          // Turned about its own upright, so a flat stone is
                          // laid flat, which is how a heap holds together.
                          rotated: random(0, .pi), axis: .unitY,
                          density: 2.4, friction: 1, restitution: 0)
            for _ in 0 ..< 75 { world.step(dt: 1.0 / 60) }
        }

        // Then long enough for the whole heap to rock itself quiet.
        for _ in 0 ..< 400 { world.step(dt: 1.0 / 60) }
        settled = world.snapshot()
        say("a fresh heap of \(world.bodies.count - 2) stones")
    }

    /// How high the heap stands so far, ignoring the post and its lantern.
    func heapTop() -> Double {
        world.bodies.dropFirst(2).map(\.position.y).max() ?? 0
    }

    /// The top of the post, read off the collider it came back wearing.
    func postTop(_ post: Body3D) -> Vector3 {
        guard case .box(_, let height, _) = post.collider else { return post.position }
        return post.position + Vector3(0, height / 2, 0)
    }

    // MARK: Keeping it

    override func keyPressed() {
        switch key?.lowercased() ?? "" {
        case "r":
            guard let settled else { return }
            release()
            world.restore(settled)
            say("back to the heap it settled into")
        case "s":
            do {
                try world.save(to: file)
                settled = world.snapshot()
                say("saved to \(file.path)")
            } catch {
                say("could not write \(file.path)")
            }
        case "l":
            release()
            if world.load(contentsOf: file) {
                settled = try? PhysicsSnapshot(contentsOf: file)
                say("loaded the cairn from the file")
            } else {
                say("no file yet: press S first")
            }
        case "n":
            release()
            buildHeap()
        default:
            break
        }
    }

    /// Restoring builds new bodies, so anything holding an old one lets go.
    func release() {
        grabbed?.remove()
        grabbed = nil
    }

    func say(_ text: String) {
        message = text
        messageUntil = time + 5
    }

    override func mousePressed() {
        grabbed = grabBody(at: Vector2(mouseX, mouseY), in: world)
    }

    override func mouseReleased() {
        release()
    }

    // MARK: Drawing

    override func draw() {
        background(Color(hex: 0x1A1C21))
        environment(.sky(turbidity: 3.5, sunElevation: 0.18))
        lightingPreset(.goldenHour)
        castShadows()
        perspective(eye: Vector3(3.0, 2.2, 5.3), target: Vector3(0.5, 1.0, 0))

        if let grabbed { dragGrab(grabbed, to: Vector2(mouseX, mouseY)) }
        world.step(dt: deltaTime)

        drawGround()

        let post = world.bodies.first
        let lamp = world.bodies.count > 1 ? world.bodies[1] : nil
        if let lamp { pointLight(flame, at: lamp.position, intensity: 6) }

        for (i, body) in world.bodies.enumerated() {
            // Color comes from where the body sits in the list, which is the
            // one thing that survives a restore: the objects themselves do not.
            let isLamp = i == 1
            fill(i == 0 ? timber : (isLamp ? flame : stones[i % stones.count]))
            material(isLamp ? .glossy : .dielectric(roughness: 0.95))
            withBody(body) { draw(body.collider) }
        }

        // The bracket the lantern hangs on, from the top of the post to the
        // lantern wherever its swing has got to.
        if let post, let lamp {
            fill(timber)
            material(.dielectric(roughness: 0.95))
            drawRod(from: postTop(post), to: lamp.position, radius: 0.03)
        }

        drawCaption(time < messageUntil
                    ? message
                    : "R settled heap      S save      L load      N new heap"
                        + "      drag a stone")
    }

    func drawGround() {
        fill(Color(hex: 0x4A4437))
        material(.dielectric(roughness: 1))
        withState {
            translate(0, -0.2, 0)
            drawBox(width: 80, height: 0.4, depth: 80)
        }
    }

    /// Every body draws itself out of the collider it came back with.
    func draw(_ collider: Collider3D) {
        switch collider {
        case .box(let width, let height, let depth):
            drawBox(width: width, height: height, depth: depth)
        case .sphere(let radius):
            drawSphere(radius: radius)
        case .cylinder(let height, let radius):
            drawCylinder(radius: radius, height: height)
        default:
            break
        }
    }

    /// A thin cylinder spanning two world points (Ollin's cylinders stand on
    /// their own y, so this turns one to face along the span).
    func drawRod(from start: Vector3, to end: Vector3, radius: Double) {
        let span = end - start
        let length = span.length
        guard length > 1e-6 else { return }
        withState {
            translate(start + span * 0.5)
            let axis = Vector3(0, 1, 0).cross(span / length)
            if axis.length > 1e-6 {
                rotate(acos(max(-1, min(1, span.y / length))), axis: axis.normalized)
            }
            drawCylinder(radius: radius, height: length)
        }
    }
}
