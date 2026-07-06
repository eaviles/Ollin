// figure: gif duration=3 fps=25 width=540
//
// Guide figure: the first motion. The circle swings side to side because
// `time` appears in its x; the loop lasts exactly one swing.
import Ollin

final class FirstMotion: Sketch {
    override func draw() {
        background(Color(hex: 0x11151C))
        noStroke()
        fill(Color(hex: 0xFFB703))
        let x = width / 2 + sin(time * .tau / 3) * 300
        drawCircle(x, height / 2, 70)
    }
}
