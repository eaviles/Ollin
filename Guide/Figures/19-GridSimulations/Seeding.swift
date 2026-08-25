// figure: frame=381 themed
//
// Guide diagram (Chapter 19): what a seed becomes. Four identical
// reaction-diffusion fields, each seeded with the same ring at a different
// moment, so one capture shows the growth at four ages.
import Ollin

final class Seeding: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }

    var dishes: [SimField] = []
    var tick = 0
    let ages = [0, 100, 220, 380]

    override func setup() {
        dishes = []
        tick = 0
    }

    override func draw() {
        background(paper)
        tick += 1
        let tile = 200.0, gutter = 15.0, ox = 12.0, oy = 20.0
        if dishes.isEmpty {
            dishes = ages.map { _ in
                simField(.reactionDiffusion(feed: 0.046, kill: 0.062), width: Int(tile), height: Int(tile))
            }
        }
        for (i, dish) in dishes.enumerated() {
            withField(dish) {
                if tick == 381 - ages[i] {               // stagger the seeding
                    noStroke()
                    stroke(.white)
                    strokeWeight(5)
                    noFill()
                    drawCircle(tile / 2, tile / 2, 34)
                    noStroke()
                    fill(.white)
                    drawCircle(tile / 2, tile / 2, 6)
                }
            }
            let x = ox + Double(i) * (tile + gutter)
            drawImage(dish.filtered(.gradientMap(.viridis)).image,
                      in: Rectangle(x: x, y: oy, width: tile, height: tile))
            noStroke()
            fill(ink.withAlpha(0.6))
            textSize(16)
            textAlign(.center, .top)
            drawText(ages[i] == 0 ? "the seed, just drawn" : "\(ages[i]) frames later",
                     x + tile / 2, oy + tile + 12)
        }

        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .top)
        drawText("whatever you draw into the field is the chemistry it grows from", width / 2, 292)
    }
}
