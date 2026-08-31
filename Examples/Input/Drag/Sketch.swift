import Ollin

/// The whole press-drag-release surface in one toy. Grab a ball
/// (`mousePressed()` fires once), drag it (`mouse - previousMouse` is this
/// frame's drag, drawn magnified as the bright stretch arrow), and let go
/// (`mouseReleased()`): the ball flies off with the hand's speed averaged over
/// the last few frames, so a flick that ended fast still throws hard. The
/// stretch arrow's weight also leans on `pressure`, which a plain mouse
/// reports as a steady 1 while pressed.
///
/// The opening rack is a `shuffled` deck (each size dealt exactly once, in a
/// random order) and every ball's ink is a weighted `randomChoice`: mostly
/// bone, sometimes amber, rarely coral. Press r to re-deal.
@main
final class Drag: Sketch {
    struct Ball {
        var position: Vector2
        var velocity: Vector2 = .zero
        var radius: Double
        var ink: Color
    }

    var balls: [Ball] = []
    /// Index of the ball being dragged, while a press holds one.
    var held: Int?
    /// Where the grab landed relative to the ball's center, so picking a ball
    /// up by its edge does not snap it to the cursor.
    var holdOffset = Vector2.zero
    /// The hand's speed over the last few frames, points per second. Averaging
    /// a handful of samples reads the flick, not the final frame's jitter.
    var recentSpeeds: [Vector2] = []

    override func setup() {
        noStroke()
        deal()
    }

    override func draw() {
        background(Color(hex: 0x0E1116))
        let delta = mouse - previousMouse           // this frame's drag

        // Free balls glide, slow down, and bounce off the walls; the held one
        // rides the cursor. deltaTime keeps the feel the same at any frame rate.
        for i in balls.indices where i != held {
            balls[i].position += balls[i].velocity * deltaTime
            balls[i].velocity *= exp(-0.9 * deltaTime)
            bounce(&balls[i])
        }
        if let i = held {
            balls[i].position = mouse + holdOffset
            recentSpeeds.append(delta / max(deltaTime, 0.001))
            if recentSpeeds.count > 6 { recentSpeeds.removeFirst() }
        }

        for ball in balls {
            fill(ball.ink)
            drawCircle(ball.position.x, ball.position.y, ball.radius)
        }

        // Two arrows while dragging: the bright one is this frame's delta
        // magnified, the teal one the averaged speed the ball would leave with
        // now. Moved steadily they coincide; they split when the hand
        // accelerates, which is the difference averaging is for.
        if let i = held {
            withState {
                if !recentSpeeds.isEmpty {
                    let fling = recentSpeeds.reduce(.zero, +) / Double(recentSpeeds.count)
                    stroke(Color(hex: 0x64DFDF, alpha: 0.6))
                    strokeWeight(2 * scale)
                    drawArrow(from: balls[i].position, to: balls[i].position + fling * 0.1)
                }
                stroke(Color(white: 1, alpha: 0.85))
                strokeWeight((2 + 3 * pressure) * scale)
                drawArrow(from: balls[i].position, to: balls[i].position + delta * 6)
            }
        }

        drawCaption("grab a ball, drag, let go: it flies with the hand's last few frames · r re-deals")
    }

    /// Fires once per press: pick up the topmost ball under the cursor.
    override func mousePressed() {
        guard let i = balls.indices.last(where: {
            balls[$0].position.distance(to: mouse) < balls[$0].radius + 12 * scale
        }) else { return }
        held = i
        holdOffset = balls[i].position - mouse
        balls[i].velocity = .zero
        recentSpeeds.removeAll()
    }

    /// Fires once per release: the ball leaves with the averaged speed.
    override func mouseReleased() {
        guard let i = held else { return }
        if !recentSpeeds.isEmpty {
            balls[i].velocity = recentSpeeds.reduce(.zero, +) / Double(recentSpeeds.count)
        }
        held = nil
    }

    override func keyPressed() {
        if key == "r" { deal() }
    }

    /// A fresh rack across the middle. `shuffled` deals each size exactly once
    /// in a random order (unlike `randomChoice`, which could repeat one), and
    /// the color weights are lopsided on purpose, so the accents stay rare.
    func deal() {
        held = nil
        let inks: [Color] = [Color(hex: 0xE8E4D8), Color(hex: 0xFFB703), Color(hex: 0xE56B6F)]
        balls = shuffled([30.0, 38, 46, 54, 62]).enumerated().map { i, size in
            Ball(position: Vector2(width * (0.15 + 0.175 * Double(i)), height / 2),
                 radius: size * scale,
                 ink: randomChoice(inks, weights: [6, 3, 1]))
        }
    }

    /// Keep a ball on the canvas: past an edge, fold the overshoot back in and
    /// reflect the velocity, losing a little energy per hit.
    func bounce(_ ball: inout Ball) {
        let r = ball.radius
        var p = ball.position
        var v = ball.velocity
        if p.x < r {
            p = Vector2(2 * r - p.x, p.y)
            v = Vector2(abs(v.x) * 0.85, v.y)
        }
        if p.x > width - r {
            p = Vector2(2 * (width - r) - p.x, p.y)
            v = Vector2(-abs(v.x) * 0.85, v.y)
        }
        if p.y < r {
            p = Vector2(p.x, 2 * r - p.y)
            v = Vector2(v.x, abs(v.y) * 0.85)
        }
        if p.y > height - r {
            p = Vector2(p.x, 2 * (height - r) - p.y)
            v = Vector2(v.x, -abs(v.y) * 0.85)
        }
        ball.position = p
        ball.velocity = v
    }
}
