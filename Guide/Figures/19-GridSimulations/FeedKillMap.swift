// figure: frame=650 themed
//
// Guide diagram (Chapter 19): the reaction-diffusion parameter map. The same
// simulation, seeded the same way, at 24 different feed/kill settings; the
// two parameters pick the regime, from dissolving to spots to mazes to coral.
import Ollin
import OllinDiagram

final class FeedKillMap: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    var dishes: [SimField] = []
    let feeds = [0.022, 0.03, 0.038, 0.046, 0.055, 0.066]
    let kills = [0.055, 0.059, 0.062, 0.065]

    override func setup() {
        dishes = []
    }

    override func draw() {
        background(paper)

        let tile = 118.0, gutter = 10.0
        let ox = 96.0, oy = 14.0
        if dishes.isEmpty {
            for kill in kills {
                for feed in feeds {
                    let dish = makeSimField(.reactionDiffusion(feed: feed, kill: kill),
                                        width: Int(tile), height: Int(tile))
                    withField(dish) {
                        noStroke()
                        fill(.white)
                        for row in 0 ..< 3 {
                            for col in 0 ..< 3 {
                                drawCircle(tile * (0.25 + 0.25 * Double(col)),
                                           tile * (0.25 + 0.25 * Double(row)), 4)
                            }
                        }
                    }
                    dishes.append(dish)
                }
            }
        }

        for (i, dish) in dishes.enumerated() {
            let x = ox + Double(i % feeds.count) * (tile + gutter)
            let y = oy + Double(i / feeds.count) * (tile + gutter)
            drawImage(dish.filtered(.gradientMap(.viridis)).image,
                      in: Rectangle(x: x, y: y, width: tile, height: tile))
        }

        noStroke()
        fill(ink.withAlpha(0.6))
        textSize(16)
        textAlign(.center, .top)
        for (i, feed) in feeds.enumerated() {
            let label = i == 0 ? String(format: "feed %.3f", feed) : String(format: "%.3f", feed)
            drawText(label, ox + Double(i) * (tile + gutter) + tile / 2, oy + 4 * (tile + gutter) + 2)
        }
        textAlign(.right, .middle)
        for (i, kill) in kills.enumerated() {
            let label = i == 0 ? String(format: "kill %.3f", kill) : String(format: "%.3f", kill)
            drawText(label, ox - 12, oy + Double(i) * (tile + gutter) + tile / 2)
        }
    }
}
