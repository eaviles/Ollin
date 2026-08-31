import Ollin

/// The same two colors mixed band by band in each interpolation space, so the
/// differences sit side by side: RGB dips through gray, HSB detours around
/// the hue wheel, the OK family stays perceptually even, and PAINT mixes the
/// two as scattering pigments (so complementary pairs meet in a real mixed
/// hue, and every mix darkens the way paint does). The endpoints drift around
/// the hue wheel over time, picked in OKHSL so their perceived lightness holds
/// still while they travel. A readout at each band's right edge reports its
/// midpoint through the `hue` / `saturation` / `brightness` read-backs, so the
/// dips and detours have numbers.
@main
final class Mixing: Sketch {
    let spaces: [(label: String, space: ColorSpace)] = [
        ("RGB", .rgb),
        // The HSB band pops now and then, on purpose: hue mixes the shortest
        // way around the wheel, and when the drifting endpoints' HSB hue gap
        // crosses half a turn, the short way switches sides in one frame. The
        // OK bands hold a fixed gap in their own hue, so only HSB flips.
        ("HSB", .hsb),
        ("OKLAB", .oklab),
        ("OKLCH", .oklch),
        ("OKHSL", .okhsl),
        ("PAINT", .paint),
    ]

    override func setup() {
        noStroke()
        textSize(26)
    }

    override func draw() {
        background(Color(hex: 0x14171C))
        let a = Color(OKHSL(h: time * 0.04, s: 0.95, l: 0.55))
        let b = Color(OKHSL(h: time * 0.04 + 0.45, s: 0.95, l: 0.7))

        let margin = width * 0.08
        let bandHeight = height * 0.1
        let gap = (height - Double(spaces.count) * bandHeight) / Double(spaces.count + 1)
        // One band per space, with an even gap above, below, and between them.
        let g = grid(columns: 1, rows: spaces.count,
                     padding: .symmetric(horizontal: margin, vertical: gap), gutter: gap)
        let samples = 180
        for (cell, entry) in zip(g.cells, spaces) {
            let band = cell.frame
            for i in 0..<samples {
                let t = Double(i) / Double(samples - 1)
                fill(Color.mix(a, b, t, in: entry.space))
                drawRect(band.x + band.width * Double(i) / Double(samples), band.y,
                         band.width / Double(samples) + 1, band.height)
            }
            fill(Color(hex: 0x9AA3AD))
            drawText(entry.label, band.x, band.y - 14)
            // Each band's midpoint, read back through `hue`/`saturation`/
            // `brightness`, the inverse of `init(hue:saturation:brightness:)`:
            // RGB's dip through gray shows as the lowest S of the column, and
            // paint's darkening as the lowest B.
            let mid = Color.mix(a, b, 0.5, in: entry.space)
            drawText("H \(Int((mid.hue * 360).rounded()))°  S \(Int((mid.saturation * 100).rounded()))  B \(Int((mid.brightness * 100).rounded()))",
                     band.x + band.width, band.y - 14, size: 20, align: .right)
        }
    }
}
