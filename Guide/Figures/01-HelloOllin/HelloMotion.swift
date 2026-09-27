// figure: frame=90
//
// Guide figure: the Chapter 1 finished sketch. A ring of circles drifts and
// breathes; every bit of motion comes from `time` appearing in an expression,
// and the parameters tune it live in the inspector. The ring is placed from
// `uv(0.5, 0.5)` and sized in units of `scale`, so the same sketch fills a
// canvas of any shape.
import Ollin

final class HelloMotion: Sketch {
    @Param("Speed", 0...2) var speed = 0.3
    @Param("Size", 8...80) var size = 38.0
    @Param("Circles", 4...120) var count = 28
    @Param("Ground") var ground = Color(hex: 0x11151C)

    let colors: [Color] = [
        Color(hex: 0xFFB703, alpha: 0.85), Color(hex: 0xFB8500, alpha: 0.85),
        Color(hex: 0x219EBC, alpha: 0.85), Color(hex: 0x8ECAE6, alpha: 0.85),
    ]

    override func draw() {
        background(ground)
        noStroke()
        let center = uv(0.5, 0.5)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .tau + time * speed
            let breathe = sin(time * 1.4 + Double(i) * 0.5)
            let ring = (310 + breathe * 80) * scale
            let x = center.x + cos(angle) * ring
            let y = center.y + sin(angle) * ring
            fill(colors[i % colors.count])
            drawCircle(x, y, (size + breathe * 16) * scale)
        }
    }
}
