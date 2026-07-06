// figure: frame=300
//
// Guide listing (Chapter 4): a seeded random walk that redraws from scratch
// every frame, revealing more steps as time passes. The seed makes the same
// walk replay identically, so it grows instead of boiling.
import Ollin

final class WalkGrows: Sketch {
    override func draw() {
        background(Color(hex: 0x0E1116))
        randomSeed(7)
        stroke(Color(hex: 0x64DFDF, alpha: 0.8))
        strokeWeight(2.5)

        var x = width / 2
        var y = height / 2
        let steps = min(2400, Int(time * 240))   // 240 new steps a second
        for _ in 0..<steps {
            let nx = x + random(-16, 16)
            let ny = y + random(-16, 16)
            drawLine(x, y, nx, ny)
            x = nx
            y = ny
        }

        noStroke()
        fill(.white)
        drawCircle(x, y, 9)
    }
}
