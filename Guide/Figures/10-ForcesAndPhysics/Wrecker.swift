// figure: frame=62
//
// Guide payoff (Chapter 10): a wrecking ball. A chain of rigid links hangs
// from a peg by revolute joints and ends in a heavy ball. It starts swung
// up to one side, so gravity launches it into the brick tower. Hold the
// mouse near the ball or a link to drag it, release to let it fly, and
// press space to rebuild.
import Ollin
import OllinPhysics

final class Wrecker: Sketch {
    let world = World()

    var bricks: [Body] = []
    var links: [Body] = []
    var ball: Body?
    var held: Joint?
    var anchor = Vector2.zero

    let brickSize = Vector2(150, 54)
    let ballRadius = 56.0
    let linkStep = Vector2(angle: .pi / 2 + 1.65, length: 91)   // up and to the left
    let rows = [
        Color(hex: 0xE07A5F), Color(hex: 0xF2CC8F),
        Color(hex: 0x81B29A), Color(hex: 0x8187B9),
    ]

    override func setup() {
        world.gravity = Vector2(0, 2600)
        world.bounce = 0.05
        world.bounds = bounds
        build()
        strokeCap(.round)
    }

    func build() {
        bricks.removeAll()
        links.removeAll()

        // The tower: a single column of bricks standing on the floor.
        for row in 0 ..< 9 {
            let y = height - 20 - (Double(row) + 0.5) * (brickSize.y + 2)
            let brick = world.addBody(.box(width: brickSize.x, height: brickSize.y),
                                      at: Vector2(width * 0.68, y), friction: 0.6)
            bricks.append(brick)
        }

        // The chain: a fixed peg, six links hinged end to end, then the ball.
        anchor = Vector2(width * 0.64, 130)
        let peg = world.addBody(.circle(radius: 12), at: anchor, kind: .static)
        let half = linkStep * 0.42

        var previous = peg
        for i in 1 ... 7 {
            let center = anchor + linkStep * Double(i)
            let hinge = anchor + linkStep * (Double(i) - 0.5)
            let body: Body
            if i == 7 {
                body = world.addBody(.circle(radius: ballRadius), at: center, density: 5)
                ball = body
            } else {
                body = world.addBody(.capsule(from: -half, to: half, radius: 13),
                                     at: center)
                links.append(body)
            }
            world.connect(previous, body, .revolute(at: hinge))
            previous = body
        }
    }

    override func mousePressed() {
        let cursor = Vector2(mouseX, mouseY)
        var grabbable = links
        if let ball { grabbable.append(ball) }
        for body in grabbable where body.position.distance(to: cursor) < 130 {
            held = world.grab(body, at: cursor)
            return
        }
    }

    override func mouseReleased() {
        held?.remove()
        held = nil
    }

    override func keyPressed() {
        if key == " " {
            held = nil
            world.removeAll()
            build()
        }
    }

    override func draw() {
        background(Color(hex: 0x12151C))
        held?.target = Vector2(mouseX, mouseY)
        world.step(dt: deltaTime)

        noStroke()
        for i in bricks.indices {
            withState {
                translate(bricks[i].position)
                rotate(bricks[i].angle)
                fill(rows[i % rows.count])
                drawRect(center: .zero, width: brickSize.x, height: brickSize.y,
                         cornerRadius: 4)
            }
        }

        let half = linkStep * 0.42
        stroke(Color(hex: 0x8E99A8))
        strokeWeight(26)
        for link in links {
            withState {
                translate(link.position)
                rotate(link.angle)
                drawLine(-half, half)
            }
        }

        noStroke()
        fill(Color(hex: 0x6B7484))
        drawCircle(center: anchor, radius: 16)
        if let ball {
            fill(Color(hex: 0xF2EFE8))
            drawCircle(center: ball.position, radius: ballRadius)
        }
    }
}
