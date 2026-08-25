import Ollin

/// `strokeProfile(_:)` lets a stroke change width as it travels, which is the
/// difference between a drawn line and a made mark. The profile multiplies
/// `strokeWeight`, so every cell here shares one weight and one spiral, and only
/// the profile changes.
///
/// `.uniform` holds a single width. `.taper()` swells in the middle and vanishes
/// at both ends, the shape of a brush pressed down and lifted. `.taper(start: 1)`
/// starts blunt and lifts off. `.ramp(from:to:)` cuts a straight wedge.
/// `.nib(angle:)` holds a flat calligraphy pen at a fixed angle, so the mark
/// thickens where the spiral runs across the nib and thins to a hairline where it
/// runs along it, which is why the spiral is the shape to show it on: the path
/// turns through every direction. The last cell profiles the width by hand.
///
/// The nib turns with `time` and the hand-drawn profile travels along the path.
@main
final class StrokeProfiles: Sketch {
    let names = ["uniform", "taper", "lift off", "wedge", "nib", "by hand"]

    override func draw() {
        background(Color(white: 0.09))
        noFill()

        let grid = Grid(in: bounds, columns: 3, rows: 2, padding: .all(60 * scale))
        // A profile closure runs where the stroke is expanded, so it reads what it
        // is handed rather than the sketch: copy the clock in first.
        let clock = time

        for cell in grid.cells {
            let i = cell.row * 3 + cell.column
            let radius = min(cell.frame.width, cell.frame.height) * 0.36

            withState {
                translate(cell.center.x, cell.center.y - radius * 0.12)
                stroke(rowColor(i, of: names.count))
                strokeWeight(radius * 0.19)
                strokeCap(.round)
                switch i {
                case 0: noStrokeProfile()
                case 1: strokeProfile(.taper())
                case 2: strokeProfile(.taper(start: 1, end: 0))
                case 3: strokeProfile(.ramp(from: 0.05, to: 1))
                case 4: strokeProfile(.nib(angle: clock * 0.4))
                default: strokeProfile { t in 0.12 + 0.88 * abs(sin(t * .pi * 2.5 - clock)) }
                }
                drawPolyline(spiral(radius: radius))
            }
            label(names[i], at: Vector2(cell.center.x, cell.center.y + radius * 1.28))
        }
    }

    /// An open spiral of nearly two turns, sampled densely. Two things make it the
    /// right test shape: it heads in every direction, so a direction-driven profile
    /// shows its whole range, and it is open, so the profiles that shape the ends
    /// have ends to shape. A profiled stroke reads its width at every path vertex,
    /// so a path with only a handful of points changes width in visible steps.
    func spiral(radius: Double) -> [Vector2] {
        let turns = 1.85
        return (0...260).map { i in
            let t = Double(i) / 260
            let angle = t * .tau * turns - .pi / 2
            return Vector2(angle: angle) * (radius * (0.22 + 0.78 * t))
        }
    }

    /// A caption under each cell, drawn unstroked so no profile reaches the text.
    func label(_ text: String, at p: Vector2) {
        withState {
            noStroke(); fill(.white); textAlign(.center, .baseline); textSize(22 * scale)
            drawText(text, p.x, p.y)
        }
    }

    func rowColor(_ i: Int, of count: Int) -> Color {
        Colormap.turbo.color(at: 0.18 + 0.72 * Double(i) / Double(count - 1))
    }
}
