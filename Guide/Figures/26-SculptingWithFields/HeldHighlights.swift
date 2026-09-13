// figure: frame=0 themed
//
// Guide figure (Chapter 26): specular anti-aliasing, in the exported pixels
// themselves. One probe, a bed of polished balls a few pixels across under
// one hard light, is rendered three times through OllinApp.image(of:): with
// the call off, with the call off at sixteen samples a pixel (the reference,
// through the export supersample), and with the call on. The same crop of
// each render is read back and drawn one pixel per square. Off, the bed is
// dark and speckled, because one shading sample per pixel misses most of the
// highlights; the reference shows what the surface really scatters; on, every
// ball carries a broader, dimmer highlight that stays put, a touch brighter
// than the reference, which is the trade the call makes.
//
// HeldHighlights is declared first on purpose: the sketch loader compiles the
// first `class …: Sketch` it finds, so the probe has to come after it.
import Ollin
import OllinDiagram

final class HeldHighlights: Sketch {
    override var canvasSize: CanvasSize { .size(880, 376) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The page size of one probe pixel, and the crop of the probe shown.
    let cell = 7.0
    let crop = (x: 112, y: 66, width: 36, height: 26)

    /// The three renders, read back once; the dark variant redraws from the
    /// same pixels, since the probes are depicted content and do not flip.
    private var panels: [[[Color]]]?

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        if panels == nil {
            panels = [
                pixels(of: probe(filtered: false), scale: 1),
                pixels(of: probe(filtered: false), scale: 4),
                pixels(of: probe(filtered: true), scale: 1),
            ]
        }
        guard let panels else { return }

        let panelWidth = cell * Double(crop.width)
        let panelHeight = cell * Double(crop.height)
        let gap = 40.0
        let left = (width - panelWidth * 3 - gap * 2) / 2
        let top = 64.0
        let titles = ["specularAntialiasing() off", "sixteen samples a pixel", "specularAntialiasing() on"]
        let notes = ["one sample, most specks missed", "the reference", "widened, and held still"]
        for (index, rows) in panels.enumerated() {
            let x = left + Double(index) * (panelWidth + gap)
            let rect = Rectangle(x: x, y: top, width: panelWidth, height: panelHeight)
            drawPixels(rows, in: rect)
            diagramFrame(rect, title: titles[index], theme: theme)
            drawText(notes[index], rect.x + rect.width / 2, rect.y + rect.height + 12,
                     size: 15, color: theme.muted, align: .center, .top)
        }

        diagramCaption("the same exported pixels, one square each", at: 318, theme: theme)
    }

    private func probe(filtered: Bool) -> SparkleProbe {
        let probe = SparkleProbe()
        probe.specularAA = filtered
        return probe
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

    /// Render the probe headless at a render scale and read the crop back as
    /// rows of colors. The scale is a global, so it goes back where it was.
    private func pixels(of probe: Sketch, scale: Int) -> [[Color]] {
        let previous = OllinApp.exportRenderScale
        OllinApp.exportRenderScale = scale
        let rendered = OllinApp.image(of: probe)
        OllinApp.exportRenderScale = previous
        guard let rendered else { return [] }
        let image = Image(cgImage: rendered)
        return (0..<crop.height).map { row in
            (0..<crop.width).map { column in image[crop.x + column, crop.y + row] }
        }
    }
}

/// The probe: a bed of small polished balls under one hard light, seen from
/// far enough that each is a few pixels across, so its highlight is narrower
/// than the pixel it sits in. Seeded, so every render lays the same bed.
final class SparkleProbe: Sketch {
    var specularAA = false

    private let ball = Mesh.sphere(radius: 1, segments: 24, rings: 12)

    override var canvasSize: CanvasSize { .size(260, 160) }

    override func draw() {
        background(Color(white: 0.03))
        perspective(eye: Vector3(4.4, 4.0, 10.4), target: Vector3(0, 0.1, 0),
                    fieldOfView: .pi / 3.4)
        directionalLight(.white, direction: Vector3(0.35, -0.5, 0.79), intensity: 0.9)
        environment(.studio.intensified(to: 0.35))
        if specularAA { specularAntialiasing() }

        randomSeed(7)
        var balls: [MeshInstance] = []
        let side = 57
        let size = 0.07
        for row in 0..<side {
            for column in 0..<side {
                let x = -5.0 + 10.0 * Double(column) / Double(side - 1)
                let z = -5.0 + 10.0 * Double(row) / Double(side - 1)
                balls.append(MeshInstance(
                    position: Vector3(x + random(-0.03, 0.03), size, z + random(-0.03, 0.03)),
                    scale: size * random(0.85, 1.15)))
            }
        }
        fill(Color(white: 0.85))
        material(.metal(roughness: 0.1))
        drawMesh(ball, instances: balls)

        withState {
            fill(Color(white: 0.16))
            material(.dielectric(roughness: 0.7))
            translate(0, -0.02, 0)
            drawBox(width: 22, height: 0.04, depth: 22)
        }
    }
}
