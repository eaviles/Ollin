// figure: frame=0 themed
//
// Guide figure (Chapter 31): the path-traced export, in the exported pixels
// themselves. One small set, three spheres on a floor under one softbox, is
// rendered three times through OllinApp.image(of:): as the window rasterizes
// it, with OllinApp.pathTracedExport set the way `--path-traced 96` sets it,
// and once more with the grain filter on, the way `--denoise` sets it. The
// sketch is the same in all three; only the export mode changes, which is the
// whole claim of the flag. The panels are the real renders, not pictures of
// them, and the tracer is a pure function of the pixel and the sample index,
// so they render the same every time.
//
// TracedLight is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class TracedLight: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The three renders, made once and kept: the themed second pass draws
    /// the same pixels rather than tracing the set again.
    private var renders: [Image] = []

    let modes: [(title: String, tracing: PathTracing?, notes: [String])] = [
        ("the window, rasterized", nil,
         ["a hard-edged shadow", "no light bounced off the spheres"]),
        ("--path-traced 96", PathTracing(samplesPerPixel: 96),
         ["soft shadows, red bled onto the floor", "light bent through the glass"]),
        ("--path-traced 96 --denoise", PathTracing(samplesPerPixel: 96, denoises: true),
         ["the grain filtered out", "the edges kept"]),
    ]

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if renders.isEmpty { renders = modes.map { render($0.tracing) } }

        let tile = 264.0, tall = 198.0, gap = 24.0, top = 62.0
        let left = (width - tile * 3 - gap * 2) / 2
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

        diagramCaption("the same sketch, the same lights: the flag renders it by following the light",
                       at: 330, theme: theme)
        drawText("the window is the viewfinder and the flag is the film back; every lamp in the frame throws a shadow",
                 width / 2, 360, size: 13, color: theme.muted, align: .center, .top)
    }

    /// Render the set under one export mode. The mode is a global dial, so it
    /// goes back where it was before the figure's own render continues.
    private func render(_ tracing: PathTracing?) -> Image {
        let previous = OllinApp.pathTracedExport
        OllinApp.pathTracedExport = tracing
        let exported = OllinApp.image(of: SetProbe())
        OllinApp.pathTracedExport = previous
        guard let exported else { return Image(width: 1, height: 1) }
        return Image(cgImage: exported)
    }
}

/// The probe: a matte red sphere, a solid amber glass one, and a chrome one
/// on a pale floor, under one warm softbox from the left. Each surface is there
/// for what tracing does to it: the red bleeds onto the floor, the glass bends
/// the light and tints its shadow, the chrome mirrors the set.
final class SetProbe: Sketch {
    override var canvasSize: CanvasSize { .size(528, 396) }

    override func draw() {
        background(Color(hex: 0x14161B))
        // A dark room and one softbox, close and from the front left, so the panel
        // is the light and every sphere throws its shadow back and to the right,
        // onto floor a camera looking down from the front can see.
        environment(.studio.intensified(to: 0.12))
        rectangleLight(Color(hue: 0.09, saturation: 0.3, brightness: 1.0),
                       at: Vector3(-2.8, 2.6, 2.2), direction: Vector3(0.68, -0.5, -0.53),
                       width: 2.0, height: 1.5, intensity: 30)
        castShadows()
        shadowSamples(8)

        camera(Camera3D(eye: Vector3(0.3, 3.2, 6.0), target: Vector3(0, 0.3, -0.2),
                        projection: .perspective(fieldOfView: .pi / 4.4)))

        withState {
            translate(0, -0.5, 0)
            fill(Color(white: 0.72))
            material(.dielectric(roughness: 0.55))
            drawBox(width: 16, height: 1, depth: 12)
        }

        let finishes: [(Color, Material)] = [
            (Color(hue: 0.01, saturation: 0.8, brightness: 0.85), .dielectric(roughness: 0.4)),
            (Color(hue: 0.1, saturation: 0.45, brightness: 1.0),
             .glass(thickness: 1, attenuationColor: Color(hue: 0.09, saturation: 0.75, brightness: 0.9),
                    attenuationDistance: 0.9)),
            (Color(white: 0.95), .metal(roughness: 0.04)),
        ]
        for (i, f) in finishes.enumerated() {
            withState {
                translate(-2.1 + Double(i) * 2.1, 0.7, 0)
                fill(f.0)
                material(f.1)
                drawSphere(radius: 0.7)
            }
        }
    }
}
