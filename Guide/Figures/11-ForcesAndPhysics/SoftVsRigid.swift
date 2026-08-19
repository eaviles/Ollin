// figure: frame=150
//
// Guide diagram (Chapter 11): the two kinds of body, dropped and settled.
// Left, a soft blob of particles and springs squashes where it lands. Right,
// rigid boxes fall, tip, and rest without losing a corner.
import Ollin
import OllinPhysics

final class SoftVsRigid: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    let leftPanel = Rectangle(x: 50, y: 60, width: 370, height: 380)
    let rightPanel = Rectangle(x: 470, y: 60, width: 370, height: 380)

    let softWorld = World()
    let rigidWorld = World()
    var rim: [Particle] = []

    override func setup() {
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
        rigidWorld.bounce = 0.08
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
        background(Color(hex: 0xF7F5F1))
        textSize(17)
        softWorld.step(dt: deltaTime)
        rigidWorld.step(dt: deltaTime)

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
                fill(Color(hex: 0x2B2B2B, alpha: 0.14))
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
