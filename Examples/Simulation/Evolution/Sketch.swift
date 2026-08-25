import Ollin

/// Thirty thousand attempts at the same journey, none of which knows where it is going.
/// Each one carries a genome (a short list of pushes, played back in order) and flies
/// it. Whoever ends the trial closest to the target is likelier to be a parent of the
/// next generation, and that is the whole mechanism: nobody is told the route, and the
/// route is found anyway, usually inside a dozen generations.
///
/// The first generation sprays in every direction. Watch the walls: the population
/// spends a few generations piling into them before a lucky genome slips through a gap,
/// and once one does, the crowd pours after it.
///
/// Drag to move the target, press `space` for a new set of walls, and `r` to start the
/// whole search over from scratch.
@main
final class Evolution_Example: Sketch {
    var run: Evolution!
    var layout = 0

    @Param(0.001 ... 0.2, icon: "dice") var mutationRate = 0.04
    @Param(2 ... 12, icon: "trophy") var tournament = 4

    let start = Vector2(540, 990)
    let goal = Vector2(540, 110)

    override func setup() {
        background(.black)
        noClear()
        // A population, a genome length, and two points. The speed, the length of a
        // trial, and how hard one gene pushes are all worked out from the distance
        // between those points, so none of them is written down here.
        run = evolution(count: 30_000, genes: 28, from: start, to: goal)
        run.measuresGenerations = true       // for the caption, once a generation
        applyLayout()
    }

    override func draw() {
        // A translucent sheet rather than a wipe, so a flight leaves the trail that
        // shows the route it took. (`background` clears outright, however little alpha
        // its color carries.) The sheet is thin because a whole flight takes over a
        // second: fade any faster and the first half of a route is gone before the
        // second half is drawn, which leaves the picture showing arrivals and no path.
        blendMode(.normal)
        noStroke()
        fill(Color(white: 0.02, alpha: 0.05))
        drawRect(0, 0, width, height)

        run.mutationRate = mutationRate
        run.tournament = Int(tournament)
        if mouseIsPressed { run.target = mouse }

        blendMode(.add)
        updateEvolution(run)
        drawParticles(run)

        blendMode(.normal)
        drawWalls()

        let reached = run.lastGeneration.map { " · \(Int($0.arrived * 100))% reached it" } ?? ""
        drawCaption("Evolution · generation \(run.generation) · 30,000 flights\(reached) · "
            + "drag to move the target, space for new walls, r to start over")
    }

    override func keyPressed() {
        if key == " " { layout = (layout + 1) % 3; applyLayout(); restart() }
        if key == "r" { restart() }
    }

    /// Breeding carries the population's learning, so starting over means a new one.
    private func restart() {
        run = evolution(count: 30_000, genes: 28, from: start, to: run.target,
                        seed: UInt64(variation &+ layout &+ frameCount))
        run.measuresGenerations = true
        run.obstacles = walls
        background(.black)
    }

    private var walls: [Rectangle] = []

    private func applyLayout() {
        switch layout {
        case 1:      // two staggered slots, so the route has to zigzag
            walls = [Rectangle(x: 0, y: 700, width: 700, height: 34),
                     Rectangle(x: 380, y: 420, width: 700, height: 34)]
        case 2:      // a funnel: the only way through is the middle
            walls = [Rectangle(x: 0, y: 560, width: 430, height: 34),
                     Rectangle(x: 650, y: 560, width: 430, height: 34),
                     Rectangle(x: 430, y: 250, width: 220, height: 34)]
        default:     // one wall with a gap off to the side
            walls = [Rectangle(x: 0, y: 620, width: 640, height: 34),
                     Rectangle(x: 800, y: 620, width: 280, height: 34)]
        }
        run.obstacles = walls
    }

    private func drawWalls() {
        noStroke()
        fill(Color(white: 0.26))
        for w in walls { drawRect(w) }
        // The target, and the ring that counts as reaching it.
        fill(Color(red: 1, green: 0.86, blue: 0.4, alpha: 0.9))
        drawCircle(center: run.target, radius: 7)
        noFill()
        stroke(Color(red: 1, green: 0.86, blue: 0.4, alpha: 0.35))
        strokeWeight(1.5)
        drawCircle(center: run.target, radius: run.targetRadius)
    }
}
