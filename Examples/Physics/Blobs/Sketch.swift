import Foundation
import Ollin
import OllinPhysics

/// Soft-body blobs built entirely from `OllinPhysics` springs: each blob is a
/// hub particle with spokes out to a ring of rim particles, plus springs around
/// the rim. The spokes are slack enough to let the blob squish, the rim springs
/// hold it roughly round, and the rim particles collide so blobs don't pass
/// through each other or the walls.
///
/// They float weightlessly and drift, bouncing off the edges — and the **cursor
/// shoves them around**: particles near the mouse are pushed away, so you sweep
/// through the field and the blobs squish, scatter, and flow back. Move the mouse
/// over the window to play with them.
///
/// This is the springs-and-collision showcase, and it renders each blob as a
/// smooth filled `drawCurve` through its rim particles — so the soft-body outline
/// rides Ollin's curved-shape path while the motion comes from the simulation.
@main
final class Blobs: Sketch {
    let world = World()

    /// One soft body: the particles that make it and the color it draws in.
    final class Blob {
        let rim: [Particle]
        let color: Color
        init(rim: [Particle], color: Color) {
            self.rim = rim
            self.color = color
        }
        var outline: [Vector2] { rim.map(\.position) }
        var center: Vector2 { rim.reduce(.zero) { $0 + $1.position } / Double(rim.count) }
    }

    var blobs: [Blob] = []

    let palette: [Color] = [
        Color(red: 0.96, green: 0.44, blue: 0.40),   // coral
        Color(red: 0.98, green: 0.76, blue: 0.30),   // amber
        Color(red: 0.36, green: 0.78, blue: 0.72),   // teal
        Color(red: 0.62, green: 0.52, blue: 0.90),   // violet
        Color(red: 0.66, green: 0.84, blue: 0.36),   // lime
        Color(red: 0.42, green: 0.72, blue: 0.94),   // sky
        Color(red: 0.94, green: 0.58, blue: 0.74),   // rose
        Color(red: 0.98, green: 0.62, blue: 0.36),   // tangerine
        Color(red: 0.55, green: 0.80, blue: 0.86)    // aqua
    ]

    override func setup() {
        world.gravity = .zero              // weightless — they float and drift
        world.drag = 0                     // keep drifting forever
        world.bounce = 0.85
        world.collisions = true
        world.iterations = 12              // soft bodies want a few passes to hold
        world.bounds = bounds

        for color in palette {
            let radius = random(58, 104) * scale
            let at = Vector2(random(radius, width - radius), random(radius, height - radius))
            let drift = Vector2(angle: random(.tau), length: random(0.5, 1.6) * scale)
            blobs.append(makeBlob(at: at, radius: radius, color: color, drift: drift))
        }
    }

    /// Build a blob: a hub plus a ring of rim particles, wired with spokes and
    /// rim springs, given an initial drift, all added to the world.
    func makeBlob(at center: Vector2, radius: Double, color: Color, drift: Vector2) -> Blob {
        let sides = 16
        let hub = world.addParticle(at: center, radius: 0, mass: 3)
        hub.push(drift)

        let rimRadius = radius * sin(.pi / Double(sides))   // adjacent rims just touch
        var rim: [Particle] = []
        for s in 0 ..< sides {
            let angle = Double(s) / Double(sides) * .tau
            let p = world.addParticle(at: center + Vector2(angle: angle, length: radius),
                                      radius: rimRadius, mass: 1)
            p.push(drift)
            rim.append(p)
            world.connect(hub, p, stiffness: 0.2)            // spoke (springy)
        }
        for s in 0 ..< sides {
            world.connect(rim[s], rim[(s + 1) % sides], stiffness: 0.6)   // rim ring
        }
        return Blob(rim: rim, color: color)
    }

    override func draw() {
        background(Color(white: 0.1))
        repelFromCursor()
        world.step(dt: deltaTime)

        strokeWeight(2 * scale)
        for blob in blobs {
            fill(blob.color)
            stroke(Color(white: 0, alpha: 0.25))
            drawCurve(blob.outline, closed: true)

            // A soft highlight so the blobs read as glossy.
            noStroke()
            fill(Color(white: 1, alpha: 0.18))
            drawCircle(center: blob.center + Vector2(0, -8 * scale), radius: 10 * scale)
        }
    }

    /// Push particles away from the mouse, falling off with distance, so sweeping
    /// the cursor scatters the blobs.
    func repelFromCursor() {
        guard mouseX != 0 || mouseY != 0 else { return }   // mouse hasn't moved yet
        let cursor = Vector2(mouseX, mouseY)
        let reach = 180 * scale
        for p in world.particles {
            let away = p.position - cursor
            let d = away.length
            guard d > 0, d < reach else { continue }
            let falloff = 1 - d / reach
            p.push(away.normalized * (falloff * falloff * 9 * scale))
        }
    }
}
