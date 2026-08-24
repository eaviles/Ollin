// figure: frame=0 themed
//
// Guide diagram: the same chart at two views. On the left the whole of it, where
// the place names are a smudge. On the right the view four notches in, where the
// same names are crisp, because nothing was re-rendered: the outlines are drawn
// through a larger transform.
import Ollin

final class ViewCloser: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.45) }

    // The chart is depicted content, identical in both themes.
    let ink = Color(hex: 0x2B2B2B)
    let land = Color(hex: 0xF0EBE0)
    let mark = Color(hex: 0xC1553C)

    /// The chart is drawn in its own 600-unit square, whatever view shows it.
    static let chart = 600.0
    /// What the zoomed panel is looking at, in chart coordinates.
    static let focus = Vector2(300, 250)

    struct Place { var at: Vector2; var name: String; var big: Bool }
    var places: [Place] = []
    var coast: [Vector2] = []

    static let syllables = ["mor", "ken", "dal", "vik", "hol", "fell", "garth", "mere"]

    override func setup() {
        textFont(OutlineFont.system)
        randomSeed(4)
        noiseSeed(4)
        coast = (0..<300).map { i in
            let lap = Double(i) / 300, angle = lap * .tau
            let r = 190 + signedNoise(loop: lap, radius: 1.6) * 74
            return Vector2(300, 280) + Vector2(cos(angle) * r, sin(angle) * r * 0.82)
        }
        places = []
        while places.count < 60 {
            let p = Vector2(random(40, 560), random(60, 500))
            guard onLand(p) else { continue }
            var name = ""
            for _ in 0..<2 { name += randomChoice(ViewCloser.syllables) ?? "vik" }
            places.append(Place(at: p, name: name.prefix(1).uppercased() + name.dropFirst(),
                                big: random() < 0.2))
        }
    }

    override func draw() {
        background(paper)
        panel(Rectangle(x: 24, y: 24, width: 400, height: 310), zoom: 1, caption: "the whole of it")
        panel(Rectangle(x: 456, y: 24, width: 400, height: 310), zoom: 4, caption: "four notches in")
    }

    /// One view of the chart: the same drawing, through a different transform.
    func panel(_ frame: Rectangle, zoom: Double, caption: String) {
        let base = frame.height / ViewCloser.chart
        withClip(frame) {
            withState {
                translate(frame.center)
                scale(base * zoom, base * zoom)
                translate(zoom == 1 ? -Vector2(ViewCloser.chart / 2, ViewCloser.chart / 2)
                                    : -ViewCloser.focus)
                drawChart()
            }
        }
        noFill()
        stroke(ink.withAlpha(0.25))
        strokeWeight(1.5)
        drawRect(corner: frame.corner, width: frame.width, height: frame.height)
        noStroke()
        fill(faint)
        textSize(18)
        textAlign(.center, .top)
        drawText(caption, frame.center.x, frame.y + frame.height + 16)
    }

    func drawChart() {
        noStroke()
        fill(land)
        drawShape(Shape(coast))
        noFill()
        stroke(ink.withAlpha(0.3))
        strokeWeight(1.2)
        drawPolyline(coast, closed: true)
        for place in places {
            noStroke()
            fill(place.big ? mark : ink.withAlpha(0.6))
            drawCircle(center: place.at, radius: place.big ? 3.4 : 1.8)
            fill(ink.withAlpha(place.big ? 0.85 : 0.55))
            textSize(place.big ? 8 : 6)
            textAlign(.left, .center)
            drawText(place.name, place.at.x + (place.big ? 6 : 4.5), place.at.y)
        }
    }

    func onLand(_ p: Vector2) -> Bool {
        var inside = false
        var j = coast.count - 1
        for i in 0..<coast.count {
            let a = coast[i], b = coast[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
