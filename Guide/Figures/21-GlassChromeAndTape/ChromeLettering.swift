// figure: frame=0
//
// Guide figure (Chapter 21): airbrushed lettering chrome. The word on top is
// the classic blue sky over an orange floor, with the horizon's bend, the dark
// core band, the razor break, and the bright wire. Below it the same filter in
// a gold palette on a heart and a night palette on a disc, so the reader sees
// that every stop is a parameter.
import Ollin

final class ChromeLettering: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    override func draw() {
        background(Color(hex: 0x111318))

        let word = makeRenderTarget(width: 880, height: 260)
        withTarget(word) {
            noStroke()
            fill(.white)
            textFont(.systemBold)
            textAlign(.center, .middle)
            textSize(172)
            drawText("CHROME", 440, 128)
        }
        drawImage(word.filtered(.chrome(warp: 9, waves: 1.5, phase: 0.8)).image, 0, 10)

        let heart = makeRenderTarget(width: 260, height: 220)
        withTarget(heart) { noStroke(); fill(.white); drawHeart(130, 116, 200) }
        let gold = Filter.chrome(horizon: 0.56, warp: 12, waves: 1,
                                 sky: Ramp([Color(hex: 0x3B1D00), Color(hex: 0xC98A1E), Color(hex: 0xFFF2B0)]),
                                 floor: Ramp([Color(hex: 0x5A2E00), Color(hex: 0xE2A232), Color(hex: 0xFFE89A)]),
                                 core: Color(hex: 0x2A1400), wire: Color(hex: 0xFFF8DC), phase: 2.1)
        drawImage(heart.filtered(gold).image, 150, 258)

        let disc = makeRenderTarget(width: 260, height: 220)
        withTarget(disc) { noStroke(); fill(.white); drawCircle(130, 110, 96) }
        let night = Filter.chrome(horizon: 0.45, warp: 16, waves: 2.5,
                                  sky: Ramp([Color(hex: 0x05060F), Color(hex: 0x3A2B8C), Color(hex: 0xD9C8FF)]),
                                  floor: Ramp([Color(hex: 0x1B0A2E), Color(hex: 0xB02A7A), Color(hex: 0xFFC2E0)]),
                                  core: Color(hex: 0x0A0410), phase: -1.4)
        drawImage(disc.filtered(night).image, 470, 258)

        textFont(.system)
        noStroke()
        fill(Color(white: 0.5))
        textSize(17)
        textAlign(.center, .top)
        drawText("gold", 280, 468)
        drawText("night", 600, 468)
    }
}
