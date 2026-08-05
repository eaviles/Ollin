import Ollin
import OllinPhysics

/// A sorting machine, and the only thing doing the sorting is three sentences.
/// Beads of three colors tumble down one ramp. Three windows are set into it,
/// and each window is told to ignore one color: a bead of that color falls
/// straight through into the chute below, and every other bead rolls over the
/// window as if it were solid ramp. Nothing checks a color and nothing opens
/// or closes; the beads that belong there simply stop being able to touch it.
///
/// **Space** withdraws the three rules, which is the same machine unsorted:
/// every bead now rides the whole ramp into the overflow tray at the end.
/// **Drag** any bead to put it back where you like.
///
/// The collision-group showcase for `World3D`: `group:` on the bodies,
/// `ignoreCollisions(between:and:)` for the rules, and `raycast(as:)` for the
/// three guide lines, each dropped as a bead of its own color and so falling
/// through exactly the window that color belongs to.
@main
final class Sieve: Sketch {
    let world = World3D()

    /// One sorted kind: what a bead is, which window lets it through, and the
    /// color both are drawn in.
    struct Kind {
        var group: CollisionGroup
        var window: CollisionGroup
        var color: Color
        /// Where along the ramp this kind's window sits.
        var windowX: Double
    }

    let kinds = [
        Kind(group: "amber", window: "amber-window",
             color: Color(hex: 0xF2A93B), windowX: -2.5),
        Kind(group: "teal", window: "teal-window",
             color: Color(hex: 0x3FBFA8), windowX: -0.3),
        Kind(group: "rose", window: "rose-window",
             color: Color(hex: 0xE0607E), windowX: 1.9),
    ]

    /// Everything the machine is made of, with the color it is drawn in, so
    /// the drawing loop never has to work out what a body was for.
    var parts: [(body: Body3D, color: Color)] = []
    var beads: [Body3D] = []
    var nextBead = 0
    var sinceSpawn = 0.0
    var grabbed: Joint3D?

    @Param(icon: "line.3.horizontal.decrease") var sorting = true
    @Param(0.08 ... 0.5, icon: "timer") var dropEvery = 0.15

    let rampTilt = 13 * Double.pi / 180
    let rampTop = Vector3(-5.6, 4.3, 0)
    let rampWidth = 2.0
    let windowWidth = 1.1
    let chuteDrop = 1.35
    let beadRadius = 0.18
    let trayY = 0.1
    let steel = Color(hex: 0x1D2534)

    override func setup() {
        world.ground = -1.5
        world.bounce = 0.1
        buildRamp()
        buildChutes()
        buildTrays()
        stockTheHopper()
        applyRules()
    }

    // MARK: The machine

    /// A point on the ramp's own line, at `x` along the world's x axis.
    func onRamp(_ x: Double) -> Vector3 {
        Vector3(x, rampTop.y - (x - rampTop.x) * tan(rampTilt), 0)
    }

    /// Which way is up for the ramp: everything bolted to it hangs along this.
    var rampUp: Vector3 { Vector3(sin(rampTilt), cos(rampTilt), 0) }

    @discardableResult
    func part(_ size: Vector3, at position: Vector3, color: Color,
              tilted: Bool = true, friction: Double = 0.4,
              group: CollisionGroup = .default) -> Body3D {
        let body = world.addBody(.box(width: size.x, height: size.y, depth: size.z),
                                 at: position, kind: .static,
                                 rotated: tilted ? -rampTilt : 0, axis: .unitZ,
                                 friction: friction, group: group)
        parts.append((body, color))
        return body
    }

    /// One plate of the ramp. A window and a solid stretch are the same plate;
    /// the only difference between them is the group it is in.
    func plate(from startX: Double, to endX: Double, color: Color,
               group: CollisionGroup = .default) {
        let span = endX - startX
        part(Vector3(span / cos(rampTilt), 0.2, rampWidth),
             at: onRamp(startX + span / 2), color: color, friction: 0.3, group: group)
    }

