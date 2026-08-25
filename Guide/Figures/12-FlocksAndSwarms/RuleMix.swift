// figure: frame=0 themed
//
// Guide figure (Chapter 12): the rules combine. The same boids, same seed,
// seven hundred steps later, run under one rule, then two, then all three.
// Each boid drags a short trail so the motion reads: separation alone keeps
// spacing but every heading is private, alignment lines the headings up, and
// cohesion gathers the lanes into groups.
import Ollin
import OllinDiagram

final class RuleMix: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.3) }
    var soft: Color { theme.ink(0.12) }

    var flocks: [Boids] = []
    var trails: [[[Vector2]]] = []      // per panel, per boid, recent positions

    // Each panel simulates in a roomier square and is drawn scaled down, so
    // the rules have space to organize before the walls interfere.
    let world = Rectangle(x: 0, y: 0, width: 560, height: 560)

    override func setup() {
        flocks = []
        trails = []
        for panel in 0 ..< 3 {
            let flock = Boids(count: 120, in: world, seed: 5,
                              maxSpeed: 2.6, maxForce: 0.08,
                              perceptionRadius: 56, separationRadius: 20, margin: 54)
            if panel < 2 { flock.cohesion = 0 } else { flock.cohesion = 1.4 }
            if panel < 1 { flock.alignment = 0 } else { flock.alignment = 1.3 }
            flock.step(560)

            var boidTrails = flock.positions.map { [$0] }
            for _ in 0 ..< 16 {
                flock.step()
                for b in 0 ..< flock.count { boidTrails[b].append(flock.positions[b]) }
            }
            flocks.append(flock)
            trails.append(boidTrails)
        }
    }

    /// Map a world point into panel `i`.
    func mapped(_ p: Vector2, _ i: Int) -> Vector2 {
        let r = panelRect(i)
        let k = r.width / world.width
        return Vector2(r.x + p.x * k, r.y + p.y * k)
    }

    func panelRect(_ i: Int) -> Rectangle {
        Rectangle(x: 50 + Double(i) * 265, y: 60, width: 250, height: 250)
    }

    override func draw() {
        background(paper)
        textSize(17)

        let titles = ["separation only", "+ alignment", "+ cohesion"]
        for (i, flock) in flocks.enumerated() {
            let r = panelRect(i)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)
            noStroke()
            fill(ink)
            textAlign(.left, .middle)
            drawText(titles[i], r.x + 2, r.y - 20)

            noFill()
            stroke(faint)
            strokeWeight(1.5)
            for trail in trails[i] {
                drawPolyline(trail.map { mapped($0, i) })
            }
            noStroke()
            fill(ink)
            for b in 0 ..< flock.count {
                withState {
                    translate(mapped(flock.positions[b], i))
                    rotate(flock.heading(b))
                    drawTriangle(Vector2(5.5, 0), Vector2(-3.6, 2.8), Vector2(-3.6, -2.8))
                }
            }
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same boids, the same seed, under one rule, then two, then three", width / 2, 345)
    }
}
