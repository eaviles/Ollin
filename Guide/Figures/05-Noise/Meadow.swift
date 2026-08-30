// figure: frame=90
//
// Guide payoff (Chapter 5): a meadow of blades bending in a noise-driven
// wind. Every blade grows by gliding through one noise field, toured on a
// closed loop (the loop: parameter), so an exported GIF of one 6-second
// pass loops seamlessly.
import Ollin

final class Meadow: Sketch {
    @Param("Sway", 0...1) var sway = 0.55
    @Param("Glow", 0...1) var glow = 0.4

    let ramp = Ramp([
        Color(hex: 0x11553F), Color(hex: 0x2A9D8F),
        Color(hex: 0x8AB17D), Color(hex: 0xE9C46A),
    ])

    override func setup() {
        noiseSeed(11)
        strokeCap(.round)   // segments overlap their joints into one blade
    }

    override func draw() {
        background(Color(hex: 0x0E1116))
        noFill()
        randomSeed(3)                          // the same planting every frame
        let up = -Double.tau / 4
        let breeze = loopProgress(over: 6)     // one lap of wind per six seconds

        for row in 0..<38 {
            for col in 0..<40 {
                let x = 45.0 + Double(col) * 26 + random(-1, 1) * 8
                let y = 95.0 + Double(row) * 26 + random(-1, 1) * 8
                let weather = noise(x * 0.0011, y * 0.0011, loop: breeze, radius: 0.5)
                let blade = ramp.color(at: weather)
                strokeWeight(1.5 + weather * 2.3)

                var px = x, py = y
                for segment in 0..<6 {
                    let angle = up + signedNoise(px * 0.0016, py * 0.0016, loop: breeze, radius: 0.5) * 1.15 * sway
                    let nx = px + cos(angle) * 8
                    let ny = py + sin(angle) * 8
                    stroke(Color.mix(blade, Color(hex: 0xFFF2CC), Double(segment) / 5 * glow))
                    drawLine(px, py, nx, ny)
                    px = nx
                    py = ny
                }
            }
        }
    }
}
