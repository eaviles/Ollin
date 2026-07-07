import Ollin

/// Steering behaviors: creatures moved by composable forces. A troop of
/// followers rides a wavy loop (`follow(path:)`), wanderers roam the middle
/// leaving trails (`wander` plus `contain`), and one pursuer hunts the lead
/// follower by aiming where it *will* be (`pursue`). Every motion here is the
/// same move with a different target: aim at full speed toward what you want,
/// subtract where you're already going, cap the turn.
@main
final class Steering: Sketch {
    private var path: [Vector2] = []
    private var followers: [Vehicle] = []
    private var wanderers: [Vehicle] = []
    private var trails: [[Vector2]] = []
    private var pursuer: Vehicle?

    override func setup() {
        seed(11)

        // A wavy closed loop built on looping noise, so it meets itself.
        let center = Vector2(width / 2, height / 2)
        path = (0 ..< 160).map { i in
            let t = Double(i) / 160
            let wobble = signedNoise(0, loop: t, radius: 1.6) * 90 * scale
            return center + Vector2(angle: t * .tau) * (360 * scale + wobble)
        }

        followers = (0 ..< 7).map { i in
            let start = path[i * 20]
            return Vehicle(at: start, velocity: Vector2(angle: Double(i), length: 2),
                           maxSpeed: (3.4 + 0.2 * Double(i % 3)) * scale, maxForce: 0.16 * scale,
                           seed: UInt64(i))
        }
        wanderers = (0 ..< 5).map { i in
            Vehicle(at: center + Vector2(angle: Double(i) * 1.3, length: 120 * scale),
                    velocity: Vector2(angle: Double(i) * 2.1, length: 2),
                    maxSpeed: 2.6 * scale, maxForce: 0.1 * scale, seed: UInt64(100 + i))
        }
        trails = wanderers.map { _ in [] }
        pursuer = Vehicle(at: center, maxSpeed: 3.1 * scale, maxForce: 0.09 * scale, seed: 42)
    }

    override func draw() {
        background(Color(hex: 0x0E1016))

        // The loop the followers ride, drawn as a faint corridor.
        noFill()
        stroke(Color(hex: 0x2A3040))
        strokeWeight(30 * scale)
        drawPolygon(path)
        stroke(Color(hex: 0x4A5468))
        strokeWeight(1.5 * scale)
        drawPolygon(path)

        // Wanderers roam the middle and leave trails.
        for (i, creature) in wanderers.enumerated() {
            creature.applyForce(creature.wander(radius: 30 * scale, distance: 90 * scale))
            creature.applyForce(creature.contain(in: bounds.inset(by: .all(220 * scale))) * 1.6)
            creature.step()
            trails[i].append(creature.position)
            if trails[i].count > 90 { trails[i].removeFirst() }
        }
        noFill()
        strokeWeight(2 * scale)
        for (i, trail) in trails.enumerated() where trail.count > 1 {
            stroke(Color(hue: 0.52 + Double(i) * 0.03, saturation: 0.5, brightness: 0.9).withAlpha(0.35))
            drawPolyline(trail)
        }
        noStroke()
        for (i, creature) in wanderers.enumerated() {
            fill(Color(hue: 0.52 + Double(i) * 0.03, saturation: 0.5, brightness: 0.95))
            drawVehicle(creature, size: 10 * scale)
        }

        // Followers stay in the corridor; each also keeps a little personal
        // space so the troop reads as creatures, not a train.
        for creature in followers {
            creature.applyForce(creature.follow(path: path, radius: 14 * scale,
                                                lookAhead: 60 * scale, closed: true))
            creature.applyForce(creature.separate(from: followers, radius: 26 * scale) * 1.2)
            creature.step()
        }
        for (i, creature) in followers.enumerated() {
            fill(Color(hue: 0.09 + Double(i) * 0.012, saturation: 0.72, brightness: 0.97))
            drawVehicle(creature, size: 12 * scale)
        }

        // The pursuer aims where the lead follower will be, not where it is.
        if let pursuer, let prey = followers.first {
            pursuer.applyForce(pursuer.pursue(prey))
            pursuer.step()
            fill(Color(hex: 0xE8586B))
            drawVehicle(pursuer, size: 15 * scale)
        }
    }
}
