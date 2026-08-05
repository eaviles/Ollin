import Ollin
import OllinPhysics

/// A pin table, built in a 3D world that has been talked out of its third
/// dimension. Every ball is told it may travel in x and y and turn about z and
/// nothing else, so the whole machine behaves like a flat one however hard the
/// pins knock it about, while still being lit, shadowed, and drawn as solid.
///
/// **Space** fires the plunger: a small quick ball up the lane on the right.
/// **Drag** any ball to move it. The three knobs are the three things a body
/// can be told about its own motion:
///
/// - **flat** is `freedom`. On, every ball is `.plane()` and the table works.
///   Off, the same balls are free in every direction, and the pins send them
///   drifting out of the board and away past the camera.
/// - **weight** is `gravityScale`, live on every ball. `1` is an ordinary
///   steel ball; below it they hang and dawdle; below zero they rise and the
///   table runs upside down.
/// - **sweep** is `checksPath`, and only the plunger's shot is quick enough to
///   care. On, the gate at the top of the lane turns it into play. Off, it
///   covers more ground in one step than the gate is thick, so it passes
///   through the gate and the rail above it and leaves the machine, having
///   touched nothing at all.
@main
final class Bagatelle: Sketch {
    let world = World3D()

    @Param(icon: "rectangle.compress.vertical") var flat = true
    @Param(-0.6 ... 1.4, icon: "scalemass") var weight = 1.0
    @Param(icon: "arrow.right.to.line") var sweep = true

    var balls: [Body3D] = []
    var pins: [Vector3] = []
    var walls: [(body: Body3D, size: Vector3)] = []
    var grabbed: Joint3D?
    var shots: Set<ObjectIdentifier> = []

    let boardWidth = 7.0
    let boardHeight = 9.0
    let laneX = 3.05
    let ballRadius = 0.22
    let shotRadius = 0.08
    let steel = Color(hex: 0xDCE6F2)
    let brass = Color(hex: 0xE8A83A)
    let frame = Color(hex: 0x151A25)

    override func setup() {
        // No floor: a ball that escapes the board should be seen leaving.
        world.bounce = 0.45
        buildTable()
        for _ in 0 ..< 14 { drop() }
    }

    // MARK: The table

    @discardableResult
    func wall(_ size: Vector3, at position: Vector3, rotated angle: Double = 0)
        -> Body3D {
        let body = world.addBody(.box(width: size.x, height: size.y, depth: size.z),
                                 at: position, kind: .static,
                                 rotated: angle, axis: .unitZ, friction: 0.2)
        walls.append((body, size))
        return body
    }

    func buildTable() {
        let half = boardWidth / 2
        // The top rail and the gate above the lane are thin plates, the way a
        // pin table's really are, and they are what the plunger's shot has to
        // cross. A ball that covers more ground in one step than a plate is
        // thick can be in front of it at one step and behind it at the next,
        // which is exactly what `checksPath` is for.
        wall(Vector3(boardWidth + 1, 0.1, 0.6), at: Vector3(0, boardHeight / 2, 0))
        wall(Vector3(0.4, boardHeight, 0.6), at: Vector3(-half - 0.2, 0, 0))
        wall(Vector3(0.4, boardHeight, 0.6), at: Vector3(half + 0.7, 0, 0))
        // The lane the plunger fires up, and the gate that turns a shot inward.
        wall(Vector3(0.3, boardHeight - 1.6, 0.6), at: Vector3(laneX - 0.35, -0.6, 0))
        wall(Vector3(1.6, 0.08, 0.6), at: Vector3(half - 0.4, boardHeight / 2 - 1.1, 0),
             rotated: 0.5)

        // Pins on a staggered lattice, the way a pin table is set out.
        for row in 0 ..< 6 {
            let y = 2.6 - Double(row) * 1.15
            let offset = row.isMultiple(of: 2) ? 0.0 : 0.62
            for column in -2 ... 2 {
                let x = Double(column) * 1.24 + offset - 0.3
                guard x < laneX - 0.9 else { continue }
                pins.append(Vector3(x, y, 0))
                world.addBody(.cylinder(height: 0.6, radius: 0.16),
                              at: Vector3(x, y, 0), kind: .static,
                              rotated: .pi / 2, axis: .unitX,
                              friction: 0.1, restitution: 0.6)
            }
        }

        // Bins along the bottom, and the dividers between them.
        for column in -3 ... 2 {
            wall(Vector3(0.16, 1.8, 0.6),
                 at: Vector3(Double(column) * 1.05 + 0.5, -boardHeight / 2 + 0.9, 0))
        }
        wall(Vector3(boardWidth + 1, 0.3, 0.6), at: Vector3(0, -boardHeight / 2, 0))
    }

