// figure: frame=0
//
// Guide diagram (Chapter 23): one landscape read three ways. The contour map
// with its river network, the same ground split into basins, and the flow
// itself as a field. Seeded, so it renders the same every time.
import Ollin

final class WhereWaterGoes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.16)
    let accent = Color(hex: 0xE4572E)
    let river = Color(hex: 0x2E6B9E)

    override func draw() {
        background(paper)

        let land = Heightfield.diamondSquare(size: 129, roughness: 0.55, seed: 3)
            .eroded(.hydraulic(drops: 20_000), seed: 3)
        let water = land.drainage()

        let first = Rectangle(x: 26, y: 20, width: 250, height: 250)
        let second = Rectangle(x: 314, y: 20, width: 250, height: 250)
        let third = Rectangle(x: 602, y: 20, width: 250, height: 250)

        // The ground, and the network the ground decides.
        noFill()
        stroke(soft)
        strokeWeight(1)
        for level in 1 ... 9 {
            for line in isolines(at: Double(level) / 10, in: first, resolution: 120,
                                 field: { land.value(atU: first.uv(of: $0).x, v: first.uv(of: $0).y) }) {
                drawPolyline(line.points, closed: line.isClosed)
            }
        }
        strokeCap(.round)
        strokeJoin(.round)
        for reach in water.rivers(minimumFlow: 70, in: first) where reach.points.count >= 2 {
            stroke(river.withAlpha(0.45 + 0.12 * Double(min(reach.order, 4))))
            strokeWeight(0.5 + Double(reach.order) * 0.8)
            drawPolyline(reach.points)
        }

        // Whose ground is whose. The lines between them are the ridges,
        // and nothing here ever looked for a ridge.
        let cell = second.width / Double(water.columns)
        noStroke()
        for y in 0 ..< water.rows {
            for x in 0 ..< water.columns {
                let which = water.basin(x, y)
                guard which >= 0 else { continue }
                fill(Color(hue: Double(which) * 0.61803, saturation: 0.32, brightness: 0.86))
                drawRect(corner: water.point(x, y, in: second), width: cell + 0.7, height: cell + 0.7)
            }
        }

        // The flow itself, which the network is only a threshold of.
        let flow = water.flowField
        let loudest = flow.values.max() ?? 1
        for y in 0 ..< flow.rows {
            for x in 0 ..< flow.columns {
                let carried = log(1 + flow[x, y]) / log(1 + loudest)
                fill(Color.mix(paper, accent, t: carried))
                drawRect(corner: water.point(x, y, in: third), width: cell + 0.7, height: cell + 0.7)
            }
        }

        textSize(15)
        textAlign(.center)
        fill(ink)
        drawText("the network, thickened by order", first.center.x, 300)
        drawText("basins: who leaves by which door", second.center.x, 300)
        drawText("the flow it is a threshold of", third.center.x, 300)
        textSize(13)
        fill(ink.withAlpha(0.55))
        drawText("nothing decides where a river goes: the ground does", 440, 326)
    }
}
