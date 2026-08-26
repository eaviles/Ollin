import Foundation
import Ollin
import OllinRemote

/// A tunable aurora, served to your phone. The sketch registers a
/// `RemoteInspector` on the extension seam, which starts a small local-network
/// server: open the address it prints (and draws, bottom of the canvas) in any
/// browser on the same Wi-Fi and every `@Param` below appears as a touch
/// control, live both ways. Drag a phone slider and the ribbons answer;
/// change a knob in the host inspector and the phone follows.
///
/// The knobs cover every control family the surface renders: sliders, a
/// toggle, a menu, a color, an XY pad, and a stepper, in three groups.
@main
final class RemoteSurface: Sketch {

    enum Palette: String, CaseIterable, ParamOption { case dawn, dusk, noir }

    @Param(0.1...4.0, group: "Motion") var speed = 1.4
    @Param(0...1, group: "Motion") var turbulence = 0.32
    @Param(group: "Motion") var trails = true

    @Param(group: "Look") var palette = Palette.dusk
    @Param(group: "Look") var accent = Color(red: 1.0, green: 0.22, blue: 0.37)
    @Param(0...1, group: "Look") var glow = 0.45

    @Param(x: 0...1, y: 0...1, style: .pad, group: "Field") var focus = Vector2(0.5, 0.38)
    @Param(1...12, group: "Field") var layers = 6

    let remote = RemoteInspector()

    override func setup() {
        extend(remote)
    }

    override func draw() {
        // Trails keep a translucent wash of the previous frames; off wipes clean.
        if trails {
            fill(base.withAlpha(0.16))
            drawRect(0, 0, width, height)
        } else {
            background(base)
        }

        let cx = focus.x * width
        let cy = focus.y * height

        noFill()
        for layer in 0..<max(1, layers) {
            let phase = Double(layer) / Double(max(1, layers))
            var points: [Vector2] = []
            let steps = 90
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let x = t * width
                let wobble = sin(t * 7 + time * speed + phase * 9)
                    + turbulence * 1.8 * sin(t * 23 + time * speed * 1.7 + phase * 31)
                let spread = 40 + phase * 190
                points.append(Vector2(x, cy + wobble * spread + (t - 0.5) * (x - cx) * 0.12))
            }
            let ink = accent.mixed(with: layerTint, phase * 0.8)

            // A wide translucent pass underneath is the glow; the crisp line rides it.
            if glow > 0.01 {
                stroke(ink.withAlpha(0.10 + glow * 0.16))
                strokeWeight(10 + glow * 22)
                drawPolyline(points)
            }
            stroke(ink.withAlpha(0.85))
            strokeWeight(1.6)
            drawPolyline(points)
        }

        // The pairing address, on the canvas itself, so the piece tells you
        // how to reach it from where you stand.
        fill(Color(white: 1).withAlpha(0.55))
        textSize(20)
        textAlign(.center)
        drawText(remote.url ?? "starting the remote surface", width / 2, height - 40)
    }

    var base: Color {
        switch palette {
        case .dawn: return Color(red: 0.13, green: 0.09, blue: 0.16)
        case .dusk: return Color(red: 0.05, green: 0.06, blue: 0.12)
        case .noir: return Color(white: 0.04)
        }
    }

    var layerTint: Color {
        switch palette {
        case .dawn: return Color(red: 1.0, green: 0.62, blue: 0.30)
        case .dusk: return Color(red: 0.36, green: 0.55, blue: 1.0)
        case .noir: return Color(white: 0.92)
        }
    }
}