    func buildRamp() {
        var edge = rampTop.x
        for kind in kinds {
            let start = kind.windowX - windowWidth / 2
            plate(from: edge, to: start, color: steel)
            plate(from: start, to: start + windowWidth,
                  color: kind.color.withAlpha(0.55), group: kind.window)
            edge = start + windowWidth
        }
        plate(from: edge, to: 3.1, color: steel)

        // Rails, so a bead that bounces stays on the ramp.
        for side in [-1.0, 1.0] {
            part(Vector3(9.0, 0.5, 0.12),
                 at: onRamp(-1.25) + Vector3(0, 0.24, side * (rampWidth / 2 + 0.06)),
                 color: steel, friction: 0.2)
        }
    }

    /// A chute hanging under each window, tilted with the ramp. It is what
    /// makes the sorting land where it should: a bead drops through the window
    /// still carrying its roll, and with nothing to catch that it would fly on
    /// under the ramp and come down in the next color's tray.
    func buildChutes() {
        for kind in kinds {
            let below = rampUp * -(chuteDrop / 2 + 0.1)
            let color = kind.color.withAlpha(0.14)
            for edge in [-windowWidth / 2, windowWidth / 2] {
                part(Vector3(0.09, chuteDrop, rampWidth + 0.18),
                     at: onRamp(kind.windowX + edge) + below, color: color)
            }
            for side in [-1.0, 1.0] {
                part(Vector3(windowWidth, chuteDrop, 0.09),
                     at: onRamp(kind.windowX) + below
                         + Vector3(0, 0, side * (rampWidth / 2 + 0.05)),
                     color: color)
            }
        }
    }

    /// A shallow open tray. Trays stay in the default group, so every one of
    /// them catches every bead: a tray in its window's group would be ignored
    /// by exactly the beads it is there to hold. `backboard` raises the far
    /// wall, which is how the last tray catches beads still travelling at the
    /// speed the whole ramp gave them.
    func tray(at center: Vector3, width: Double, depth: Double,
              backboard: Double = 0.7) {
        part(Vector3(width, 0.2, depth), at: center, color: steel, tilted: false,
             friction: 0.7)
        part(Vector3(0.14, backboard, depth),
             at: center + Vector3(width / 2, backboard / 2, 0), color: steel,
             tilted: false, friction: 0.5)
        for (offset, size) in [(Vector3(-width / 2, 0.35, 0), Vector3(0.14, 0.7, depth)),
                               (Vector3(0, 0.35, depth / 2), Vector3(width, 0.7, 0.14)),
                               (Vector3(0, 0.35, -depth / 2), Vector3(width, 0.7, 0.14))] {
            part(size, at: center + offset, color: steel, tilted: false, friction: 0.5)
        }
    }

    func buildTrays() {
        for kind in kinds {
            // Under the chute's mouth, which the ramp's tilt carries a little
            // back up the slope from the window itself.
            let mouth = onRamp(kind.windowX) - rampUp * chuteDrop
            tray(at: Vector3(mouth.x, trayY, 0), width: 1.8, depth: 2.4)
        }
        // The overflow, which everything reaches when the sorting is off. It
        // sits where a bead leaving the end of the ramp lands, with a tall
        // back wall for the ones still carrying the whole slope's worth of
        // speed.
        tray(at: Vector3(5.4, trayY - 1.1, 0), width: 3.4, depth: 2.4,
             backboard: 2.1)
    }

    // MARK: The beads

    func stockTheHopper() {
        for index in 0 ..< 54 {
            let kind = kinds[index % kinds.count]
            let bead = world.addBody(.sphere(radius: beadRadius), at: hopper(),
                                     density: 0.7, friction: 0.3, restitution: 0.1,
                                     group: kind.group)
            bead.userData = kind.color
            bead.kind = .static           // parked until it is its turn
            beads.append(bead)
        }
    }

