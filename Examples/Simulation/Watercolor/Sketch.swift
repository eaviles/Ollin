import Ollin

/// Wet paint on rough paper: a `Sim.watercolor` field painted like a real sheet.
/// A short scripted painting runs on its own: a broad ultramarine wash (watch
/// its edge darken as it sits), a rose charged into it wet-in-wet, then the
/// wash is blotted and a held drop of clean water blooms a backrun through the
/// damp paint, and finally the sheet dries and a yellow band glazes across
/// everything, mixing optically where it crosses. Take over any time: drag to
/// paint, keys 1-3 pick a pigment, W is clean water (hold it in a damp wash to
/// bloom), B blots the standing water, D dries the sheet for the next glaze.
@main
final class WatercolorPainting: Sketch {
    private var paint: WatercolorField!
    private var pigment = 0        // current brush: 0-2 = palette, 3 = clean water
    private var tookOver = false   // first click ends the scripted painting

    @Param(0 ... 0.08, icon: "drop") var edgeDarkening = 0.04
    @Param(icon: "cloud.rain") var backruns = true
    @Param(0 ... 0.8, icon: "paintbrush") var dryBrush = 0.0

    override func setup() {
        paint = watercolor(.watercolor(pigments: [.frenchUltramarine, .quinacridoneRose, .cadmiumYellow],
                                       paperSeed: Double(variation)))
    }

    override func draw() {
        paint.sim = .watercolor(pigments: [.frenchUltramarine, .quinacridoneRose, .cadmiumYellow],
                                edgeDarkening: edgeDarkening, backruns: backruns,
                                dryBrush: dryBrush, paperSeed: Double(variation))

        withField(paint) {
            noStroke()   // a stroked mark would ring every stamp with pigment-free water
            if !tookOver { autoPaint() }
            if mouseIsPressed {
                let color = pigment < 3 ? paint.ink(pigment, load: 0.5, water: 0.9)
                                        : paint.water(0.9)
                fill(color)
                drawCircle(mouseX, mouseY, 26)
            }
        }
        drawImage(paint.image, 0, 0)
    }

    override func mousePressed() { tookOver = true }

    override func keyPressed() {
        switch key {
        case "1": pigment = 0
        case "2": pigment = 1
        case "3": pigment = 2
        case "w": pigment = 3
        case "b": paint.blot()
        case "d": paint.dry()
        default: break
        }
    }

    /// The scripted painting: wash, wet-in-wet charge, blot + a held water drop
    /// (the backrun bloom), dry, glaze. Brush touches land on their frames and
    /// the simulation does the rest; the water drop is *held* over a stretch of
    /// frames because that is what blooms (a single tap only nudges).
    private func autoPaint() {
        switch frameCount {
        case 1:
            brushLine(from: Vector2(210, 390), to: Vector2(870, 430), radius: 82,
                      color: paint.ink(0, load: 0.5))
        case 120:
            brushLine(from: Vector2(360, 410), to: Vector2(700, 440), radius: 38,
                      color: paint.ink(1, load: 0.6, water: 0.6))
        case 300:
            paint.blot()
        case 310 ... 360:
            fill(paint.water(0.8))
            drawCircle(520, 400, 40)
        case 560:
            paint.dry()
        case 580:
            brushLine(from: Vector2(470, 140), to: Vector2(520, 940), radius: 58,
                      color: paint.ink(2, load: 0.35))
        default: break
        }
    }

    /// A single brush touch: overlapping stamps along a gently wobbling path.
    private func brushLine(from a: Vector2, to b: Vector2, radius: Double, color: Color) {
        fill(color)
        let steps = max(1, Int(a.distance(to: b) / (radius * 0.35)))
        for i in 0 ... steps {
            let t = Double(i) / Double(steps)
            let p = a.lerp(to: b, t) + Vector2(0, sin(t * .tau * 1.4) * radius * 0.2)
            drawCircle(p.x, p.y, radius)
        }
    }
}
