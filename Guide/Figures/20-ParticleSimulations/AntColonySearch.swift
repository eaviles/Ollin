// Guide diagram (Chapter 20): one ant-colony search shown at three moments.
// The same seeded colony solves the same cities in every panel. After one
// iteration the pheromone web is a haze over every pair; a few iterations
// condense it; by sixty it has settled, and the best tour rides on top.
import Ollin

final class AntColonySearch: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)
    let accent = Color(hex: 0xE4572E)

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let panelStep = 273.0
    let stops = [1, 8, 60]

    override func draw() {
        background(Color(hex: 0x0B0D12))

        seed(7)
        let cities = poissonDisk(in: left.inset(by: .all(26)), radius: 56)
        let colony = AntColony(cities: cities, elitism: 2, seed: 7)

        for (panel, stop) in stops.enumerated() {
            colony.step(stop - colony.iterations)
            withState {
                translate(Double(panel) * panelStep, 0)
                strokeCap(.round)
                for trail in colony.trails {
                    stroke(ink.withAlpha(0.05 + trail.strength * 0.55))
                    strokeWeight(0.5 + trail.strength * 2.5)
                    drawLine(trail.a, trail.b)
                }
                if panel == stops.count - 1 {
                    stroke(accent)
                    strokeWeight(2)
                    noFill()
                    drawPolyline(colony.bestTourPoints, closed: true)
                }
                noStroke()
                fill(ink)
                for city in colony.cities {
                    drawCircle(city.x, city.y, 3.5)
                }
                frame(left, title: "iteration \(stop)")
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the haze over every pair condenses onto a tour", width / 2, 462)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
