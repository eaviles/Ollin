// figure: frame=0 themed
//
// Docs diagram (Drawing/LocalAverages.md): the summed-area-table lookup.
// Each table read holds the sum of everything above and to the left of its
// corner, so the sum over any rectangle is D - B - C + A: four lookups,
// wherever the box sits and however big it is.
import Ollin

final class SummedAreaLookup: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.55) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.18) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    // The box's corners, as fractions of the table.
    let left = 3.0 / 11, right = 9.0 / 11
    let top = 2.0 / 7, bottom = 6.0 / 7

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        // The table, with the queried box shaded and its four corners read.
        let grid = Rectangle(x: 70, y: 52, width: 330, height: 210)
        stroke(faint)
        strokeWeight(1)
        for column in 0...11 {
            let x = grid.x + grid.width * Double(column) / 11
            drawLine(x, grid.y, x, grid.y + grid.height)
        }
        for row in 0...7 {
            let y = grid.y + grid.height * Double(row) / 7
            drawLine(grid.x, y, grid.x + grid.width, y)
        }
        let boxRect = Rectangle(x: grid.x + grid.width * left,
                                y: grid.y + grid.height * top,
                                width: grid.width * (right - left),
                                height: grid.height * (bottom - top))
        noStroke()
        fill(wash)
        drawRect(boxRect)
        corner(at: Vector2(boxRect.x, boxRect.y), name: "A", dx: -10, dy: -10)
        corner(at: Vector2(boxRect.x + boxRect.width, boxRect.y),
               name: "B", dx: 10, dy: -10)
        corner(at: Vector2(boxRect.x, boxRect.y + boxRect.height),
               name: "C", dx: -10, dy: 10)
        corner(at: Vector2(boxRect.x + boxRect.width, boxRect.y + boxRect.height),
               name: "D", dx: 10, dy: 10)

        // The arithmetic: one mini table per read, its lookup region shaded.
        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .middle)
        drawText("each read: the sum above and left of its corner", 656, 88)
        mini(x: 452, cornerX: right, cornerY: bottom, name: "D")
        sign("−", x: 548)
        mini(x: 560, cornerX: right, cornerY: top, name: "B")
        sign("−", x: 656)
        mini(x: 668, cornerX: left, cornerY: bottom, name: "C")
        sign("+", x: 764)
        mini(x: 776, cornerX: left, cornerY: top, name: "A")

        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("sum of the shaded box = D − B − C + A", 440, 296)
    }

    func corner(at point: Vector2, name: String, dx: Double, dy: Double) {
        noStroke()
        fill(accent)
        drawCircle(center: point, radius: 4)
        textSize(16)
        textAlign(dx < 0 ? .right : .left, dy < 0 ? .bottom : .top)
        drawText(name, point.x + dx, point.y + dy)
    }

    // A small copy of the table with the region one lookup sums shaded:
    // everything above and to the left of its corner.
    func mini(x: Double, cornerX: Double, cornerY: Double, name: String) {
        let r = Rectangle(x: x, y: 120, width: 84, height: 56)
        noStroke()
        fill(wash)
        drawRect(r.x, r.y, r.width * cornerX, r.height * cornerY)
        noFill()
        stroke(faint)
        strokeWeight(1)
        drawRect(r)
        noStroke()
        fill(accent)
        drawCircle(r.x + r.width * cornerX, r.y + r.height * cornerY, 3.5)
        fill(ink)
        textSize(16)
        textAlign(.center, .top)
        drawText(name, r.x + r.width / 2, r.y + r.height + 12)
    }

    func sign(_ glyph: String, x: Double) {
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .middle)
        drawText(glyph, x, 148)
    }
}
