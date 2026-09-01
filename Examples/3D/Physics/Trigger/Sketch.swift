import Ollin
import OllinPhysics

/// A trigger toy: balls rain onto a hoop, and the ones that fall clean through
/// it are counted by a sensor filling the ring. The tray below is a second
/// sensor, lit by however many balls are parked in it, and every hard knock
/// rings the air where it happened. **Drag** a ball to post it through by hand;
/// **space** drops another.
///
/// The contact showcase for `World3D`. Three surfaces, all polled in `draw()`:
/// `hoop.arrivals` counts the balls crossing the ring, `tray.touching` reads
/// what is resting in the tray (they fall asleep in there, and the sensor keeps
/// reporting them), and `world.contacts` carries every knock in the scene with
/// the speed it landed at.
@main
final class Trigger: Sketch {
    let world = World3D()
    var hoop: Body3D?
    var tray: Body3D?
    var balls: [Body3D] = []
    var restFrames: [Int] = []

    var score = 0
    var scoreGlow = 0.0
    var knocks: [Knock] = []

    @Param(0.4 ... 4, icon: "drop") var dropEvery = 1.1
    var nextDrop = 0.0

    let hoopCenter = Vector3(0, 3.2, 0)
    let hoopRadius = 1.1, hoopTube = 0.17, ballRadius = 0.22
    let trayHalf = 1.5
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0xD94F70),
        Color(hex: 0x8D92E0), Color(hex: 0x72BFB2),
    ]

    /// A ring drawn where two things met, fading as it spreads. Born from a
    /// contact, so its size is the speed of the impact.
    struct Knock {
        var at: Vector3
        var strength: Double
        var age = 0.0
    }

    override func setup() {
        world.ground = 0
        world.restitution = 0.35
        buildHoop()
        buildTray()
        for index in 0 ..< 5 { dropBall(stagger: index) }
    }

    /// The hoop: a solid rim of overlapping beads fused into one static body,
    /// and a disc of sensor filling the ring. The rim is what a ball clatters
    /// off (beads rather than blocks, so the tube is round the whole way and a
    /// ball rolls off it instead of parking); the sensor is the hole, and only
    /// a ball that gets through the hole enters it. A sensor is not solid, so
    /// the two happily occupy the same space.
    func buildHoop() {
        let beads = 28
        var rim: [Collider3D.Part] = []
        for index in 0 ..< beads {
            let angle = Double(index) / Double(beads) * .tau
            rim.append(.part(.sphere(radius: hoopTube),
                             at: Vector3(cos(angle), 0, sin(angle)) * hoopRadius))
        }
        world.addBody(.compound(rim), at: hoopCenter, kind: .static,
                      friction: 0.3, restitution: 0.5)

        hoop = world.addBody(.cylinder(height: 0.5, radius: hoopRadius - hoopTube),
                             at: hoopCenter, isSensor: true)
    }

    /// The tray: a solid pan the balls come to rest in, with a shallow sensor
    /// box sitting over its floor. Balls that settle in there fall asleep, and
    /// because a sensor stays awake it goes on counting them.
    func buildTray() {
        let wall = 0.18
        for side in 0 ..< 4 {
            let angle = Double(side) * .pi / 2
            let out = Vector3(cos(angle), 0, sin(angle)) * (trayHalf + wall / 2)
            world.addBody(.box(width: side % 2 == 0 ? wall : 2 * trayHalf + 2 * wall,
                               height: 0.4,
                               depth: side % 2 == 0 ? 2 * trayHalf + 2 * wall : wall),
                          at: Vector3(out.x, 0.2, out.z), kind: .static)
        }
        world.addBody(.box(width: 2 * trayHalf, height: 0.2, depth: 2 * trayHalf),
                      at: Vector3(0, 0.1, 0), kind: .static, friction: 0.8)

        tray = world.addBody(.box(width: 2 * trayHalf, height: 0.7,
                                  depth: 2 * trayHalf),
                             at: Vector3(0, 0.55, 0), isSensor: true)
    }

    func dropBall(stagger: Int = 0) {
        let ball = world.addBody(.sphere(radius: ballRadius),
                                 at: Vector3(random(-1.15, 1.15),
                                             5.6 + Double(stagger) * 0.7,
                                             random(-1.15, 1.15)),
                                 density: 1.4, friction: 0.35, restitution: 0.4)
        ball.userData = palette[balls.count % palette.count]
        balls.append(ball)
        restFrames.append(0)
    }

    /// Back to the sky: a ball that has been sitting still for a while, or one
    /// that skipped out of the tray entirely.
    func recycle(_ ball: Body3D) {
        ball.position = Vector3(random(-1.15, 1.15), 5.6 + random(0, 1.2),
                                random(-1.15, 1.15))
        ball.velocity = .zero
        ball.angularVelocity = .zero
    }

    override func keyPressed() {
        if key == " " { dropBall() }
    }

    override func draw() {
        background(Color(hex: 0x0A0D14))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(1.4, 4.0, 7.6), target: Vector3(0, 2.4, 0))

        dragBodies(in: world)
        world.advance(by: deltaTime)
        readTheTriggers()
        keepBallsInPlay()

        drawStage()
        drawHoop()
        for ball in balls {
            fill(ball.userData as? Color ?? .white)
            material(.dielectric(roughness: 0.28))
            withBody(ball) { drawSphere(radius: ballRadius) }
        }
        drawKnocks()

        drawCaption("through the hoop: \(score)      in the tray: "
                    + "\(tray?.touching.count ?? 0)")
    }

    /// The whole contact surface, read once a step. `arrivals` is the pair of
    /// transitions the hoop saw this step, `touching` is standing occupancy,
    /// and `world.contacts` is every knock in the scene.
    func readTheTriggers() {
        if let hoop {
            score += hoop.arrivals.count
            if !hoop.arrivals.isEmpty { scoreGlow = 1 }
        }
        scoreGlow = max(0, scoreGlow - deltaTime * 1.6)

        for contact in world.contacts where contact.phase == .began {
            // A ball settling into the tray touches at a crawl; only real
            // knocks are worth ringing.
            guard contact.speed > 1.4 else { continue }
            knocks.append(Knock(at: contact.point, strength: contact.speed))
        }
        for index in knocks.indices { knocks[index].age += deltaTime }
        knocks.removeAll { $0.age > 0.55 }
    }

    func keepBallsInPlay() {
        nextDrop -= deltaTime
        if nextDrop <= 0 {
            nextDrop = dropEvery
            if balls.count < 14 { dropBall() } else { recycle(balls[frameCount % balls.count]) }
        }
        for (index, ball) in balls.enumerated() {
            restFrames[index] = ball.velocity.length < 0.06 ? restFrames[index] + 1 : 0
            if ball.position.y < -2 || restFrames[index] > 260 {
                recycle(ball)
                restFrames[index] = 0
            }
        }
    }

    func drawStage() {
        fill(Color(hex: 0x161C26))
        material(.dielectric(roughness: 0.9))
        drawGround(size: 26, thickness: 0.14)

        // The tray lights with its load: an empty pan is nearly dark, a full
        // one glows.
        let load = min(1.0, Double(tray?.touching.count ?? 0) / 6)
        fill(Color.mix(Color(hex: 0x252D3B), Color(hex: 0x2F8E76), load))
        material(.dielectric(roughness: 0.55))
        for body in world.bodies where body.kind == .static {
            // The tray's slabs; the hoop's rim is a compound and draws as the
            // torus below.
            guard case .box(let w, let h, let d) = body.collider else { continue }
            withBody(body) { drawBox(width: w, height: h, depth: d) }
        }
    }

    func drawHoop() {
        // Lit while a ball is crossing, and flaring for a moment after a score.
        let inside = hoop.map { !$0.touching.isEmpty } ?? false
        let heat = max(scoreGlow, inside ? 1 : 0)
        fill(Color.mix(Color(hex: 0xB8C0CC), Color(hex: 0xF2A93B), heat))
        material(.metal(roughness: 0.3 - 0.15 * heat))
        withState {
            translate(hoopCenter)
            drawTorus(radius: hoopRadius, tube: hoopTube)
        }
    }

    /// Each knock as a ring in the air where it landed, spreading and fading.
    /// `withBillboard` puts 2D drawing at a world point with the scene's own
    /// depth, so a ring behind a ball is hidden by it.
    func drawKnocks() {
        noFill()
        for knock in knocks {
            let t = knock.age / 0.55
            let radius = (4 + knock.strength * 2.2) * (0.5 + t) * scale
            withBillboard(at: knock.at) {
                stroke(Color(hex: 0xF7F3E8).withAlpha((1 - t) * 0.8))
                strokeWeight(2 * (1 - t) * scale)
                drawCircle(0, 0, radius)
            }
        }
        noStroke()
    }
}
