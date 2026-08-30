import Ollin

/// A soap film measured, not styled: `.thinFilm` works out real interference
/// per wavelength for a film a few hundred nanometers deep, so as the film
/// breathes the colors run through the true film color order (clear, straw,
/// magenta, cyan, then crowded pastel), instead of a hue wheel. Behind it, a
/// dust of bright specks runs through `.diffraction`, a slowly turning grating
/// that streaks each speck into rainbow orders, red always reaching farther
/// than blue.
@main
final class SoapFilm: Sketch {

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x0A0C10))

        // The dust: fixed bright specks, streaked into grating orders that
        // slowly turn with time.
        let dust = makeRenderTarget()
        withTarget(dust) {
            for i in 0..<26 {
                let n = Double(i)
                let x = width * (0.5 + 0.46 * sin(n * 2.4 + 0.7) * cos(n * 0.9))
                let y = height * (0.5 + 0.46 * sin(n * 1.7 + 2.1))
                fill(Color(white: 0.5 + 0.5 * sin(n * 3.3).magnitude))
                drawCircle(x, y, 3 + 4 * sin(n * 5.1).magnitude)
            }
        }
        drawImage(dust.filtered(.diffraction(amount: 0.07, angle: time * 0.1,
                                             orders: 2)).image, 0, 0)

        // The film: a bright round wash whose mean thickness swings a few
        // hundred nanometers, so it drains through the color orders and back.
        let film = makeRenderTarget()
        withTarget(film) {
            fill(Color(white: 0.85))
            drawCircle(width / 2, height / 2, 330)
        }
        let breathing = 340 + sin(time * 0.4) * 170
        drawImage(film.filtered(.thinFilm(amount: 0.95, thickness: breathing,
                                          variation: 260, scale: 1.8,
                                          shift: time * 0.25)).image, 0, 0)
    }
}
