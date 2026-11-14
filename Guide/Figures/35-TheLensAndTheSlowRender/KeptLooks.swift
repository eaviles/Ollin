// figure: frame=0 themed
//
// Guide figure (Chapter 35): a stylized finish keeps its look in a traced
// frame, in the exported pixels themselves. One set, four balls in front of a
// mirror under one softbox, is rendered twice through OllinApp.image(of:): as
// the window draws it, and with OllinApp.pathTracedExport set the way
// `--path-traced 256 --denoise` sets it. The band, the rim, the flakes, and
// the highlight are the same in both. The traced frame adds the soft shadows,
// the light bounced into the shaded sides, and the lit backs in the mirror. A
// card stands between the softbox and the polished ball, so that ball's
// highlight is cut where the card's shadow falls.
//
// KeptLooks is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class KeptLooks: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The two renders, made once and kept: the themed second pass draws the
    /// same pixels rather than tracing the set again.
    private var renders: [Image] = []

    let modes: [(title: String, tracing: PathTracing?, notes: [String])] = [
        ("the window", nil,
         ["the band, the rim, the flakes, the highlight", "hard shadows, and dark backs in the mirror"]),
        ("--path-traced 256 --denoise", PathTracing(samplesPerPixel: 256, denoises: true),
         ["the same four looks, drawn by the same formulas", "soft shadows, bounced light, lit backs in the mirror"]),
    ]

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if renders.isEmpty { renders = modes.map { render($0.tracing) } }

        let tile = 396.0, tall = 223.0, gap = 24.0, top = 62.0
        let left = (width - tile * 2 - gap) / 2
        for (i, mode) in modes.enumerated() {
            let panel = Rectangle(x: left + Double(i) * (tile + gap), y: top, width: tile, height: tall)
            noStroke()
            drawText(mode.title, panel.center.x, top - 22, size: 16, color: theme.ink, align: .center, .middle)
            drawImage(renders[i], in: panel)
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(panel)
            noStroke()
            for (j, note) in mode.notes.enumerated() {
                drawText(note, panel.center.x, top + tall + 12 + Double(j) * 16, size: 12,
                         color: theme.muted, align: .center, .top)
            }
        }

        diagramCaption("each finish keeps its look when the frame is traced",
                       at: 344, theme: theme)
    }

    /// Render the set under one export mode. The mode is a global dial, so it
    /// goes back where it was before the figure's own render continues.
    private func render(_ tracing: PathTracing?) -> Image {
        let previous = OllinApp.pathTracedExport
        OllinApp.pathTracedExport = tracing
        let exported = try? OllinApp.image(of: LooksProbe())
        OllinApp.pathTracedExport = previous
        guard let exported else { return Image(width: 1, height: 1) }
        return Image(cgImage: exported)
    }
}

/// The probe: a toon ball, a velvet one, a glitter one, and a polished one in a
/// row, a mirror standing behind them, and one softbox from the front left. A
/// narrow card stands between the softbox and the polished ball.
final class LooksProbe: Sketch {
    override var canvasSize: CanvasSize { .size(792, 446) }

    override func draw() {
        background(Color(hex: 0x14161B))
        environment(.studio.intensified(to: 0.14))
        rectangleLight(Color(hex: 0xFFF1DC), at: Vector3(-3.0, 3.4, 2.6),
                       direction: Vector3(0.6, -0.68, -0.42),
                       width: 2.4, height: 1.6, intensity: 14)
        castShadows()
        rayTracedReflections()

        camera(Camera3D(eye: Vector3(0.2, 2.6, 6.4), target: Vector3(0, 0.7, -0.4),
                        projection: .perspective(fieldOfView: .pi / 5.8)))

        withState {
            translate(0, -0.5, 0)
            fill(Color(white: 0.6))
            material(.dielectric(roughness: 0.6))
            drawBox(width: 16, height: 1, depth: 12)
        }

        // The mirror behind the row.
        withState {
            translate(0.2, 1.1, -2.1)
            rotateY(0.12)
            fill(Color(white: 0.95))
            material(.metal(roughness: 0.03))
            drawBox(width: 6.4, height: 2.2, depth: 0.12)
        }

        let finishes: [(Color, Material)] = [
            (Color(hex: 0xE8762C), .toon),
            (Color(hex: 0x6A2C8C), .velvet),
            (Color(hue: 0.98, saturation: 0.8, brightness: 0.45), .glitter),
            (Color(hex: 0x2C8C86), .polished),
        ]
        for (i, f) in finishes.enumerated() {
            withState {
                translate(-2.25 + Double(i) * 1.5, 0.55, 0)
                fill(f.0)
                material(f.1)
                drawSphere(radius: 0.55, segments: 64, rings: 32)
            }
        }

        // The card, turned to face the softbox.
        withState {
            fill(Color(white: 0.3))
            translate(1.35, 0.65, 0.65)
            rotateY(-1.15)
            drawBox(width: 0.34, height: 1.3, depth: 0.05)
        }
    }
}
