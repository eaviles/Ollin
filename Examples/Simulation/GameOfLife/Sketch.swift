import Ollin

/// Conway's **Game of Life** on the GPU through the effects substrate. A `SimField`
/// running `.gameOfLife()` is a persistent layer the renderer steps each frame; you
/// *draw into it* to spawn or erase cells (white = alive, black = dead), and the
/// renderer evolves the B3/S23 rule. The field is coarse (one texel is one cell), so
/// the gliders and oscillators are big enough to watch.
///
/// Drag to draw living cells; hold any key while dragging to erase. See
/// `Simulation/GrayScott` for the reaction-diffusion sibling.
@main
final class GameOfLife_Example: Sketch {
    private let cells = 130
    private var life: SimField!
    private var seeded = false

    override func setup() {
        // A field ~`cells` across, so each texel reads as a chunky, visible cell.
        life = simField(.gameOfLife(), scale: Double(cells) / width)
    }

    override func draw() {
        background(.black)
        let cw = width / Double(cells)                    // one cell, in canvas points
        withField(life) {
            noStroke()
            if !seeded {                                  // a random soup to get life going
                fill(.white)
                for _ in 0 ..< 7000 {
                    let gx = Double(Int(random(Double(cells)))), gy = Double(Int(random(Double(cells))))
                    drawRect(gx * cw, gy * cw, cw, cw)
                }
                seeded = true
            }
            // Paint cells under the cursor (cell-aligned), erasing if a key is held.
            if mouseIsPressed {
                fill(keyIsPressed ? .black : .white)
                let gx = Double(Int(mouseX / cw)), gy = Double(Int(mouseY / cw))
                drawRect((gx - 1) * cw, (gy - 1) * cw, cw * 3, cw * 3)
            }
        }
        drawImage(life.image, 0, 0)
        drawCaption("Game of Life · a SimField on the GPU · drag to draw cells, hold a key to erase")
    }
}
