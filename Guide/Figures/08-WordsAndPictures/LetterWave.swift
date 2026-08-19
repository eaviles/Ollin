// figure: frame=45
//
// Guide figure (Chapter 8): the per-glyph form of drawText. Each letter rides
// the same swing with a head start proportional to its place in the word, and
// fading echoes trail the motion so the wave reads in a still image.
import Ollin

final class LetterWave: Sketch {
    let palette = Palette([
        Color(hex: 0x5E60CE), Color(hex: 0x64DFDF),
        Color(hex: 0xFFB703), Color(hex: 0xE56B6F), Color(hex: 0x8AC926),
    ])

    override func draw() {
        background(Color(hex: 0x0E1116))
        noStroke()
        textSize(230)
        textAlign(.center, .middle)

        // Echoes first (oldest faintest), then the crisp front copy.
        for echo in stride(from: 12, through: 0, by: -1) {
            let phase = time - Double(echo) * 0.045
            let alpha = echo == 0 ? 1.0 : 0.2 - Double(echo) * 0.015
            drawText("ollin", width / 2, height / 2) { g in
                let bob = sin(phase * 2.6 + Double(g.index) * 0.9) * 90
                let c = palette[g.index]
                fill(Color(red: c.red, green: c.green, blue: c.blue, alpha: alpha))
                withState {
                    translate(0, bob)
                    g.draw()
                }
            }
        }
    }
}
