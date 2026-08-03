import Ollin

/// Fog: distance and height atmosphere over a colonnade.
///
/// Fog is the cheapest depth cue there is: every surface fades toward the fog
/// color with distance, so near columns stand crisp while far ones dissolve
/// into the air, and the eye reads the space's depth at a glance. The
/// `heightFalloff` makes the atmosphere pool low like morning mist: the
/// density is full at the floor and thins exponentially with altitude, so the
/// column feet drown while the tall tops rise clear, and the tallest read
/// like peaks over a cloud sea. The fog is computed exactly (a closed-form
/// integral, not a per-frame blur), so it costs almost nothing; the slow
/// breathing of the density is just a parameter moving. A new `variation`
/// re-scatters the whole colonnade.
@main
final class Fog: Sketch {

    private struct Column {
        var position: Vector2
        var height: Double
        var radius: Double
        var tone: Double
    }
    private var columns: [Column] = []

    override func setup() {
        // A loose field of columns receding in every direction; seeded, so the
        // recorded `variation` brings this exact forest back.
        while columns.count < 110 {
            let p = Vector2(random(-17, 17), random(-17, 17))
            if p.length < 2.4 { continue }
            columns.append(Column(position: p,
                                  height: random(1.0, 5.2),
                                  radius: random(0.18, 0.55),
                                  tone: random(0.35, 0.75)))
        }
    }

    override func draw() {
        let fogTint = Color(hex: 0xB4BDC9)
        background(fogTint)

        cameraShowcase(.turntable(period: 64), target: Vector3(0, 1.1, 0),
                       radius: 12, elevation: 0.2, fieldOfView: .pi / 4)

        directionalLight(Color(hue: 0.10, saturation: 0.12, brightness: 1.0),
                         direction: Vector3(0.5, 0.85, 0.3), intensity: 0.9)
        ambientLight(Color(white: 0.22))

        // The mist: pooled low (the falloff thins it with altitude), breathing
        // slowly. Try `heightFalloff: 0` for an even, all-altitude haze.
        fog(fogTint, density: 0.16 + sin(time * 0.25) * 0.05, heightFalloff: 0.55)

        // The ground plane, oversized so the horizon is fog, not an edge.
        fill(Color(hex: 0x717A7E))
        withState {
            translate(0, -0.5, 0)
            drawBox(width: 44, height: 1, depth: 44)
        }

        // The colonnade: plain shafts with a square cap, in stone grays.
        for column in columns {
            let gray = Color(white: column.tone)
            withState {
                translate(column.position.x, column.height / 2, column.position.y)
                fill(gray)
                drawCylinder(radius: column.radius, height: column.height)
                translate(0, column.height / 2 + 0.07, 0)
                drawBox(width: column.radius * 2.6, height: 0.14, depth: column.radius * 2.6)
            }
        }
    }
}
