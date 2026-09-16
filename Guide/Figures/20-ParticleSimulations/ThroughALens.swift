// figure: frame=0
//
// Guide figure (Chapter 20): the same scene of lines through three lenses. One
// probe, the ring sphere of the LineSpray example, is rendered three times
// through OllinApp.image(of:) with only the lens's strength changed: no lens,
// so every ring is sharp near and far; the example's own lens; and one opened
// wide. Each panel is the real developed print after two hundred passes of
// the running mean, so the bokeh is what the running mean converged to rather
// than a blur laid over a picture.
//
// ThroughALens is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class ThroughALens: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let strengths = [0.0, 0.095, 0.3]
    /// The three prints, kept so a second pass draws the same pixels.
    private var prints: [Image] = []

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if prints.isEmpty {
            for strength in strengths {
                let probe = RingProbe()
                probe.strength = strength
                if let print = OllinApp.image(of: probe, frame: 40) {
                    prints.append(Image(cgImage: print))
                }
            }
        }

        let side = 260.0, gap = 30.0, top = 60.0
        let left = (width - side * 3 - gap * 2) / 2
        let titles = ["strength 0: no lens", "strength 0.095: the example's lens", "strength 0.3: wide open"]
        let notes = ["every ring sharp, near and far",
                     "the near rim in focus, the far side dissolving",
                     "only the plane of focus survives"]
        for (i, print) in prints.enumerated() {
            let panel = Rectangle(x: left + Double(i) * (side + gap), y: top, width: side, height: side)
            drawImage(print, in: panel)
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(panel)
            noStroke()
            drawText(titles[i], panel.center.x, top - 22, size: 16, color: theme.ink, align: .center, .middle)
            drawText(notes[i], panel.center.x, top + side + 12, size: 12, color: theme.muted, align: .center, .top)
        }

        diagramCaption("one scene of lines, three lenses: each print is the running mean, developed",
                       at: 358, theme: theme)
    }
}

/// The ring sphere, the scene of the `Rendering/LineSpray` example: a hundred
/// and fifty rings of latitude nudged by a curl field and lit from one side,
/// with a burst of short bright spokes at the center.
final class RingProbe: Sketch {
    override var canvasSize: CanvasSize { .size(260, 260) }

    var strength = 0.095
    private var spray: LineSpray!

    override func setup() {
        seed(3)
        spray = makeLineSpray(buildScene(), sampling: .perLine(10), passesPerFrame: 5,
                              bokeh: Bokeh(focalDistance: 49.19, strength: strength, minSize: 0.015))
    }

    override func draw() {
        background(.black)
        camera(.orbiting(target: .zero, radius: 49,
                         azimuth: -26.57 * .pi / 180, elevation: -24.09 * .pi / 180,
                         fieldOfView: 20 * .pi / 180, near: 2, far: 200))
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: 72, ground: Color(red: 21 / 255, green: 16 / 255, blue: 16 / 255)).image, 0, 0)
    }

    private func buildScene() -> [SprayLine] {
        var lines: [SprayLine] = []
        let light = Vector3(0.2, 0.35, 0.5).normalized
        for j in 0 ..< 150 {
            let latitude = Double(j) / 150 * .pi
            let ringRadius = -sin(latitude), z = cos(latitude)
            let segments = 70 + Int(abs(floor(ringRadius * 360)))
            for i in 0 ..< segments {
                let a1 = Double(i) / Double(segments) * .tau
                let a2 = Double(i + 1) / Double(segments) * .tau
                let r = random() > 0.92 ? 5.9 : 5.75
                let p1 = Vector3(cos(a1) * ringRadius * r, sin(a1) * ringRadius * r, z * r)
                let p2 = Vector3(cos(a2) * ringRadius * r, sin(a2) * ringRadius * r, z * r)
                let q1 = p1 + displacement(p1), q2 = p2 + displacement(p2)
                let diffuse = pow(max(p1.normalized.dot(light), 0), 3)
                let radiance = 0.1 * diffuse + 0.002
                lines.append(line(q1, q2, radiance))
                if random() > 0.975 {
                    let boost = random() > 0.8 ? 6.0 : 2.0
                    let inner = 0.1 + random() * 0.3
                    let outer = inner + pow(random(), 2) * 0.25
                    lines.append(line(q1 * inner, q1 * outer, boost * radiance))
                }
            }
        }
        return lines
    }

    private func displacement(_ p: Vector3) -> Vector3 {
        let strength = 0.1 + curlNoise(p * 0.15).normalized.x * 0.7
        return curlNoise(p * 0.5).normalized * strength
    }

    private func line(_ a: Vector3, _ b: Vector3, _ radiance: Double) -> SprayLine {
        SprayLine(from: a, to: b, light: SIMD3(repeating: radiance))
    }
}
