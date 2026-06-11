import Ollin

/// The same two colors mixed band by band in each interpolation space, so the
/// differences sit side by side: RGB dips through gray, HSB detours around
/// the hue wheel, and the OK family stays perceptually even. The endpoints
/// drift around the hue wheel over time, picked in OKHSL so their perceived
/// lightness holds still while they travel.
@main
final class Mixing: Sketch {
    let spaces: [(label: String, space: ColorSpace)] = [
        ("RGB", .rgb),
        ("HSB", .hsb),
        ("OKLAB", .oklab),
        ("OKLCH", .oklch),
        ("OKHSL", .okhsl),
    ]

    override func setup() {
        noStroke()
        textSize(26)
    }

    override func draw() {
        background(Color(hex: 0x14171C))
        let a = Color(OKHSL(h: time * 0.02, s: 0.95, l: 0.55))
        let b = Color(OKHSL(h: time * 0.02 + 0.45, s: 0.95, l: 0.7))

        let margin = width * 0.08
        let bandWidth = width - margin * 2
        let bandHeight = height * 0.1
        let gap = (height - Double(spaces.count) * bandHeight) / Double(spaces.count + 1)
        let columns = 180
        for (row, entry) in spaces.enumerated() {
            let y = gap + Double(row) * (bandHeight + gap)
            for i in 0..<columns {
                let t = Double(i) / Double(columns - 1)
                fill(Color.mix(a, b, t: t, in: entry.space))
                drawRect(margin + bandWidth * Double(i) / Double(columns), y,
                         bandWidth / Double(columns) + 1, bandHeight)
            }
            fill(Color(hex: 0x9AA3AD))
            drawText(entry.label, margin, y - 14)
        }
    }
}
