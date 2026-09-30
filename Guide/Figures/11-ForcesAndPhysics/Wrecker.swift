// figure: frame=62
//
// Guide payoff (Chapter 11): a wrecking ball. A chain of rigid links hangs
// from a peg by revolute joints and ends in a heavy ball. It starts swung
// up to one side, so gravity launches it into the brick tower, and a brick
// the ball meets fast enough breaks where it was hit. Hold the
// mouse near the ball or a link to drag it, release to let it fly, and
// press space to rebuild.
import Ollin
import OllinPhysics

final class Wrecker: Sketch {
    let world = World()

    struct Shard { let body: Body; let shape: Shape; let color: Color }

    var bricks: [Body] = []
    var shards: [Shard] = []
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
        world.restitution = 0.05
        world.bounds = bounds
        build()
        strokeCap(.round)
    }

    func build() {
        bricks.removeAll()
        shards.removeAll()
        links.removeAll()

        // The tower: a single column of bricks standing on the floor.
        for row in 0 ..< 9 {
            let y = height - 20 - (Double(row) + 0.5) * (brickSize.y + 2)
            let brick = world.addBody(.box(width: brickSize.x, height: brickSize.y),
                                      at: Vector2(width * 0.68, y), friction: 0.6)
            brick.userData = rows[row % rows.count]
            bricks.append(brick)
        }

        // The chain: a fixed peg, six links hinged end to end, then the ball.
        anchor = Vector2(width * 0.64, 130)
        let peg = world.addBody(.circle(radius: 12), at: anchor, kind: .static)
        let half = linkStep * 0.42

        var previous = peg
        for i in 1 ... 7 {
            let center = anchor + linkStep * (Double(i) - 0.5)
            let hinge = anchor + linkStep * (Double(i) - 1)
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

    /// Break one brick where it was hit, into pieces that carry on with it.
    func shatter(_ i: Int, at hit: Vector2) {
        let brick = bricks.remove(at: i)
        let w = brickSize.x / 2, h = brickSize.y / 2
        let outline = Shape([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)])
        for piece in outline.fractured(into: 6, around: hit, seed: bricks.count) {
            let middle = piece.centroid
            let local = piece.mapPoints { $0 - middle }
            guard let corners = local.contours.first?.points else { continue }
            let body = world.addBody(.polygon(corners),
                                     at: brick.position + middle.rotated(by: brick.angle),
                                     friction: 0.6)
            body.angle = brick.angle
            body.velocity = brick.velocity + (middle - hit).normalized * 250
            shards.append(Shard(body: body, shape: local, color: brick.userData as? Color ?? .white))
        }
        world.remove(brick)
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
        world.advance(by: deltaTime)

        // A brick the ball meets fast enough breaks where it was hit.
        if let ball, ball.velocity.length > 900 {
            for i in bricks.indices.reversed() {
                let local = (ball.position - bricks[i].position).rotated(by: -bricks[i].angle)
                let nearest = Vector2(clamp(local.x, -brickSize.x / 2, brickSize.x / 2),
                                      clamp(local.y, -brickSize.y / 2, brickSize.y / 2))
                if local.distance(to: nearest) < ballRadius + 3 { shatter(i, at: nearest) }
            }
        }

        noStroke()
        for brick in bricks {
            withState {
                translate(brick.position)
                rotate(brick.angle)
                fill(brick.userData as? Color ?? .white)
                drawRect(center: .zero, width: brickSize.x, height: brickSize.y,
                         cornerRadius: 4)
            }
        }
        for shard in shards {
            withState {
                translate(shard.body.position)
                rotate(shard.body.angle)
                fill(shard.color)
                drawShape(shard.shape)
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
