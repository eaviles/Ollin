import Foundation
import Ollin
import OllinPhysics

/// The force API in one windy yard. A gusting wind leans on every loose shape
/// through `applyForce`, so the light leaves skitter while the heavy crates
/// barely shuffle. **Click to kick** the nearest shape away from the cursor
/// with `applyImpulse` (an impulse is mass times velocity change, so the same
/// kick launches a leaf and only nudges a crate). A paddle spun up by
/// `applyTorque` bats whatever drifts through it. And a white sweeper of
/// `kind: .kinematic` plows along the floor, moved only by the velocity it is
/// given each frame and unstoppable by wind, kicks, or collisions. Space
/// resets.
///
/// In the corner hangs a pinned cloth: a lattice of particles (the pole column
/// held by `pin()`) whose springs are tinted by `Spring.strain`, teal where
/// compressed, coral where stretched, so the wind load is visible traveling
/// through the weave.
///
/// `World.pixelsPerMeter` rides a parameter. It maps sketch points onto the rigid
/// solver's meters, so raising it makes every collider smaller in meters and
/// therefore lighter, and the same wind and kick numbers toss the shapes much
/// harder; the scene rebuilds when it changes, because the walls and masses
/// are all sized through the mapping. The particle side works directly in
/// points, so the cloth ignores the parameter entirely.
@main
final class Forces: Sketch {
    @Param(25 ... 400, icon: "ruler", group: "World") var pixelsPerMeter = 100.0
    @Param(0 ... 2, icon: "wind", group: "Wind") var windStrength = 1.0

    let world = World()

    /// The paddle `applyTorque` spins.
    var paddle: Body?
    /// The kinematic sweeper, driven by velocity alone.
    var sweeper: Body?

    /// A click's fading ring, so the kick has a visible source.
    struct Kick { let at: Vector2; let born: Double }
    var kicks: [Kick] = []

    /// A shape's geometry (in body-local space) plus its color, hung off
    /// `Body.userData`, the same pattern the other rigid examples use.
    enum Form {
        case box(Double, Double)
        case ball(Double)
        case polygon([Vector2])
    }
    final class Look {
        let form: Form
        let color: Color
        init(_ form: Form, _ color: Color) { self.form = form; self.color = color }
    }

    /// Random picks for the leaves.
    let palette: [Color] = [
        Color(red: 0.95, green: 0.49, blue: 0.34), Color(red: 0.97, green: 0.71, blue: 0.30),
        Color(red: 0.45, green: 0.77, blue: 0.71), Color(red: 0.55, green: 0.57, blue: 0.88),
        Color(red: 0.88, green: 0.53, blue: 0.70), Color(red: 0.62, green: 0.80, blue: 0.42)
    ]
    let crateColor = Color(red: 0.62, green: 0.50, blue: 0.38)
    let paddleColor = Color(red: 0.55, green: 0.57, blue: 0.88)
    let restColor = Color(white: 0.55)
    let tautColor = Color(red: 0.95, green: 0.49, blue: 0.34)
    let slackColor = Color(red: 0.45, green: 0.77, blue: 0.71)

    /// Where the turnstile hinges (also anchors its label).
    var hubPoint: Vector2 { Vector2(width * 0.64, height * 0.44) }
    /// Where the cloth hangs.
    var polePoint: Vector2 { Vector2(width * 0.10, height * 0.10) }

    override func setup() {
        world.gravity = Vector2(0, 700)    // light enough for the wind to matter
        world.restitution = 0.25
        world.pixelsPerMeter = pixelsPerMeter
        world.bounds = bounds
        build()
        noStroke()
    }

