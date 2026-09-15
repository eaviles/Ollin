// figure: frame=0 themed
//
// Guide diagram (Chapter 29): a grain cloud has two clocks where every other
// source has one. The top row is three panels of the same cloud, differing
// only in speed: time runs across, where in the sound each grain was cut from
// runs up, and every grain is a dot. At speed 1 the dots run diagonally,
// which is a recording played through; at 0.25 the same sound is crawled
// through at a quarter of the speed with nothing moved in pitch; at 0 they
// lie flat, which is one moment held. The band around them is the jitter.
// The bottom row is the six shapes a grain is cut with, each read from the
// shipped curve rather than drawn here, so the picture cannot disagree with
// the sound.
import Ollin
import OllinAudio
import OllinDiagram

final class GrainClouds: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.14) }
    var accent: Color { theme.accent }

    /// The cloud the three panels share. Only `speed` differs between them.
    let cloud = GrainCloud(size: 0.06, density: 26, positionJitter: 0.05)
    /// How much of the sound each panel shows going by.
    let span = 4.0

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let takes: [(Double, String)] = [
            (1, "speed 1: played through"),
            (0.25, "speed 0.25: crawled through"),
            (0, "speed 0: one moment, held"),
        ]
        let panelWidth = 240.0, gap = 40.0
        let left = (880 - (panelWidth * 3 + gap * 2)) / 2
        for (index, take) in takes.enumerated() {
            let panel = Rectangle(x: left + Double(index) * (panelWidth + gap), y: 60,
                                  width: panelWidth, height: 230)
            drawScatter(panel, speed: take.0, title: take.1, seed: 11 + index)
        }

        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.center, .middle)
        drawText("where in the sound each grain was cut from, against when it sounds",
                 440, 320)

        drawShapes(top: 400)
        diagramCaption("two clocks: the grains keep the note's pitch, the reading keeps its own speed",
                       at: 588, theme: theme)
    }

    /// One panel: time across, position in the sound up, a dot per grain.
    private func drawScatter(_ panel: Rectangle, speed: Double, title: String, seed: Int) {
        diagramFrame(panel, title: title, theme: theme)
        let inner = Rectangle(x: panel.x + 14, y: panel.y + 12,
                              width: panel.width - 28, height: panel.height - 28)

        // The band the grains come out of: where the reading has got to, as
        // wide either side as the jitter lets a grain stray.
        func reading(at t: Double) -> Double { fract(0.2 + speed * t / span) }
        noStroke()
        fill(theme.accent(0.16))
        let steps = 120
        for step in 0..<steps {
            let t = span * Double(step) / Double(steps)
            let x = inner.x + inner.width * Double(step) / Double(steps)
            let center = reading(at: t)
            // Drawn as two pieces where the band runs off an edge, since the
            // sound comes round rather than running out.
            for offset in [-1.0, 0, 1] {
                let top = center + offset + cloud.positionJitter
                let bottom = center + offset - cloud.positionJitter
                guard top > 0, bottom < 1 else { continue }
                let high = inner.bottomRight.y - min(1, top) * inner.height
                let low = inner.bottomRight.y - max(0, bottom) * inner.height
                drawRect(corner: Vector2(x, high),
                         width: inner.width / Double(steps) + 0.6, height: low - high)
            }
        }

        // The grains themselves, one dot each, arriving at the cloud's own
        // average rate and straying by its own jitter.
        var rng = SplitMix64(seed: UInt64(seed))
        var t = 0.0
        while t < span {
            let center = reading(at: t)
            let stray = Double.random(in: -1 ... 1, using: &rng) * cloud.positionJitter
            let place = fract(center + stray)
            fill(accent)
            drawCircle(inner.x + inner.width * t / span,
                       inner.bottomRight.y - place * inner.height, 2.6)
            // The gap between onsets is random with the cloud's own average,
            // which is what `scatter` at 1 means.
            t += -log(max(1e-9, Double.random(in: 0 ... 1, using: &rng))) / cloud.density
        }

        noStroke()
        fill(soft)
        textSize(11)
        textAlign(.right, .top)
        drawText("end", inner.x - 6, inner.y - 2)
        textAlign(.right, .bottom)
        drawText("start", inner.x - 6, inner.bottomRight.y + 4)
    }

    /// The six shapes a grain is cut with, read off the shipped curve.
    private func drawShapes(top: Double) {
        let names: [(GrainShape, String)] = [
            (.bell, "bell"), (.gaussian, "gaussian"), (.triangle, "triangle"),
            (.plateau, "plateau"), (.tick, "tick"), (.swell, "swell"),
        ]
        let boxWidth = 118.0, gap = 18.0
        let left = (880 - (boxWidth * 6 + gap * 5)) / 2
        for (index, take) in names.enumerated() {
            let box = Rectangle(x: left + Double(index) * (boxWidth + gap), y: top,
                                width: boxWidth, height: 112)
            noFill()
            stroke(faint)
            strokeWeight(1)
            drawLine(box.x, box.bottomRight.y, box.topRight.x, box.bottomRight.y)

            stroke(index == 0 ? ink : accent)
            strokeWeight(2)
            drawPolyline((0...110).map { step in
                let t = Double(step) / 110
                return Vector2(box.x + box.width * t,
                               box.bottomRight.y - take.0.level(at: t) * (box.height - 16))
            })
            noStroke()
            fill(soft)
            textSize(12)
            textAlign(.center, .top)
            drawText(take.1, box.center.x, box.bottomRight.y + 8)
        }

        noStroke()
        fill(soft)
        textSize(13)
        textAlign(.center, .middle)
        drawText("the shape one grain is cut with, which at these lengths is most of the sound",
                 440, top - 28)
    }
}
