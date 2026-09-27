// figure: frame=300
//
// Guide sketch (Chapter 10): the motion trio throwing a ball. Gravity bends
// the velocity, the velocity moves the position, and the floor flips the
// vertical part of the velocity while taking a little of both parts. The
// trail keeps the ball's recent positions so a still shows the arc and the
// bounces, not only where the ball is now.
import Ollin

final class Thrown: Sketch {
    var position = Vector2(120, 800)
    var velocity = Vector2(150, -640)
    let gravity = Vector2(0, 700)
    var trail: [Vector2] = []

    override func draw() {
        background(Color(hex: 0x0E1116))

        velocity += gravity * deltaTime
        position += velocity * deltaTime

        // The floor: bounce, losing a little each time.
        if position.y > height - 60 {
            position = position.with(y: height - 60)
            velocity = Vector2(velocity.x * 0.7, -velocity.y * 0.82)
        }

        // Remember where the ball has been, every third frame.
        if frameCount % 3 == 0 { trail.append(position) }
        if trail.count > 200 { trail.removeFirst() }

        stroke(Color(white: 0.25))
        strokeWeight(2)
        drawLine(0, height - 36, width, height - 36)
        noStroke()
        fill(Color(hex: 0xFFB703, alpha: 0.35))
        for p in trail { drawCircle(center: p, radius: 4) }
        fill(Color(hex: 0xFFB703))
        drawCircle(center: position, radius: 24)
    }
}
