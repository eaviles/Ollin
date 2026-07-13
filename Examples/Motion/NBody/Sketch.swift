import Ollin

/// Two toy galaxies on a grazing pass: thousands of light bodies orbiting two
/// heavy centers, every one pulling on every other through `NBody`. As the
/// disks close, tides take over. Each galaxy peels long streamer arms off the
/// other, stars are flung into the void, and what is left settles into a
/// tangled merger. Give it a minute; the drama unfolds slowly.
///
/// The forces run through a quadtree, so a few thousand bodies stay cheap,
/// and the whole run is seeded: restart it and the same collision replays,
/// down to the last flung star.
@main
final class NBodyCollision: Sketch {
    private var system: NBody!

    override func setup() {
        // Two spinning disks released at the far point of a bound mutual
        // orbit, moving sideways to each other: gravity swings them together
        // into a rim-grazing pass half an orbit later, and they stay bound,
        // so the tails are followed by a slow return and merger.
        let a = NBody.disk(count: 1400, center: Vector2(330, 730), radius: 230,
                           centralMass: 420_000, jitter: 0.04, velocity: Vector2(5.9, 7.0), seed: 4)
        let b = NBody.disk(count: 900, center: Vector2(790, 340), radius: 175,
                           centralMass: 260_000, spin: -1, jitter: 0.04,
                           velocity: Vector2(-9.6, -11.3), seed: 9)
        system = a
        system.bodies += b.bodies
        system.softening = 6
    }

    override func draw() {
        background(Color(hex: 0x07080D))
        system.step()

        let bodies = system.bodies
        withState {
            // Keep the camera midway between the two cores so the encounter
            // stays framed through the pass and the merger.
            let anchor = (bodies[0].position + bodies[1401].position) / 2
            translate(width / 2 - anchor.x, height / 2 - anchor.y)

            // Additive points, one hue per galaxy: where arms cross, they glow.
            blendMode(.add)
            noStroke()
            for (i, body) in bodies.enumerated() {
                guard body.mass < 1000 else { continue } // the two cores draw below
                let home = i <= 1400
                fill((home ? Color(hex: 0x5AA7D4) : Color(hex: 0xE0A458)).withAlpha(0.75))
                drawCircle(center: body.position, radius: 2.1)
            }
            for body in bodies where body.mass >= 1000 {
                fill(Color.white.withAlpha(0.9))
                drawCircle(center: body.position, radius: 6)
            }
        }

        let seconds = Int(Double(frameCount) / 60)
        drawCaption("\(bodies.count) bodies, one rule. \(seconds)s in")
    }
}