    func build() {
        kicks.removeAll()

        // Leaves: light shapes the wind can carry.
        for _ in 0 ..< 40 {
            let at = Vector2(random(width * 0.06, width * 0.94),
                             random(height * 0.10, height * 0.72))
            let form = leafForm()
            let body = world.addBody(collider(for: form), at: at,
                                     density: 0.2, friction: 0.4,
                                     restitution: random(0.1, 0.35))
            body.angle = random(.tau)
            body.angularVelocity = random(-3, 3)
            body.userData = Look(form, palette[Int(random(Double(palette.count)))])
        }

        // Crates: the same wind and the same kicks, many times the mass.
        for i in 0 ..< 4 {
            let w = random(96, 132) * scale
            let h = random(72, 104) * scale
            let body = world.addBody(.box(width: w, height: h),
                                     at: Vector2(width * (0.2 + 0.2 * Double(i)), height * 0.86),
                                     density: 1.2, friction: 0.6, restitution: 0.05)
            body.userData = Look(.box(w, h), crateColor)
        }

        // The turnstile: a paddle on a free hinge, spun up by applyTorque each
        // frame until it reaches cruising speed.
        let hub = world.addBody(.circle(radius: 12 * scale), at: hubPoint, kind: .static)
        hub.userData = Look(.ball(12 * scale), Color(white: 0.45))
        let blade = world.addBody(.box(width: 330 * scale, height: 20 * scale), at: hubPoint,
                                  density: 0.8, friction: 0.3)
        blade.userData = Look(.box(330 * scale, 20 * scale), paddleColor)
        world.connect(hub, blade, .revolute(at: hubPoint))
        paddle = blade

        // The sweeper: kinematic, so forces and contacts never move it; it
        // goes only where the velocity set in draw() sends it.
        let broom = world.addBody(.box(width: 46 * scale, height: 180 * scale),
                                  at: Vector2(width / 2, height - 100 * scale),
                                  kind: .kinematic, friction: 0.8)
        broom.userData = Look(.box(46 * scale, 180 * scale), Color(white: 0.95))
        sweeper = broom

        buildCloth()
    }

    /// A lattice of particles pinned along its pole edge, wired with structural
    /// and shear springs. The wind blows it through `Particle.applyForce`; the
    /// springs are drawn tinted by `Spring.strain`.
    func buildCloth() {
        let columnCount = 13, rowCount = 8
        let spacing = width * 0.015
        var grid: [[Particle]] = []
        for r in 0 ..< rowCount {
            var row: [Particle] = []
            for c in 0 ..< columnCount {
                let p = world.addParticle(at: polePoint + Vector2(Double(c) * spacing,
                                                                 Double(r) * spacing))
                if c == 0 { p.pin() }        // the pole edge holds still
                row.append(p)
            }
            grid.append(row)
        }
        for r in 0 ..< rowCount {
            for c in 0 ..< columnCount {
                if c + 1 < columnCount { world.connect(grid[r][c], grid[r][c + 1], stiffness: 0.95) }
                if r + 1 < rowCount { world.connect(grid[r][c], grid[r + 1][c], stiffness: 0.95) }
                if c + 1 < columnCount, r + 1 < rowCount {
                    world.connect(grid[r][c], grid[r + 1][c + 1], stiffness: 0.4)
                    world.connect(grid[r][c + 1], grid[r + 1][c], stiffness: 0.4)
                }
            }
        }
    }

    /// A random light shape, sized in canvas points.
    func leafForm() -> Form {
        let s = random(11, 20) * scale
        switch Int(random(3)) {
        case 0:  return .box(s * 2, random(0.5, 0.9) * s * 1.6)
        case 1:  return .ball(s)
        default:
            let sides = Int(random(3, 5.99))
            let points = (0 ..< sides).map { i -> Vector2 in
                let angle = Double(i) / Double(sides) * .tau + random(-0.2, 0.2)
                return Vector2(angle: angle, length: s * random(0.8, 1.15))
            }
            return .polygon(points)
        }
    }

    func collider(for form: Form) -> Collider {
        switch form {
        case .box(let w, let h):   return .box(width: w, height: h)
        case .ball(let r):         return .circle(radius: r)
        case .polygon(let points): return .polygon(points)
        }
    }

    /// The shared wind: a unit-scale vector that gusts and lulls, with a slight
    /// lift so the leaves loft instead of only piling. The prevailing direction
    /// turns right around on a slower cycle, so the yard is swept both ways
    /// rather than emptying against one wall and staying there.
    func gust() -> Vector2 {
        let swell = Swift.max(0, sin(time * 0.5) + 0.4 * sin(time * 1.7)) / 1.4
        let strength = 0.3 + 0.7 * swell
        let across = strength * sin(time * 0.12)
        return Vector2(across, -0.18 * strength)
    }

    /// Kick the nearest dynamic body away from the click. The impulse is a raw
    /// momentum change, not scaled by mass, so a leaf flies and a crate nudges.
    override func mousePressed() {
        let cursor = mouse
        var nearest: Body?
        var nearestDistance = Double.infinity
        for body in world.bodies where body.kind == .dynamic {
            let d = body.position.distance(to: cursor)
            if d < nearestDistance { nearestDistance = d; nearest = body }
        }
        guard let body = nearest else { return }
        let offset = body.position - cursor
        let aim = offset.length > 0.001 ? offset / offset.length : Vector2(0, -1)
        // Forces and impulses push a mass, and drawn area stands in for mass
        // here, so the magnitudes carry scale squared to keep their feel at
        // export scales.
        body.applyImpulse(aim * (22 * scale * scale))
        kicks.append(Kick(at: cursor, born: time))
    }

