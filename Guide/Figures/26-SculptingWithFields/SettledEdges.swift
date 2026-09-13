// figure: frame=0 themed
//
// Guide figure (Chapter 26): temporal anti-aliasing, in the exported pixels
// themselves. One probe, thin bright rods at shallow tilts under a still
// camera, is rendered twice through OllinApp.image(of:), once with plain
// multisampling and once with temporalAntialiasing() on, which a headless
// render carries out as sixteen jittered passes averaged inside the frame.
// The same crop of both renders is read back and drawn one pixel per square,
// so the two panels are the real pixels rather than a smoothed enlargement:
// the fixed sample positions on the left leave each hairline beaded and
// stepped, and the jittered average on the right settles it into an even line.
//
// SettledEdges is declared first on purpose: the sketch loader compiles the
// first `class …: Sketch` it finds, so the probe has to come after it.
import Ollin
import OllinDiagram

final class SettledEdges: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The page size of one probe pixel, and the crop of the probe shown.
    let cell = 8.0
    let crop = (x: 62, y: 61, width: 46, height: 30)

    /// Both renders, read back once; the dark variant redraws from the same
    /// pixels, since the probes are depicted content and do not flip.
    private var panels: [[[Color]]]?

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        if panels == nil {
            panels = [false, true].map { on in
                let probe = HairlineProbe()
                probe.temporalAA = on
                return pixels(of: probe)
            }
        }
        guard let panels else { return }

        let panelWidth = cell * Double(crop.width)
        let panelHeight = cell * Double(crop.height)
        let gap = 44.0
        let left = (width - panelWidth * 2 - gap) / 2
        let top = 64.0
        let titles = ["temporalAntialiasing() off", "temporalAntialiasing() on"]
        let notes = ["eight fixed sample positions", "sixteen jittered passes, averaged"]
        for (index, rows) in panels.enumerated() {
            let x = left + Double(index) * (panelWidth + gap)
            let rect = Rectangle(x: x, y: top, width: panelWidth, height: panelHeight)
            drawPixels(rows, in: rect)
            diagramFrame(rect, title: titles[index], theme: theme)
            drawText(notes[index], rect.x + rect.width / 2, rect.y + rect.height + 12,
                     size: 16, color: theme.muted, align: .center, .top)
        }

        diagramCaption("the same exported pixels, one square each", at: 372, theme: theme)
    }

    /// One square per read-back pixel, top row first.
    private func drawPixels(_ rows: [[Color]], in rect: Rectangle) {
        noStroke()
        for (y, row) in rows.enumerated() {
            for (x, color) in row.enumerated() {
                fill(color)
                drawRect(rect.x + Double(x) * cell, rect.y + Double(y) * cell, cell, cell)
            }
        }
    }

    /// Render the probe headless and read the crop back as rows of colors.
    private func pixels(of probe: Sketch) -> [[Color]] {
        guard let rendered = OllinApp.image(of: probe) else { return [] }
        let image = Image(cgImage: rendered)
        return (0..<crop.height).map { row in
            (0..<crop.width).map { column in image[crop.x + column, crop.y + row] }
        }
    }
}

/// The probe: bright rods thinner than a pixel, tilted a few degrees, which is
/// the case fixed sample positions handle worst. Nothing in it moves, so the
/// two renders differ only in how the pixels were sampled.
final class HairlineProbe: Sketch {
    var temporalAA = false

    override var canvasSize: CanvasSize { .size(240, 150) }

    override func draw() {
        background(Color(white: 0.045))
        perspective(eye: Vector3(0, 1.4, 6.2), target: Vector3(0, 1.2, 0),
                    fieldOfView: .pi / 3.6)
        ambientLight(Color(white: 0.10))
        directionalLight(.white, direction: Vector3(-0.4, -0.9, -0.5), intensity: 0.95)
        if temporalAA { temporalAntialiasing() }

        // Four rods from half a pixel to two pixels thick, the thin ones for the
        // beading and the thick one for the staircase.
        fill(Color(white: 0.92))
        let heights = [0.012, 0.02, 0.032, 0.05]
        for (i, height) in heights.enumerated() {
            withState {
                translate(0, 0.9 + Double(i) * 0.2, 0)
                rotate(0.028 + Double(i) * 0.014, axis: .unitZ)
                drawBox(width: 5.4, height: height, depth: 0.04)
            }
        }
    }
}
