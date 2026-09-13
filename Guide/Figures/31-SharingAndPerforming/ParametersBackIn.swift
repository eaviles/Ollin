// figure: frame=0 themed
//
// Guide figure (Chapter 31): the parameters, handed back to a run. One probe
// sketch, rings on a ground, is rendered three times through
// OllinApp.image(of:), each time with its parameters set the way --param sets
// them, after setup() and before the first frame: as written, with the radius
// given, and with the radius, the ring count, and the paper given. Under each
// render, the command that asks for it and the recipe the file then carries,
// which are the same values read in two directions. The panels are the
// probe's real exported pixels.
//
// ParametersBackIn is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class ParametersBackIn: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    struct Run {
        var flags: [String]          // the command line, a line each
        var radius: Double?
        var rings: Int?
        var paper: Color?
        var recipe: [String]         // what the exported file then says
    }

    let runs: [Run] = [
        Run(flags: ["--export a.png"],
            radius: nil, rings: nil, paper: nil,
            recipe: ["seed 48213", "radius 40 · rings 2", "paper #F3EFE6"]),
        Run(flags: ["--export b.png", "--param radius=90"],
            radius: 90, rings: nil, paper: nil,
            recipe: ["seed 48213", "radius 90 · rings 2", "paper #F3EFE6"]),
        Run(flags: ["--export c.png", "--param radius=90 --param rings=4", "--param paper=#101018"],
            radius: 90, rings: 4, paper: Color(hex: 0x101018),
            recipe: ["seed 48213", "radius 90 · rings 4", "paper #101018"]),
    ]

    /// The three renders, made once and kept, so the themed second pass draws
    /// the same pixels rather than rendering again.
    private var renders: [Image] = []

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if renders.isEmpty { renders = runs.map(render) }

        let side = 240.0, gap = 34.0, top = 98.0
        let left = (width - side * 3 - gap * 2) / 2
        for (i, run) in runs.enumerated() {
            let x = left + Double(i) * (side + gap)
            let panel = Rectangle(x: x, y: top, width: side, height: side)

            // The command, above: the export flag quiet, the parameters plain.
            noStroke()
            for (j, line) in run.flags.enumerated() {
                drawText(line, panel.center.x, 34 + Double(j) * 19, size: 13,
                         color: j == 0 ? theme.muted : theme.ink, align: .center, .middle)
            }

            drawImage(renders[i], in: panel)
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(panel)

            // The recipe the file carries, below.
            let card = Rectangle(x: x, y: top + side + 18, width: side, height: 84)
            fill(theme.card)
            stroke(theme.border)
            strokeWeight(1)
            drawRect(card, cornerRadius: 8)
            noStroke()
            drawText("the file's recipe", card.x + 12, card.y + 15, size: 11, color: theme.muted,
                     align: .left, .middle)
            for (j, line) in run.recipe.enumerated() {
                drawText(line, card.x + 12, card.y + 37 + Double(j) * 18, size: 12.5,
                         color: theme.ink, align: .left, .middle)
            }
        }

        diagramCaption("one sketch, three runs: the command line and the recipe name the same values",
                       at: 486, theme: theme)
        noStroke()
        drawText("each lands after setup() and before the first frame; a name the sketch lacks, or a value its kind cannot read, stops the run",
                 width / 2, 514, size: 13, color: theme.muted, align: .center, .top)
    }

    /// Render the probe under one run's parameters, set the way the flag sets
    /// them: on the instance, before its first frame.
    private func render(_ run: Run) -> Image {
        let probe = RecipeProbe()
        if let radius = run.radius { probe.radius = radius }
        if let rings = run.rings { probe.rings = rings }
        if let paper = run.paper { probe.paper = paper }
        guard let exported = OllinApp.image(of: probe) else { return Image(width: 1, height: 1) }
        return Image(cgImage: exported)
    }
}

/// The probe: rings on a paper, every part of it a parameter.
final class RecipeProbe: Sketch {
    override var canvasSize: CanvasSize { .square(240) }

    @Param("Radius", 10 ... 120) var radius = 40.0
    @Param("Rings", 1 ... 6) var rings = 2
    @Param("Paper") var paper = Color(hex: 0xF3EFE6)

    override func draw() {
        background(paper)
        let ink = paper.luminance > 0.5 ? Color(hex: 0x1F2328) : Color(hex: 0xF3EFE6)
        noFill()
        stroke(ink)
        strokeWeight(4)
        for i in 0..<rings {
            drawCircle(width / 2, height / 2, radius * (1 - Double(i) * 0.22))
        }
        noStroke()
        fill(ink)
        drawCircle(width / 2, height / 2, 5)
    }
}