    override func keyPressed() {
        if key == " " { reset() }
    }

    /// Rebuild everything under the current parameter values. Reassigning `bounds`
    /// rebuilds the walls, which are also sized through `pixelsPerMeter`.
    func reset() {
        world.removeAll()
        world.pixelsPerMeter = pixelsPerMeter
        world.bounds = bounds
        paddle = nil
        sweeper = nil
        build()
    }

    override func draw() {
        background(Color(white: 0.12))

        // The parameter remaps points onto the solver's meters; every wall and mass
        // is sized through the mapping, so a change rebuilds the scene.
        if world.pixelsPerMeter != pixelsPerMeter { reset() }

        // The wind: a steady per-frame force on every dynamic body, and on
        // every cloth particle (whose masses are 1, so the force is smaller).
        let wind = gust() * windStrength
        for body in world.bodies where body.kind == .dynamic {
            body.applyForce(wind * (10 * scale * scale))
        }
        for particle in world.particles {
            particle.applyForce(wind * (850 * scale))
        }

        // Spin the paddle up to cruising speed, then let it coast.
        if let paddle, paddle.angularVelocity < 3.4 {
            paddle.applyTorque(6)
        }
        driveSweeper()

        world.advance(by: deltaTime)

        drawBodies()
        drawCloth()
        drawKicks()
        drawCaptions()
    }

    /// Steer the kinematic sweeper along its patrol by velocity alone: aim it
    /// at a moving target so it tracks smoothly without drifting off its lane.
    func driveSweeper() {
        guard let sweeper else { return }
        let target = Vector2(width / 2 + sin(time * 0.5) * width * 0.34,
                             height - 100 * scale)
        sweeper.velocity = (target - sweeper.position) * 6
        sweeper.angularVelocity = 0
    }

    func drawBodies() {
        for body in world.bodies {
            guard let look = body.userData as? Look else { continue }
            withState {
                translate(body.position)
                rotate(body.angle)
                fill(look.color)
                switch look.form {
                case .box(let w, let h):
                    drawRect(center: .zero, width: w, height: h, cornerRadius: 3 * scale)
                case .ball(let r):
                    drawCircle(center: .zero, radius: r)
                case .polygon(let points):
                    drawPolygon(points)
                }
            }
        }
    }

    func drawCloth() {
        // The pole the pinned column hangs from.
        stroke(Color(white: 0.5))
        strokeWeight(6 * scale)
        drawLine(polePoint + Vector2(0, -30 * scale), polePoint + Vector2(0, 190 * scale))

        // Springs tinted by strain: teal compressed, coral stretched.
        strokeWeight(2 * scale)
        for spring in world.springs {
            let t = Swift.max(-1, Swift.min(1, spring.strain / 0.12))
            let color = t >= 0
                ? restColor.mixed(with: tautColor, t)
                : restColor.mixed(with: slackColor, -t)
            stroke(color)
            drawLine(spring.a.position, spring.b.position)
        }
        noStroke()
    }

    func drawKicks() {
        kicks.removeAll { time - $0.born > 0.5 }
        noFill()
        for kick in kicks {
            let age = (time - kick.born) / 0.5
            stroke(Color(white: 1, alpha: (1 - age) * 0.6))
            strokeWeight(2.5 * scale)
            drawCircle(center: kick.at, radius: (18 + age * 240) * scale)
        }
        noStroke()
    }

    func drawCaptions() {
        withState {
            textFont(.system)
            textAlign(.center)
            noStroke()

            // The parameter caption: what pixelsPerMeter changes.
            textSize(width * 0.0165)
            fill(Color(white: 0.7))
            drawText("pixelsPerMeter \(Int(world.pixelsPerMeter.rounded())): raise it and the shapes read lighter, so the same wind carries them further",
                     at: Vector2(width / 2, height * 0.045))

            // Station labels.
            textSize(width * 0.015)
            fill(Color(white: 0.55))
            drawText("applyTorque", at: hubPoint + Vector2(0, 200 * scale))
            drawText("pin() + strain", at: polePoint + Vector2(width * 0.06, 290 * scale))
            if let sweeper {
                drawText(".kinematic", at: sweeper.position + Vector2(0, -115 * scale))
            }
        }
    }
}
