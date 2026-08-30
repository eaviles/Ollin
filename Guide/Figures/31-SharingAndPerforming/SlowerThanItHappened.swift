// figure: frame=0 themed
//
// Guide figure (Chapter 31): what slow motion actually does to a run. One
// probe, a mark crossing a track in a tenth of a second, is rendered through
// OllinApp.image(of:frame:fps:) at two clocks: the sketch's own 30 a second on
// the top row, and the 90 a second a factor of 3 asks for on the bottom. The
// tiles are real exported frames, and the top row sits directly above the
// bottom-row frames that show the same moments, so the new ones are visibly
// the moments between rather than a different run.
//
// SlowerThanItHappened is declared first on purpose: the sketch loader compiles
// the first `class …: Sketch` it finds, so the probe has to come after it.
import Ollin
import OllinDiagram

final class SlowerThanItHappened: Sketch {
    override var canvasSize: CanvasSize { .size(880, 352) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var accent: Color { theme.accent }

    /// The factor, the frames the file holds, and the tile geometry.
    let factor = 3
    let fineCount = 10
    let tile = 74.0
    let gap = 12.0

    override func setup() { noLoop() }

    override func draw() {
        background(paper)
        textFont(.system)

        let step = tile + gap
        let left = (width - (Double(fineCount) * tile + Double(fineCount - 1) * gap)) / 2
        let topY = 62.0
        let bottomY = topY + tile + 66

        // The connectors first, so the tiles sit on top of them: each drawn
        // frame is the same moment as one frame of the finer row.
        stroke(ink.withAlpha(0.22))
        strokeWeight(1)
        for k in stride(from: 0, to: fineCount, by: factor) {
            let x = left + Double(k) * step + tile / 2
            drawLine(x, topY + tile, x, bottomY)
        }

        for k in 0..<fineCount {
            let x = left + Double(k) * step
            if k % factor == 0 {
                drawFrame(SlowMotionProbe(), frame: k / factor, fps: 30,
                          at: Vector2(x, topY), marked: true)
            }
            drawFrame(SlowMotionProbe(), frame: k, fps: 90,
                      at: Vector2(x, bottomY), marked: false)
        }

        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.left, .bottom)
        drawText("what the sketch drew: four frames, 30 a second", left, topY - 12)

        fill(ink)
        textSize(19)
        textAlign(.left, .bottom)
        drawText("--slow-motion 3: 90 a second", left, bottomY - 12)
        fill(ink.withAlpha(0.62))
        textSize(16)
        textAlign(.left, .top)
        drawText("the same tenth of a second in ten frames, and the file still plays at 30, so it lasts three times as long",
                 left, bottomY + tile + 10)
    }

    /// One exported frame, drawn into its tile. A drawn frame the top row shares
    /// with the bottom one gets the accent border, so the pairs read as pairs.
    private func drawFrame(_ probe: Sketch, frame: Int, fps: Double,
                           at origin: Vector2, marked: Bool) {
        if let rendered = OllinApp.image(of: probe, frame: frame, fps: fps) {
            drawImage(Image(cgImage: rendered), origin.x, origin.y, tile, tile)
        }
        noFill()
        stroke(marked ? accent : ink.withAlpha(0.3))
        strokeWeight(marked ? 2 : 1)
        drawRect(origin.x, origin.y, tile, tile)
    }
}

/// The probe: a mark crossing its track, placed by the clock alone, so the same
/// moment renders identically however finely the clock was stepping.
final class SlowMotionProbe: Sketch {
    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        noStroke()
        fill(Color(hex: 0xDED8CE))
        drawRect(0, height * 0.5 - 1.5, width, 3)
        fill(Color(hex: 0x1E4FD8))
        let travelled = min(1, time * 8)
        drawCircle(width * (0.14 + 0.72 * travelled), height * 0.5, 13)
    }
}
