import Ollin

/// Tone-mapping — the canvas composites in linear floating-point, so light can
/// pile up *past* full brightness. A handful of colored lamps orbit and overlap
/// with `blendMode(.add)`, summing as light; where they cross, the color runs
/// well above 1.0. A tone-map decides what happens to those out-of-range values
/// on an ordinary screen.
///
/// Press any key to cycle the mapping, and watch the bright cores:
///
///   • `.clamp`    — the standard look: anything past full clips flat to white,
///                   so overlaps turn into a hard, detail-less blob.
///   • `.reinhard` — `x / (1 + x)`: every value is squeezed under 1.0, so the
///                   cores keep their hue instead of blowing out, if a touch flat.
///   • `.aces`     — a film-like S-curve: highlights roll off smoothly with
///                   contrast and saturation held in the midtones — the glow look.
///
/// Drag left↔right to change `exposure` (the brightness dial): push it up and even
/// `.aces` saturates; pull it down and the whole scene dims into its falloff. This
/// is the precision the depth-of-field "sandpainting" track rides on — faint light
/// summed in float, then mapped down at the very end.
@main
final class ToneMapping_Example: Sketch {
    private let modes: [ToneMap] = [.aces, .reinhard, .clamp]
    private let names = ["ACES", "Reinhard", "Clamp (SDR)"]
    private var modeIndex = 0

    // Six lamps, each a saturated light on its own slow Lissajous orbit.
    private struct Lamp { var hue, fx, fy, px, py: Double }
    private var lamps: [Lamp] = []

    override func setup() {
        seed(7)
        for i in 0 ..< 6 {
            lamps.append(Lamp(hue: Double(i) / 6,
                              fx: random(0.10, 0.22), fy: random(0.10, 0.22),
                              px: random(.tau), py: random(.tau)))
        }
    }

    override func keyPressed() {
        modeIndex = (modeIndex + 1) % modes.count
    }

    override func draw() {
        background(Color(hex: 0x05060A))

        // Drag to expose; otherwise sit at a value that pushes overlaps past 1.0.
        let exposure = mouseIsPressed ? map(mouseX, 0, width, 0.3, 3.0) : 1.5
        toneMap(modes[modeIndex], exposure: exposure)

        blendMode(.add)            // every lamp adds light to the frame
        noStroke()

        let r = shortSide * 0.26
        for lamp in lamps {
            let cx = width / 2 + sin(time * lamp.fx * .tau + lamp.px) * width * 0.24
            let cy = height / 2 + sin(time * lamp.fy * .tau + lamp.py) * height * 0.24
            // A bright, saturated core fading to clear — additive, so the rims
            // wash together and the cores stack into HDR highlights.
            let core = Color(hue: lamp.hue, saturation: 0.85, brightness: 1, alpha: 0.95)
            fill(.radial(center: Vector2(cx, cy), radius: r,
                         Ramp(stops: [(0.0, core),
                                      (0.5, Color(hue: lamp.hue, saturation: 0.9,
                                                  brightness: 1, alpha: 0.35)),
                                      (1.0, Color(hue: lamp.hue, saturation: 0.9,
                                                  brightness: 1, alpha: 0))])))
            drawCircle(cx, cy, r)
        }

        blendMode(.normal)
        let expoNote = mouseIsPressed ? String(format: "exposure %.2f", exposure) : "drag to expose"
        drawCaption("tone-map: \(names[modeIndex])  ·  \(expoNote)  ·  press a key to cycle")
    }
}
