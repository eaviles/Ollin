// figure: frame=1100 themed
//
// Guide diagram (Chapter 19): a picture choosing the chemistry. One layer, a
// soft-edged disc, is attached as a reaction-diffusion field's modulation, so
// its brightness slides feed and kill per texel: the spot regime where it is
// black, the maze regime where it is white, and everything between across the
// soft edge. The middle dish is that one simulation; the right one is what a
// mask gives instead, two separate dishes cut along the same disc, meeting at
// a seam neither of them knows about.
import Ollin
import OllinDiagram

final class ChemistryByPicture: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let side = 260
    var map: RenderTarget!
    var modulated: SimField!
    var spots: SimField!
    var maze: SimField!
    var seeded = false
    /// The seed marks, the same in all three dishes.
    var marks: [Vector2] = []

    override func setup() {
        seed(11)
        marks = (0 ..< 40).map { _ in Vector2(random(Double(side)), random(Double(side))) }
        // The two regimes: the spot pair where the map is black, the maze pair
        // where it is white.
        modulated = makeSimField(.reactionDiffusion(feed: 0.046, kill: 0.065,
                                                    toFeed: 0.055, toKill: 0.062),
                                 width: side, height: side)
        spots = makeSimField(.reactionDiffusion(feed: 0.046, kill: 0.065), width: side, height: side)
        maze = makeSimField(.reactionDiffusion(feed: 0.055, kill: 0.062), width: side, height: side)
        map = makeRenderTarget(width: side, height: side)
        modulated.modulation = map
        seeded = false
    }

    var disc: Circle { Circle(center: Vector2(Double(side) * 0.5, Double(side) * 0.5), radius: Double(side) * 0.3) }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        // The map, drawn every frame: white inside the disc, black outside, a
        // soft edge a fifth of the radius wide.
        withTarget(map) {
            background(.black)
            noStroke()
            fill(.radial(center: disc.center, radius: disc.radius * 1.2,
                         Ramp(stops: [(0.0, .white), (0.7, .white), (1.0, .black)])))
            drawCircle(center: disc.center, radius: disc.radius * 1.2)
        }

        // The same seed in all three dishes, once.
        if !seeded {
            for dish in [modulated!, spots!, maze!] {
                withField(dish) {
                    noStroke()
                    fill(.white)
                    for mark in marks { drawCircle(center: mark, radius: 4) }
                }
            }
            seeded = true
        }

        let s = Double(side), gap = 30.0, top = 66.0
        let left = (width - s * 3 - gap * 2) / 2
        let panels = (0 ..< 3).map { Rectangle(x: left + Double($0) * (s + gap), y: top, width: s, height: s) }

        drawImage(map.image, in: panels[0])
        drawImage(modulated.filtered(.gradientMap(.viridis)).image, in: panels[1])
        drawImage(spots.filtered(.gradientMap(.viridis)).image, in: panels[2])
        withClip(Circle(center: panels[2].center, radius: disc.radius)) {
            drawImage(maze.filtered(.gradientMap(.viridis)).image, in: panels[2])
        }

        // The disc's own outline on the mask panel, so the seam is named.
        noFill()
        stroke(theme.accent)
        strokeWeight(1.5)
        drawCircle(center: panels[2].center, radius: disc.radius)

        let titles = ["the layer", "one dish, modulated by it", "two dishes, cut with a mask"]
        let notes = ["white where the maze should grow",
                     "the maze grows out into the spots",
                     "a seam where the mask ends"]
        for (i, panel) in panels.enumerated() {
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(panel)
            noStroke()
            drawText(titles[i], panel.center.x, top - 22, size: 16, color: theme.ink, align: .center, .middle)
            drawText(notes[i], panel.center.x, top + s + 12, size: 12,
                     color: i == 2 ? theme.accent : theme.muted, align: .center, .top)
        }

        diagramCaption("one simulation wearing two regimes: the boundary is chemistry, not a mask",
                       at: 412, theme: theme)
        drawText("dish.modulation = layer · black runs feed 0.046, kill 0.065 · white runs feed 0.055, kill 0.062 · gray slides between",
                 width / 2, 446, size: 13, color: theme.muted, align: .center, .top)
    }
}
