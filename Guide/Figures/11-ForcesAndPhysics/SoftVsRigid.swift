// figure: frame=150 themed
//
// Guide diagram (Chapter 11): the two kinds of body, dropped and settled.
// Left, a soft blob of particles and springs squashes where it lands. Right,
// rigid boxes fall, tip, and rest without losing a corner.
import Ollin
import OllinDiagram
import OllinPhysics

final class SoftVsRigid: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.4) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    let leftPanel = Rectangle(x: 50, y: 60, width: 370, height: 380)
    let rightPanel = Rectangle(x: 470, y: 60, width: 370, height: 380)

    var softWorld = World()
    var rigidWorld = World()
    var rim: [Particle] = []

    override func setup() {
        softWorld = World()
        rigidWorld = World()
        rim = []
        // The soft side: a blob, a hub with spokes out to a springy rim.
        softWorld.gravity = Vector2(0, 2200)
        softWorld.bounds = leftPanel
        let center = Vector2(leftPanel.x + 185, leftPanel.y + 120)
        let radius = 82.0
        let sides = 16
        let hub = softWorld.addParticle(at: center, mass: 6)
        for s in 0 ..< sides {
            let angle = Double(s) / Double(sides) * .tau
            let p = softWorld.addParticle(at: center + Vector2(angle: angle, length: radius),
                                          radius: 8)
            rim.append(p)
            softWorld.connect(hub, p, stiffness: 0.08)
        }
        for s in 0 ..< sides {
            softWorld.connect(rim[s], rim[(s + 1) % sides], stiffness: 0.5)
        }

        // The rigid side: four boxes, one dropped tilted from higher up.
        rigidWorld.gravity = Vector2(0, 1500)
        rigidWorld.restitution = 0.08
        rigidWorld.bounds = rightPanel
        let floor = rightPanel.y + rightPanel.height
        let mid = rightPanel.x + 175
        rigidWorld.addBody(.box(width: 110, height: 54), at: Vector2(mid - 10, floor - 27))
        rigidWorld.addBody(.box(width: 110, height: 54), at: Vector2(mid + 14, floor - 83))
        rigidWorld.addBody(.box(width: 110, height: 54), at: Vector2(mid - 4, floor - 139))
        let tipped = rigidWorld.addBody(.box(width: 110, height: 54),
                                        at: Vector2(mid + 96, floor - 300))
        tipped.angle = 0.55
    }

    override func draw() {
        background(paper)
        textSize(17)
        softWorld.advance(by: deltaTime)
        rigidWorld.advance(by: deltaTime)

        frame(leftPanel, title: "soft: particles and springs, it gives")
        noStroke()
        fill(accent)
        drawCurve(rim.map(\.position), closed: true)
        fill(ink)
        for p in rim {
            drawCircle(center: p.position, radius: 3.5)
        }

        frame(rightPanel, title: "rigid: bodies that keep their shape")
        for body in rigidWorld.bodies {
            withState {
                translate(body.position)
                rotate(body.angle)
                fill(theme.ink(0.14))
                stroke(ink)
                strokeWeight(2.5)
                drawRect(center: .zero, width: 110, height: 54, cornerRadius: 3)
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one gives where it lands, one keeps its corners", width / 2, 495)
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
