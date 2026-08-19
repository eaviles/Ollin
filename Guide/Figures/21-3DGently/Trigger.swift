// figure: frame=308
//
// Guide listing (Chapter 21): contact events and sensor bodies. The hoop is a
// solid rim of beads with a sensor disc filling the ring, so `hoop.entered`
// counts the balls that drop clean through and the ring lights while one is
// crossing; the tray is a sensor too, lit by `touching.count`, which keeps
// counting balls that have settled and gone to sleep in it; and every knock in
// `world.contacts` rings the air at the speed it landed. Staged drops, no
// random anywhere, so the moment replays identically.
import Ollin
import OllinPhysics

final class Trigger: Sketch {
    let world = World3D()
    var hoop: Body3D?
    var tray: Body3D?
    var score = 0
    var scoreGlow = 0.0
    var knocks: [(at: Vector3, strength: Double, age: Double)] = []

    let hoopCenter = Vector3(0, 3.2, 0)
    let hoopRadius = 1.1, hoopTube = 0.17, ballRadius = 0.22
    let trayHalf = 1.5
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0xD94F70),
        Color(hex: 0x8D92E0), Color(hex: 0x72BFB2),
    ]

    override func setup() {
        world.ground = 0
        world.bounce = 0.35

        var rim: [Collider3D.Part] = []
        for index in 0 ..< 28 {
            let angle = Double(index) / 28 * .tau
            rim.append(.part(.sphere(radius: hoopTube),
                             at: Vector3(cos(angle), 0, sin(angle)) * hoopRadius))
        }
        world.addBody(.compound(rim), at: hoopCenter, kind: .static,
                      friction: 0.3, restitution: 0.5)
        hoop = world.addBody(.cylinder(height: 0.5, radius: hoopRadius - hoopTube),
                             at: hoopCenter, isSensor: true)

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

    /// Staged releases, no random: one ball every so many frames from the same
    /// height, so the tray has filled by the time the last one is crossing.
    let releases: [(frame: Int, x: Double, z: Double)] = [
        (2, 0.10, 0.05), (45, -0.30, 0.35), (90, 0.95, -0.20),
        (135, -0.15, -0.40), (180, 0.35, 0.30), (260, -0.12, 0.16),
    ]

    func releaseDue() {
        for (index, release) in releases.enumerated()
        where release.frame == frameCount {
            let ball = world.addBody(.sphere(radius: ballRadius),
                                     at: Vector3(release.x, 5.4, release.z),
                                     density: 1.4, friction: 0.35,
                                     restitution: 0.4)
            ball.userData = palette[index % palette.count]
        }
    }

    override func draw() {
        background(Color(hex: 0x0A0D14))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(1.4, 4.0, 7.6), target: Vector3(0, 2.4, 0))

        releaseDue()
        world.step(dt: deltaTime)

        if let hoop {
            score += hoop.entered.count
            if !hoop.entered.isEmpty { scoreGlow = 1 }
        }
        scoreGlow = max(0, scoreGlow - deltaTime * 1.6)
        for contact in world.contacts where contact.phase == .began {
            guard contact.speed > 1.4 else { continue }
            knocks.append((contact.point, contact.speed, 0))
        }
        for index in knocks.indices { knocks[index].age += deltaTime }
        knocks.removeAll { $0.age > 0.55 }

        fill(Color(hex: 0x161C26))
        material(.dielectric(roughness: 0.9))
        withState {
            translate(0, -0.07, 0)
            drawBox(width: 26, height: 0.14, depth: 26)
        }

        let load = min(1.0, Double(tray?.touching.count ?? 0) / 6)
        fill(Color.mix(Color(hex: 0x252D3B), Color(hex: 0x2F8E76), t: load))
        material(.dielectric(roughness: 0.55))
        for body in world.bodies where body.kind == .static {
            guard case .box(let w, let h, let d) = body.collider else { continue }
            withBody(body) { drawBox(width: w, height: h, depth: d) }
        }

        let inside = hoop.map { !$0.touching.isEmpty } ?? false
        let heat = max(scoreGlow, inside ? 1 : 0)
        fill(Color.mix(Color(hex: 0xB8C0CC), Color(hex: 0xF2A93B), t: heat))
        material(.metal(roughness: 0.3 - 0.15 * heat))
        withState {
            translate(hoopCenter)
            drawTorus(radius: hoopRadius, tube: hoopTube)
        }

        for body in world.bodies where body.kind == .dynamic {
            fill(body.userData as? Color ?? .white)
            material(.dielectric(roughness: 0.28))
            withBody(body) { drawSphere(radius: ballRadius) }
        }

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
