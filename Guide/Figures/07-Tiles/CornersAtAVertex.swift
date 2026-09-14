// figure: frame=0 themed
//
// Guide diagram (Chapter 7): why flat paper holds only three regular tilings,
// and where the rest go. Four vertices, each with the same regular polygon
// meeting around it: six triangles, four squares, and three hexagons each use
// up one full turn exactly, and four pentagons ask for 432 degrees, so the
// fourth one lands on the first. The last panel is the same four pentagons
// meeting in the Poincaré disk, where every corner is 90 degrees.
import Ollin
import OllinDiagram

final class CornersAtAVertex: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    // The tiles are depicted content, identical in both themes.
    let ivory = Color(hex: 0xF2E9DC)
    let indigo = Color(hex: 0x24476B)

    struct Corner {
        let sides: Int
        let meeting: Int
        let edge: Double
        var interior: Double { Double(sides - 2) * .pi / Double(sides) }
        var total: Double { Double(meeting) * interior }
        var fits: Bool { total <= .pi * 2 + 1e-9 }
    }

    let corners = [
        Corner(sides: 3, meeting: 6, edge: 46),
        Corner(sides: 4, meeting: 4, edge: 40),
        Corner(sides: 6, meeting: 3, edge: 33),
        Corner(sides: 5, meeting: 4, edge: 36),
    ]

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let side = 150.0, gap = 22.0, top = 72.0
        let left = (width - side * 5 - gap * 4) / 2

        for (i, corner) in corners.enumerated() {
            let panel = Rectangle(x: left + Double(i) * (side + gap), y: top, width: side, height: side)
            drawCorner(corner, in: panel)
            let degrees = Int((corner.interior * 180 / .pi).rounded())
            let sum = Int((corner.total * 180 / .pi).rounded())
            drawText("\(corner.meeting) × \(degrees)° = \(sum)°", panel.center.x, panel.y + side + 16,
                     size: 16, color: corner.fits ? theme.ink : theme.accent, align: .center, .top)
            drawText(corner.fits ? "a full turn, exactly" : "72° too many",
                     panel.center.x, panel.y + side + 40, size: 13, color: theme.muted, align: .center, .top)
        }

        let disk = Rectangle(x: left + 4 * (side + gap), y: top, width: side, height: side)
        drawDisk(in: disk)
        drawText("4 × 90° = 360°", disk.center.x, disk.y + side + 16,
                 size: 16, color: theme.ink, align: .center, .top)
        drawText("the same four, curved", disk.center.x, disk.y + side + 40,
                 size: 13, color: theme.muted, align: .center, .top)

        drawText("flat paper", left + (side * 3 + gap * 2) / 2, top - 26, size: 16, color: theme.ink,
                 align: .center, .middle)
        drawText("does not fit", left + 3 * (side + gap) + side / 2, top - 26, size: 16, color: theme.accent,
                 align: .center, .middle)
        drawText("the Poincaré disk", disk.center.x, top - 26, size: 16, color: theme.ink,
                 align: .center, .middle)

        diagramCaption("a corner gets one turn on flat paper; the disk has room for the rest",
                       at: 322, theme: theme)
        drawText("the rule: (sides − 2) × (meeting − 2) > 4 lives in the disk; = 4 is flat paper; < 4 closes into a solid",
                 width / 2, 356, size: 13, color: theme.muted, align: .center, .top)
    }

    /// The polygons around one vertex at the panel's center, laid edge to
    /// edge counterclockwise, each with one corner at the vertex.
    func drawCorner(_ corner: Corner, in panel: Rectangle) {
        let v = panel.center
        let n = corner.sides
        let circumradius = corner.edge / (2 * sin(.pi / Double(n)))
        var polygons: [[Vector2]] = []
        for i in 0 ..< corner.meeting {
            let start = -Double.pi / 2 + Double(i) * corner.interior
            let bisector = start + corner.interior / 2
            let center = v + Vector2(cos(bisector), sin(bisector)) * circumradius
            let back = bisector + .pi
            polygons.append((0 ..< n).map { k in
                let a = back + Double(k) * 2 * .pi / Double(n)
                return center + Vector2(cos(a), sin(a)) * circumradius
            })
        }

        noStroke()
        for (i, polygon) in polygons.enumerated() {
            let last = !corner.fits && i == corner.meeting - 1
            fill(last ? theme.accent(0.55) : (i % 2 == 0 ? ivory : indigo).withAlpha(0.9))
            drawPolygon(polygon)
        }
        noFill()
        stroke(theme.ink(0.55))
        strokeWeight(1.2)
        for polygon in polygons {
            drawPolyline(polygon, closed: true)
        }

        // The overflow: the wedge past a full turn, hatched in the accent.
        if !corner.fits {
            let from = -Double.pi / 2, to = from + corner.total - .pi * 2
            noStroke()
            fill(theme.accent)
            drawArc(v.x, v.y, 44, 44, start: from, stop: to, mode: .pie)
            stroke(theme.accent)
            strokeWeight(2)
            noFill()
            drawArc(v.x, v.y, 52, 52, start: from, stop: to, mode: .open)
        }

        // The vertex everything meets at.
        noStroke()
        fill(theme.ink)
        drawCircle(center: v, radius: 3.2)
    }

    /// {5,4} in the disk, panned so one vertex sits in the middle; the four
    /// pentagons around it are drawn full and the rest faded.
    func drawDisk(in panel: Rectangle) {
        let radius = panel.width / 2
        // The vertex to bring to the middle: a corner of the tile at the center.
        let first = hyperbolicTiling(sides: 5, meeting: 4, in: panel, minEdge: 2)
        let central = first.first { $0.depth == 0 } ?? first[0]
        let corner = (central.points[0] - panel.center) / radius
        let tiles = hyperbolicTiling(sides: 5, meeting: 4, in: panel, viewpoint: corner, minEdge: 2)

        noStroke()
        for tile in tiles {
            let atVertex = tile.points.contains { ($0 - panel.center).length < 1.5 }
            let base = tile.parity == 0 ? ivory : indigo
            fill(atVertex ? base : base.withAlpha(0.42))
            drawShape(tile.shape)
        }
        noFill()
        stroke(theme.ink(0.3))
        strokeWeight(0.8)
        for tile in tiles where tile.points.contains(where: { ($0 - panel.center).length < 1.5 }) {
            drawPolyline(tile.points, closed: true)
        }
        stroke(theme.border)
        strokeWeight(2)
        drawCircle(center: panel.center, radius: radius)
        noStroke()
        fill(theme.ink)
        drawCircle(center: panel.center, radius: 3.2)
    }
}
