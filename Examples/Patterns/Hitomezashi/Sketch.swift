import Ollin

/// Hitomezashi stitching: every grid line carries a row of unit dashes, and one
/// bit per line decides whether its dashes start on the edge or one cell in.
/// The shifted lines join at the crossings into steps, staircases, and loops,
/// so a handful of coin flips reads as a woven cloth.
///
/// The design is a pure function of the seed, so it's computed once and held.
/// Both faces draw: the two-tone parity fill underneath (every hitomezashi
/// design two-colors exactly, region against region), the stitches over it.
/// A slow tide of noise leans the fill tones back and forth, so the cloth
/// breathes while the stitching holds still.
@main
final class HitomezashiStitches: Sketch {
    private var design: Hitomezashi?

    override func draw() {
        let design = self.design ?? {
            seed(11)
            let made = hitomezashi(in: bounds.inset(by: .all(60 * scale)),
                                   columns: 26, rows: 26)
            self.design = made
            return made
        }()

        background(Color(hex: 0x101A33))   // deep indigo cloth

        let low = Color(hex: 0x18264A)     // the sunken tone
        let high = Color(hex: 0x2C4A7F)    // the raised tone
        noStroke()
        for (cell, tone) in zip(design.grid.cells, design.parities) {
            let tide = signedNoise(cell.center.x * 0.002, cell.center.y * 0.002,
                                   time * 0.4) * 0.2
            let t = (tone ? 0.85 : 0.15) + tide
            fill(Color.mix(low, high, t: t))
            drawRect(cell.frame)
        }

        stroke(Color(hex: 0xF2E9DC))       // warm thread
        strokeWeight(5 * scale)
        strokeCap(.round)
        for dash in design.stitches {
            drawPolyline(dash.points, closed: false)
        }
    }
}
