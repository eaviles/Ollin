// figure: frame=0
//
// Guide figure (Appendix A): the sketch the appendix reads line by line.
// Sixty streaks drifting across a night sky.
import Ollin

final class Meteors: Sketch {
    var meteors: [Vector2] = []

    override func setup() {
        seed(11)
        for _ in 0..<60 {
            meteors.append(Vector2(random(width), random(height)))
        }
    }

    override func draw() {
        background(Color(hex: 0x101623))
        for i in 0..<meteors.count {
            meteors[i] += Vector2(2.3, 0.9)
            if meteors[i].x > width {
                meteors[i] = Vector2(-30, random(height))
            }
            drawMeteor(at: meteors[i])
        }
    }

    func drawMeteor(at p: Vector2) {
        stroke(Color(hex: 0xF2B33D, alpha: 0.7))
        strokeWeight(2)
        drawLine(p.x - 34, p.y - 13, p.x, p.y)
        noStroke()
        fill(.white)
        drawCircle(p.x, p.y, 3.5)
    }
}
