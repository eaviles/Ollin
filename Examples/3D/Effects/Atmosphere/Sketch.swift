import Ollin

/// Atmosphere: the cheap distance cue and the physical outdoor air, on one colonnade.
///
/// `fog` is the cheapest depth cue there is: every surface fades toward the fog
/// color with distance, so near columns stand crisp while far ones dissolve into
/// the air, and the eye reads the space's depth at a glance. The `heightFalloff`
/// makes the atmosphere pool low like morning mist: the density is full at the
/// floor and thins exponentially with altitude, so the column feet drown while the
/// tall tops rise clear, and the tallest read like peaks over a cloud sea. The fog
/// is computed exactly (a closed-form integral, not a per-frame blur), so it costs
/// almost nothing; the slow breathing of the density is just a parameter moving.
///
/// **Hold the space bar** and the same colonnade stands in real outdoor air
/// instead. Over distance the air itself takes part in the picture: short
/// wavelengths scatter out of a surface's light first, so a far column warms and
/// darkens, while sunlight scatters *into* the view path, veiling it in blue and
/// brightening the air toward the sun. `aerialPerspective()` computes both in
/// closed form (fog's one integral, split by wavelength), so the colonnade recedes
/// into the sky the way a real one does instead of fading toward one flat color.
/// With a `.sky` environment the haze follows the sky's own sun, rotation
/// included: drop the sun low and the light it feeds the air reddens with it.
/// `density` is the air's optical depth per world unit (leave the call bare and it
/// derives one from the camera framing); `haziness` trades the crisp molecular
/// blue-shift for a gray aerosol veil with a bright halo around the sun. One frame
/// runs one of the two: the last call wins. A new `variation` re-scatters the
/// whole colonnade.
@main
final class Atmosphere: Sketch {

    @Param(0 ... 0.08, icon: "cloud.fog", group: "Air") var density = 0.035
    @Param(0 ... 1, icon: "sun.haze", group: "Air") var haziness = 0.3
    @Param(0.06 ... 1.35, icon: "sun.max", group: "Sun") var sunHeight = 0.34
    @Param(0 ... 6.28, icon: "location.north.line", group: "Sun") var sunAround = 4.4

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
        let aerial = isKeyDown(" ")
        let fogTint = Color(hex: 0xB4BDC9)

        cameraShowcase(.turntable(period: 64), target: Vector3(0, 1.1, 0),
                       radius: 12, elevation: 0.2, fieldOfView: .pi / 4)

        if aerial {
            background(.black)
            toneMap(.aces)
            // The sky is the backdrop and the ambient; a warm key rides the same sun
            // direction so lit faces catch it while shadow faces keep the sky's cool.
            // The aerial haze reads its sun from the environment (rotation included).
            environment(.sky(turbidity: 2.4, sunElevation: sunHeight).rotated(sunAround))
            let ce = cos(sunHeight)
            directionalLight(Color(hue: 0.09, saturation: 0.35, brightness: 1.0),
                             direction: Vector3(sin(sunAround) * ce, -sin(sunHeight),
                                                -cos(sunAround) * ce),
                             intensity: 1.15)
            aerialPerspective(density: density, haziness: haziness)
        } else {
            background(fogTint)
            directionalLight(Color(hue: 0.10, saturation: 0.12, brightness: 1.0),
                             direction: Vector3(0.5, 0.85, 0.3), intensity: 0.9)
            ambientLight(Color(white: 0.22))
            // The mist: pooled low (the falloff thins it with altitude), breathing
            // slowly. Try `heightFalloff: 0` for an even, all-altitude haze.
            fog(fogTint, density: 0.16 + sin(time * 0.25) * 0.05, heightFalloff: 0.55)
        }

        // The ground plane, oversized so the horizon is air, not an edge.
        fill(Color(hex: 0x717A7E))
        drawGround(size: 44, thickness: 1)

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

        drawCaption(aerial
            ? "Aerial perspective (release space for fog)"
            : "Fog (hold space for aerial perspective)")
    }
}
