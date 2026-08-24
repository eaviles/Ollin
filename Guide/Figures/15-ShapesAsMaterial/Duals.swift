// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the two structures hiding in one scatter.
// The same points; on the left the Voronoi cells (everything closest to
// each point), on the right the Delaunay triangulation (each point joined
// to its natural neighbors). Each is the other turned inside out.
import Ollin

final class Duals: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }

    override func draw() {
        background(paper)
        textSize(17)
        seed(11)

        let left = Rectangle(x: 50, y: 60, width: 370, height: 340)
        let right = Rectangle(x: 470, y: 60, width: 370, height: 340)

        let sites = poissonDisk(in: left.inset(by: .all(26)), radius: 62)
        let shifted = sites.map { Vector2($0.x + 420, $0.y) }

        panel(left, title: "Voronoi: each point's territory")
        let diagram = voronoi(sites, in: left.inset(by: .all(8)))
        noFill()
        stroke(ink)
        strokeWeight(1.6)
        for cell in diagram.cells {
            for contour in cell.contours { drawPolygon(contour.points) }
        }
        noStroke()
        fill(accent)
        drawCircles(sites, radius: 4.5)

        panel(right, title: "Delaunay: each point's neighbors")
        let triangulation = delaunay(shifted)
        noFill()
        stroke(ink)
        strokeWeight(1.6)
        for triangle in triangulation.triangles {
            drawPolygon(triangle.points)
        }
        noStroke()
        fill(accent)
        drawCircles(shifted, radius: 4.5)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one scatter, two structures: territories and neighbors", width / 2, 428)
    }

    func panel(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
