// figure: frame=0
//
// Guide payoff (Chapter 21): a lighthouse at dusk, worked out rather than
// painted. A few marks diffuse into the sky and the sea. The headland, the
// tower, a turning shutter, and a boat are drawn as a scene for light to
// meet; the lighthouse lamp throws beams through the shutter's gaps and the
// masthead lamp glows over the water. Every silhouette is outlined a few
// pixels out, read off its measured distance field. The horizon swells, the
// shutter turns, and the boat floats on the swell.
import Ollin

final class Lighthouse: Sketch {
    let night = Color(hex: 0x2A2350)
    let dusk = Color(hex: 0xE86F4A)
    let sea = Color(hex: 0x16233F)
    let deep = Color(hex: 0x080D1A)
    let sun = Color(hex: 0xFFE9B0)
    let land = Color(hex: 0x0A0D16)
    let rim = Color(hex: 0xF2C879)

    let lantern = Vector2(235, 272)

    override func draw() {
        let boat = Vector2(800, 700 + sin(time * 0.9) * 5)

        // The marks: a horizon warm above and deep below, a band of night at the
        // top, a low sun, and its path on the water. Diffusion fills in the rest.
        let marks = makeRenderTarget()
        withTarget(marks) {
            background(.clear)
            let horizon = stride(from: -20.0, through: width + 20, by: 12).map { x in
                Vector2(x, 640 + sin(x / width * 5 + time * 0.4) * 8)
            }
            drawDiffusionCurve(horizon, left: dusk, right: sea, width: 4)
            noStroke()
            fill(night)
            drawRect(0, 0, width, 24)
            fill(deep)
            drawRect(0, height - 24, width, 24)
            fill(sun)
            drawCircle(620, 606, 30)
            fill(dusk)
            drawRect(575, 690, 90, 4)
        }

        // The scene: everything the light meets. The shutter around the lamp
        // turns, and the gaps between its blades cut the light into beams.
        let scene = makeRenderTarget()
        withTarget(scene) {
            noStroke()
            fill(land)
            drawPolygon([Vector2(0, 1080), Vector2(0, 560), Vector2(90, 530),
                         Vector2(180, 486), Vector2(280, 482), Vector2(340, 540),
                         Vector2(390, 650), Vector2(440, 800), Vector2(500, 1080)])
            drawPolygon([Vector2(214, 490), Vector2(256, 490),
                         Vector2(249, 300), Vector2(221, 300)])
            for blade in 0 ..< 8 {
                let angle = time * 0.5 + Double(blade) * .tau / 8
                withState(at: lantern + Vector2(cos(angle), sin(angle)) * 30, rotation: angle) {
                    drawRect(center: .zero, width: 8, height: 13)
                }
            }
            drawPolygon([boat + Vector2(-65, -10), boat + Vector2(65, -10),
                         boat + Vector2(48, 12), boat + Vector2(-50, 12)])
            drawRect(boat.x - 2, boat.y - 104, 4, 96)
        }

        // The lamps: the lighthouse lamp, and a small one at the masthead.
        let lamps = makeRenderTarget()
        withTarget(lamps) {
            noStroke()
            fill(Color(hex: 0xFFF1C8))
            drawCircle(lantern.x, lantern.y, 12)
            fill(Color(hex: 0xFF7A50))
            drawCircle(boat.x, boat.y - 110, 6)
        }

        // The sky, then the silhouettes, then the light laid over both.
        drawImage(marks.filtered(.diffuse()).image, 0, 0)
        drawImage(scene.image, 0, 0)
        blendMode(.add)
        drawImage(scene.combined(with: lamps, .light(brightness: 6)).image, 0, 0)
        blendMode(.normal)

        // An outline a few pixels out from every silhouette, read off the field.
        let field = scene.filtered(.distanceField(maxDistance: 32))
        let band = Ramp([rim.withAlpha(0), rim, rim.withAlpha(0)])
        drawImage(field.filtered(.fieldMap(band, from: 1, to: 5)).image, 0, 0)
    }
}
