// figure: frame=381
//
// Guide diagram (Chapter 18): what a seed becomes. Four identical
// reaction-diffusion fields, each seeded with the same ring at a different
// moment, so one capture shows the growth at four ages.
import Ollin

final class Seeding: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    var dishes: [SimField] = []
    let ages = [0, 100, 220, 380]

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        let tile = 200.0, gutter = 15.0, ox = 12.0, oy = 20.0
        if dishes.isEmpty {
            dishes = ages.map { _ in
                simField(.reactionDiffusion(feed: 0.046, kill: 0.062), width: Int(tile), height: Int(tile))
            }
        }
        for (i, dish) in dishes.enumerated() {
            withField(dish) {
                if frameCount == 381 - ages[i] {         // stagger the seeding
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
            fill(Color(hex: 0x2B2B2B, alpha: 0.6))
            textSize(16)
            textAlign(.center, .top)
            drawText(ages[i] == 0 ? "the seed, just drawn" : "\(ages[i]) frames later",
                     x + tile / 2, oy + tile + 12)
        }

        noStroke()
        fill(Color(hex: 0x2B2B2B))
        textSize(19)
        textAlign(.center, .top)
        drawText("whatever you draw into the field is the chemistry it grows from", width / 2, 292)
    }
}