    // MARK: Balls

    /// The one line the whole sketch is about: a ball that may move in the
    /// board's plane and turn about the axis facing the camera, and no more.
    var boardPlane: Freedom3D { flat ? .plane() : .all }

    func drop() {
        let ball = world.addBody(.sphere(radius: ballRadius),
                                 at: Vector3(random(-2.8, 1.6), random(3.4, 4.2), 0),
                                 friction: 0.15, restitution: 0.5,
                                 freedom: boardPlane, gravityScale: weight)
        // The dropper is not careful: every ball arrives with a nudge toward or
        // away from the camera. A body held to its plane simply has nowhere to
        // put that, which is the point. A free one takes it and wanders off the
        // board, and the whole table stops being a table.
        ball.velocity = Vector3(0, 0, random(-2, 2))
        balls.append(ball)
    }

    /// The plunger's shot: small, quick, and the only body here that can
    /// outrun a single step.
    func fire() {
        let shot = world.addBody(.sphere(radius: shotRadius),
                                 at: Vector3(laneX, -boardHeight / 2 + 0.9, 0),
                                 density: 4, friction: 0.1, restitution: 0.55,
                                 freedom: boardPlane, gravityScale: weight,
                                 checksPath: sweep)
        shot.velocity = Vector3(0, 72, 0)
        balls.append(shot)
        shots.insert(ObjectIdentifier(shot))
    }

    override func keyPressed() {
        if key == " " { fire() }
    }

    override func mousePressed() {
        grabbed = grabBody(at: Vector2(mouseX, mouseY), in: world)
    }

    override func mouseReleased() {
        grabbed?.remove()
        grabbed = nil
    }

    override func draw() {
        background(Color(hex: 0x0E1119))
        // Steel and brass need something to reflect, so the table stands in a
        // room rather than under bare lamps.
        environment(.studio.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(0.9, 0.4, 12.2), target: Vector3(0.2, 0.1, 0))

        // All three knobs are live, so every ball is told again each frame:
        // this is the whole cost of changing what a body is allowed to do.
        for ball in balls {
            ball.freedom = boardPlane
            ball.gravityScale = weight
            if shots.contains(ObjectIdentifier(ball)) { ball.checksPath = sweep }
        }

        // Anything that has left the table is gone; a ball only leaves when a
        // knob let it.
        let escaped = balls.filter {
            abs($0.position.z) > 14 || abs($0.position.x) > 22
                || abs($0.position.y) > 26
        }
        for ball in escaped {
            shots.remove(ObjectIdentifier(ball))
            world.remove(ball)
        }
        balls.removeAll { ball in escaped.contains { $0 === ball } }

        if balls.count < 14 && frameCount % 45 == 0 { drop() }
        if let grabbed { dragGrab(grabbed, to: Vector2(mouseX, mouseY)) }
        world.step(dt: deltaTime)

        drawTable()
        drawBalls()

        drawCaption("space fires      drag a ball      "
                    + (flat ? "flat" : "free") + "      "
                    + (sweep ? "sweeping" : "not sweeping"))
    }

    func drawTable() {
        material(.dielectric(roughness: 0.85))
        fill(Color(hex: 0x0F131B))
        withState {
            translate(0, 0, -0.45)
            drawBox(width: boardWidth + 2.2, height: boardHeight + 0.9, depth: 0.3)
        }

        fill(frame)
        for wall in walls {
            withBody(wall.body) {
                drawBox(width: wall.size.x, height: wall.size.y, depth: wall.size.z)
            }
        }

        fill(brass)
        material(.metal(roughness: 0.3))
        for pin in pins {
            withState {
                translate(pin.x, pin.y, pin.z)
                rotateX(.pi / 2)
                drawCylinder(radius: 0.16, height: 0.6)
            }
        }
    }

    func drawBalls() {
        material(.metal(roughness: 0.28))
        for ball in balls {
            let isShot = shots.contains(ObjectIdentifier(ball))
            fill(isShot ? brass : steel)
            withBody(ball) {
                drawSphere(radius: isShot ? shotRadius : ballRadius)
            }
        }
    }
}
