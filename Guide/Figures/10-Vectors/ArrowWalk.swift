// figure: frame=90
//
// Guide sketch (Chapter 10): arrow arithmetic you can push around. The trip
// is a subtraction that follows a wandering target, stones mark scaled
// fractions of it, and a fixed breeze walked from its end is an addition.
import Ollin

final class ArrowWalk: Sketch {
    override func setup() {
        noiseSeed(8)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let home = Vector2(width * 0.3, height * 0.68)
        var target = Vector2(noise(time * 0.25, 3) * width,
                             noise(time * 0.25, 77) * height * 0.55)
        if mouseIsPressed { target = Vector2(mouseX, mouseY) }

        let trip = target - home            // the arrow from here to there
        let breeze = Vector2(170, -240)     // a second arrow, always the same

        // Scaling: stones along the same road, at fractions of the trip.
        noStroke()
        fill(Color(hex: 0x2B2B2B, alpha: 0.28))
        for s in [-0.5, 0.25, 0.5, 0.75, 1.5] {
            drawCircle(center: home + trip * s, radius: 9)
        }

        // The trip itself, then the breeze walked from its end.
        strokeWeight(4)
        stroke(Color(hex: 0xE4572E))
        drawLine(home, home + trip)
        stroke(Color(hex: 0x2B2B2B))
        drawLine(home + trip, home + trip + breeze)

        noStroke()
        fill(Color(hex: 0x2B2B2B))
        drawCircle(center: home, radius: 12)
        drawCircle(center: target, radius: 8)
        fill(Color(hex: 0xE4572E))
        drawCircle(center: home + trip + breeze, radius: 12)
    }
}
