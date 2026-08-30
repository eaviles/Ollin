// figure: frame=300 themed
//
// Guide diagram (Chapter 11): three motion systems you hold and step yourself.
// Left, an IK chain bends so its tip strains for a target while its base stays
// planted. Middle, a double pendulum traces the tangle only two arms can make.
// Right, a few hundred bodies pulling on each other settle into a disk.
import Ollin
import OllinDiagram

final class Articulated: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var trailInk: Color { theme.ink(0.35) }
    var accent: Color { theme.accent }

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 340)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 340)

    var arm = Articulated.makeArm()
    var pendulum = Articulated.makePendulum()
    var galaxy = Articulated.makeGalaxy()

    static func makeArm() -> IKChain {
        IKChain(from: Vector2(90, 370), segments: 12, length: 24, angle: -.pi / 2)
    }
    static func makePendulum() -> DoublePendulum {
        DoublePendulum(length1: 58, length2: 58, angle1: 2.1, angle2: 2.5)
    }
    static func makeGalaxy() -> NBody {
        NBody.disk(count: 500, center: Vector2(702, 240), radius: 100,
                   jitter: 0.03, seed: 5)
    }

    var target = Vector2.zero
    var pivot = Vector2.zero
    var trail: [Vector2] = []

    override func setup() {
        arm = Articulated.makeArm()
        pendulum = Articulated.makePendulum()
        galaxy = Articulated.makeGalaxy()
        trail = []
        target = Vector2(left.x + 200, left.y + 70)
        pivot = Vector2(middle.x + 126, middle.y + 130)
        galaxy.softening = 2
    }

    override func draw() {
        background(paper)
        textSize(17)

        // All three advance by a fixed step, so the figure reproduces exactly.
        arm.reach(toward: target)
        pendulum.advance()
        trail.append(pendulum.bob2)
        galaxy.advance()

        frame(left, title: "a chain that reaches")
        noFill()
        stroke(ink)
        strokeWeight(5)
        strokeCap(.round)
        drawPolyline(arm.joints)
        noStroke()
        fill(ink)
        for joint in arm.joints {
            drawCircle(center: joint, radius: 4)
        }
        drawRect(center: arm.base, width: 22, height: 9)
        noFill()
        stroke(accent)
        strokeWeight(2.5)
        drawCircle(center: target, radius: 10)

        frame(middle, title: "chaos from two arms")
        withState {
            translate(pivot)
            noFill()
            stroke(trailInk)
            strokeWeight(1.5)
            if trail.count > 1 { drawPolyline(trail) }
            stroke(ink)
            strokeWeight(4)
            drawLine(.zero, pendulum.bob1)
            drawLine(pendulum.bob1, pendulum.bob2)
            noStroke()
            fill(ink)
            drawCircle(center: pendulum.bob1, radius: 6)
            fill(accent)
            drawCircle(center: pendulum.bob2, radius: 8)
        }

        frame(right, title: "gravity at scale")
        // A streak along each body's velocity, so the disk's circulation reads.
        stroke(theme.ink(0.75))
        strokeWeight(1.4)
        for body in galaxy.bodies.dropFirst() {
            drawLine(body.position - body.velocity * 0.1, body.position)
        }
        noStroke()
        fill(accent)
        drawCircle(center: galaxy.bodies[0].position, radius: 6)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("three systems you hold on the sketch and step yourself",
                 width / 2, 462)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
