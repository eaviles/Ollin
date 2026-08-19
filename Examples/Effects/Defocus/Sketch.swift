import Ollin

/// Depth of field through the two-input combine path: a layer **defocused by** a
/// depth map. The depth map is just another layer — its luminance read as distance
/// (0 near … 1 far) — so it can be anything you draw. Here the scene is a scatter of
/// orbs at staggered depths, and the depth `aside` redraws each orb filled with a
/// gray that *is* its depth (black near, white far). Drag left/right to rack the
/// focal plane through them: whichever orbs sit at the focus depth stay crisp while
/// the rest melt into bokeh.
///
/// The blur is a single-pass circle-of-confusion gather, so a nearer, more defocused
/// orb spills softly over the farther ones. `focus` is the in-focus depth, `range`
/// the half-width of the sharp band, `maxBlur` how far the most defocused orbs blur.
///
/// Try it: widen `range` for a deeper focus, raise `maxBlur` for creamier bokeh, or
/// feed `.defocused(by:)` a smooth top-to-bottom gradient aside instead of the
/// per-orb map (a tilt-shift look).
@main
final class Defocus_Example: Sketch {

    /// One orb: a depth (0 near … 1 far), a screen position, and a hue.
    struct Orb { let depth, x, y, hue: Double }

    /// A fixed scatter, sorted far-first so nearer orbs occlude — in both the color
    /// scene and the depth map, which must agree on what's in front.
    lazy var orbs: [Orb] = {
        seed(7)
        return (0 ..< 48).map { _ in
            Orb(depth: random(1), x: random(1), y: random(1), hue: random(1))
        }.sorted { $0.depth > $1.depth }
    }()

    override func draw() {
        // Drag to rack focus by hand; left idle, the focal plane sweeps on its own.
        let focus = mouseIsPressed ? min(max(mouseX / width, 0), 1)
                                   : 0.5 + 0.45 * sin(time * 0.4)

        compose {
            layer {
                background(Color(white: 0.05))
                noStroke()
                for orb in orbs {
                    // Nearer orbs read brighter and larger, the usual distance cues.
                    let near = 1 - orb.depth
                    fill(Color(hue: orb.hue, saturation: 0.7, brightness: 0.45 + 0.55 * near))
                    drawCircle(orb.x * width, orb.y * height, radius(orb))
                }
            }
            .defocused(by: aside {
                background(.white)                        // gaps read as far
                noStroke()
                for orb in orbs {
                    fill(Color(white: orb.depth))         // the gray IS the depth
                    drawCircle(orb.x * width, orb.y * height, radius(orb))
                }
            }, focus: focus, range: 0.07, maxBlur: 36)
        }

        drawCaption("depth of field — focus \(String(format: "%.2f", focus)) (drag to rack)")
    }

    func radius(_ orb: Orb) -> Double { 26 + (1 - orb.depth) * 96 }
}
