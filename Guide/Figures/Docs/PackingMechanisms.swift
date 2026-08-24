// figure: frame=0 themed
//
// Docs diagram (Generators/Packing.md): the three packing mechanisms on the
// same panel size. Self-seeding packCircles(count:) grows big circles first
// and fills the gaps, packCircles(around:) grows one circle per handed point
// until neighbors meet, and relaxCircles pushes your own sized, overlapping
// circles apart while holding every radius fixed.
import Ollin

final class PackingMechanisms: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.55) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.22) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.10) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)
        seed(11)

        // Panel 1: self-seeding, biggest circles land first, small ones fill.
        let r1 = Rectangle(x: 42, y: 42, width: 248, height: 200)
        show(packCircles(in: r1, count: 220, minRadius: 3, maxRadius: 46,
                         padding: 2),
             in: r1, caption: "packCircles(count:)",
             note: "self-seeded, gaps filled")

        // Panel 2: one circle per handed point, grown until neighbors meet.
        let r2 = Rectangle(x: 316, y: 42, width: 248, height: 200)
        let sites = poissonDisk(in: r2, radius: 34)
        show(packCircles(around: sites, in: r2, padding: 2),
             in: r2, caption: "packCircles(around:)",
             note: "one circle per point, an even foam")

        // Panel 3: circles sized by hand, overlaps pushed apart, radii kept.
        let r3 = Rectangle(x: 590, y: 42, width: 248, height: 200)
        let sized = poissonDisk(in: r3, radius: 34).map {
            Circle(center: $0, radius: random(8, 22))
        }
        show(relaxCircles(sized, in: r3, iterations: 60, padding: 2),
             in: r3, caption: "relaxCircles",
             note: "your radii, pushed apart")
    }

    func show(_ circles: [Circle], in panel: Rectangle,
              caption: String, note: String) {
        noFill()
        stroke(faint)
        strokeWeight(1)
        drawRect(panel)
        fill(wash)
        stroke(ink)
        strokeWeight(1.5)
        drawCircles(circles)
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText(caption, panel.x + panel.width / 2, panel.y + panel.height + 16)
        fill(soft)
        textSize(14)
        drawText(note, panel.x + panel.width / 2, panel.y + panel.height + 42)
    }
}