    /// Where a bead enters the machine, spread across the ramp so the stream
    /// does not run down one line.
    func hopper() -> Vector3 {
        onRamp(rampTop.x + 0.8) + Vector3(0, 1.3, random(-0.5, 0.5))
    }

    /// Beads are a fixed pool: the next drop is the oldest one, lifted back to
    /// the hopper. The trays empty themselves from the bottom, and the machine
    /// runs forever without growing.
    func dropOne() {
        let bead = beads[nextBead]
        nextBead = (nextBead + 1) % beads.count
        bead.kind = .dynamic
        bead.position = hopper()
        bead.velocity = Vector3(0.5, 0, 0)
        bead.angularVelocity = .zero
    }

    // MARK: The rules

    /// All of them: three sentences, one per color. Everything else about the
    /// machine is ordinary geometry.
    func applyRules() {
        for kind in kinds {
            if sorting {
                world.ignoreCollisions(between: kind.group, and: kind.window)
            } else {
                world.allowCollisions(between: kind.group, and: kind.window)
            }
        }
    }

    override func keyPressed() {
        if key == " " {
            sorting.toggle()
            applyRules()
        }
    }

    override func mousePressed() {
        grabbed = grabBody(at: Vector2(mouseX, mouseY), in: world)
    }

    override func mouseReleased() {
        grabbed?.remove()
        grabbed = nil
    }

    override func draw() {
        background(Color(hex: 0x0A0D14))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        cameraShowcase(.autoOrbit(period: 52), from: Camera3D
            .perspective(eye: Vector3(0.8, 5.0, 12.2), target: Vector3(0.5, 1.3, 0)))

        sinceSpawn += deltaTime
        if sinceSpawn >= dropEvery {
            sinceSpawn = 0
            dropOne()
        }

        if let grabbed { dragGrab(grabbed, to: Vector2(mouseX, mouseY)) }
        world.step(dt: deltaTime)

        drawFloor()
        drawMachine()
        drawBeads()
        drawGuides()
        drawCaption(sorting ? "space: stop sorting      drag a bead"
                            : "space: sort again      everything rides to the end")
    }

    // MARK: Drawing it

    func drawFloor() {
        fill(Color(hex: 0x10141D))
        material(.dielectric(roughness: 0.94))
        withState {
            translate(0, -1.56, 0)
            drawBox(width: 40, height: 0.12, depth: 40)
        }
    }

    func drawMachine() {
        material(.dielectric(roughness: 0.72))
        for (body, color) in parts {
            fill(color)
            guard case .box(let w, let h, let d) = body.collider else { continue }
            withBody(body) { drawBox(width: w, height: h, depth: d) }
        }
    }

    func drawBeads() {
        material(.dielectric(roughness: 0.24))
        for bead in beads where bead.kind == .dynamic {
            fill(bead.userData as? Color ?? .white)
            withBody(bead) { drawSphere(radius: beadRadius, segments: 14, rings: 8) }
        }
    }

    /// One guide per color, dropped from above its own window and asked *as*
    /// that color: it falls through the window that color belongs to and
    /// lands in the tray, where the same line asked as anything else stops on
    /// the ramp. Turn the sorting off and all three stop on the ramp.
    func drawGuides() {
        material(.dielectric(roughness: 0.4))
        for kind in kinds {
            let from = onRamp(kind.windowX) + Vector3(0, 2.4, 0)
            guard let landed = world.raycast(from: from, to: from - Vector3(0, 9, 0),
                                             as: kind.group) else { continue }
            fill(kind.color.withAlpha(0.32))
            drawTube([from, landed.point], radius: 0.013, sides: 6)
            withState {
                translate(landed.point + Vector3(0, 0.02, 0))
                drawCylinder(radius: 0.2, height: 0.02)
            }
        }
    }
}
